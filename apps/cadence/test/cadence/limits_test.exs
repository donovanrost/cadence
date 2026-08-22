defmodule Cadence.LimitsTest do
  alias Cadence.Jobs.Runner, as: JobRunner

  alias Cadence.Control.DerivedTelemetry, as: DerivedTelemetryService
  alias Cadence.Jobs
  alias Cadence.Reads.DerivedTelemetry, as: DerivedTelemetryReads
  alias Cadence.Reads.Limits, as: LimitReads
  use Cadence.ConfigCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}

  alias Cadence.Dashboards.{
    Frame,
    PlannedSourceRequest,
    RuntimeCache,
    RuntimeCacheKey,
    RuntimeFactConsumer,
    SourceResult
  }

  alias Cadence.DataSources.SourceWatermark

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.DerivedTelemetry.Definition, as: DerivedTelemetryDefinition
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits
  alias Cadence.Limits.Definition, as: LimitDefinition
  alias Cadence.Limits.Facts, as: LimitFacts
  alias Cadence.Platform.EventBus
  alias Cadence.Telemetry.PacketDefinition

  test "owns versioned limit definition persistence and scoped reads" do
    organization_id = "org-limit-definitions"
    mission_id = "mission-limit-definitions"
    persist_mission_scope(organization_id, mission_id)

    first_definition =
      LimitDefinition.new(%{
        mission_id: mission_id,
        limit_definition_id: "counter-limits",
        point_id: "HK.counter",
        version: 1,
        thresholds: %{"yellow_high" => 10}
      })

    latest_definition =
      LimitDefinition.new(%{
        mission_id: mission_id,
        limit_definition_id: "counter-limits",
        point_id: "HK.counter",
        version: 2,
        thresholds: %{"yellow_high" => 20}
      })

    assert {:ok, ^first_definition} = Limits.persist_limit_definition(first_definition)
    assert {:ok, ^latest_definition} = Limits.persist_limit_definition(latest_definition)
    assert [^latest_definition] = Limits.list_limit_definitions(mission_id)

    assert {:ok, ^first_definition} =
             Limits.fetch_limit_definition(
               organization_id,
               mission_id,
               "counter-limits",
               1
             )

    assert {:ok, ^latest_definition} =
             Limits.fetch_latest_limit_definition(
               organization_id,
               mission_id,
               "counter-limits"
             )

    assert [^first_definition, ^latest_definition] =
             organization_id
             |> Limits.list_limit_definition_versions(
               mission_id,
               [{"counter-limits", 1}, {"counter-limits", 2}]
             )
             |> Enum.sort_by(& &1.version)

    assert {:error, :limit_definition_not_found} =
             Limits.fetch_limit_definition(
               organization_id,
               mission_id,
               "counter-limits",
               3
             )
  end

  test "evaluates governed telemetry limits over derived telemetry in an async job" do
    event_bus = start_event_bus()
    assert :ok = LimitFacts.subscribe(event_bus, self())

    binding_set = persist_binding_set_fixture()

    derived_definition =
      DerivedTelemetryDefinition.new(%{
        mission_id: "mission-alpha",
        derived_definition_id: "counter-double",
        point_id: "DERIVED.counter_double",
        point_name: "DERIVED.counter_double",
        expression: "HK.counter * 2"
      })

    limit_definition =
      LimitDefinition.new(%{
        mission_id: "mission-alpha",
        limit_definition_id: "derived-counter-limits",
        point_id: "DERIVED.counter_double",
        limit_set_name: "ops",
        thresholds: %{"yellow_high" => 50, "red_high" => 70}
      })

    assert {:ok, ^derived_definition} =
             Cadence.Governance.persist_derived_definition(derived_definition)

    assert {:ok, ^limit_definition} = Cadence.Limits.persist_limit_definition(limit_definition)
    assert [persisted_limit_definition] = Cadence.Limits.list_limit_definitions("mission-alpha")
    assert persisted_limit_definition.limit_set_name == "ops"

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(1, 10, 1_700_000_200),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(2, 30, 1_700_000_210),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, derived_run} = DerivedTelemetryService.evaluate("mission-alpha")
    assert derived_run.status == :completed

    assert DerivedTelemetryReads.latest_value("mission-alpha", "DERIVED.counter_double").value ==
             60

    assert {:ok, run} = Limits.start_evaluate("mission-alpha")
    assert run.status == :running

    assert {:ok, queued_job} =
             Jobs.fetch_job_for_run(:telemetry_limit_evaluation, run.limit_run_id)

    assert queued_job.status == :queued

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert claimed_job.run_id == run.limit_run_id

    runner =
      JobRunner.new(%{
        telemetry_limit_evaluation: fn limit_run_id ->
          Limits.execute_enqueued_run(limit_run_id, event_bus: event_bus)
        end
      })

    assert {:ok, completed_job} = JobRunner.run_job(runner, claimed_job.job_id)
    assert completed_job.status == :completed
    assert completed_job.job_type == :telemetry_limit_evaluation
    assert completed_job.attempt_count == 1

    assert {:ok, completed_run} = Limits.fetch_run(run.limit_run_id)
    assert completed_run.status == :completed
    assert completed_run.evaluated_sample_count == 4
    assert completed_run.emitted_event_count == 2
    assert completed_run.definition_count == 1

    published_events =
      for _index <- 1..2 do
        assert_receive {:"$gen_cast",
                        {:cadence_fact, {:cadence, :limits, :facts},
                         %Cadence.Limits.Event{} = event}}

        event
      end

    assert Enum.map(published_events, & &1.limit_state) == [:green, :yellow_high]
    refute_receive {:"$gen_cast", {:cadence_fact, {:cadence, :limits, :facts}, _fact}}

    event_history =
      LimitReads.event_history("mission-alpha", "DERIVED.counter_double")

    assert Enum.map(event_history, & &1.limit_state) == [:yellow_high, :green]

    bounded_event_history =
      LimitReads.event_history("mission-alpha", "DERIVED.counter_double",
        from_receipt_time: DateTime.from_unix!(1_700_000_200),
        to_receipt_time: DateTime.from_unix!(1_700_000_205)
      )

    assert Enum.map(bounded_event_history, & &1.limit_state) == [:green]

    as_of_state =
      LimitReads.latest_state("mission-alpha", "DERIVED.counter_double",
        to_receipt_time: DateTime.from_unix!(1_700_000_205)
      )

    assert as_of_state.limit_state == :green
    assert as_of_state.normalized_state == :green

    latest_state =
      LimitReads.latest_state("mission-alpha", "DERIVED.counter_double")

    assert latest_state.limit_state == :yellow_high
    assert latest_state.normalized_state == :yellow
    assert latest_state.violation
    assert latest_state.evaluated_value == 60

    assert {:ok, watermark} =
             LimitReads.watermark_result("mission-alpha", "DERIVED.counter_double")

    assert watermark.confidence == :best_effort

    assert DateTime.compare(watermark.latest_receipt_time, DateTime.from_unix!(1_700_000_210)) ==
             :eq

    assert DateTime.compare(watermark.complete_through, DateTime.from_unix!(1_700_000_210)) ==
             :eq

    assert DateTime.compare(watermark.retention_starts_at, DateTime.from_unix!(1_700_000_200)) ==
             :eq

    assert watermark.sample_count == 3
    assert watermark.projection_sources == %{event_count: 2, latest_state_count: 1}
  end

  test "persisting a limit definition invalidates matching dashboard runtime caches" do
    cache = start_supervised!({RuntimeCache, name: nil})

    start_supervised!(
      {RuntimeFactConsumer, name: nil, enabled?: true, runtime_cache: RuntimeCache.client(cache)}
    )

    persist_mission_scope("org-limit-cache", "mission-limit-cache")

    limits_key = dashboard_source_result_key(:limits, "HK.counter")
    limits_frame_key = dashboard_frame_key(:limits, "HK.counter")
    other_limits_key = dashboard_source_result_key(:limits, "HK.temperature")
    other_limits_frame_key = dashboard_frame_key(:limits, "HK.temperature")
    telemetry_key = dashboard_source_result_key(:telemetry, "HK.counter")
    telemetry_frame_key = dashboard_frame_key(:telemetry, "HK.counter")

    limits_result = dashboard_source_result()
    limits_frames = dashboard_frames(:limits, "frame-limits-counter")
    other_limits_result = dashboard_source_result()
    other_limits_frames = dashboard_frames(:limits, "frame-limits-temperature")
    telemetry_result = dashboard_source_result()
    telemetry_frames = dashboard_frames(:telemetry, "frame-telemetry-counter")

    assert :ok = RuntimeCache.put_source_result(limits_key, limits_result, cache)
    assert :ok = RuntimeCache.put_frame(limits_frame_key, limits_frames, cache)
    assert :ok = RuntimeCache.put_source_result(other_limits_key, other_limits_result, cache)
    assert :ok = RuntimeCache.put_frame(other_limits_frame_key, other_limits_frames, cache)
    assert :ok = RuntimeCache.put_source_result(telemetry_key, telemetry_result, cache)
    assert :ok = RuntimeCache.put_frame(telemetry_frame_key, telemetry_frames, cache)

    limit_definition_id = "counter-limits-#{System.unique_integer([:positive])}"

    limit_definition =
      LimitDefinition.new(%{
        mission_id: "mission-limit-cache",
        limit_definition_id: limit_definition_id,
        point_id: "HK.counter",
        thresholds: %{"yellow_high" => 10, "red_high" => 20}
      })

    assert {:ok, ^limit_definition} = Cadence.Limits.persist_limit_definition(limit_definition)

    assert RuntimeCache.get_source_result(limits_key, cache) == :miss
    assert RuntimeCache.get_frame(limits_frame_key, cache) == :miss
    assert {:ok, ^other_limits_result} = RuntimeCache.get_source_result(other_limits_key, cache)
    assert {:ok, ^other_limits_frames} = RuntimeCache.get_frame(other_limits_frame_key, cache)
    assert {:ok, ^telemetry_result} = RuntimeCache.get_source_result(telemetry_key, cache)
    assert {:ok, ^telemetry_frames} = RuntimeCache.get_frame(telemetry_frame_key, cache)
  end

  defp persist_binding_set_fixture do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_definition_id: "hk-limits",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "mission-alpha-limits",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, ^binding_set} = Cadence.Governance.persist_binding_set(binding_set)
    binding_set
  end

  defp raw_evidence_fixture(sequence_count, counter_value, receipt_unix) do
    RawEvidence.new(%{
      mission_id: "mission-alpha",
      receipt_time: DateTime.from_unix!(receipt_unix, :second),
      raw: build_space_packet(42, sequence_count, <<counter_value::16>>)
    })
  end

  defp start_event_bus do
    start_supervised!(%{
      id: {:limits_event_bus, make_ref()},
      start: {EventBus, :start_link, [[name: nil, delivery: :async, before_notify: nil]]},
      restart: :temporary
    })
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      sequence_count::14,
      packet_length::16,
      packet_data::binary
    >>
  end

  defp dashboard_source_result_key(logical_source, observable) do
    request = dashboard_source_request(logical_source, observable)

    RuntimeCacheKey.source_result(request,
      source_binding: dashboard_source_binding(logical_source),
      data_source: dashboard_data_source(logical_source),
      watermark: dashboard_watermark(logical_source)
    )
  end

  defp dashboard_frame_key(logical_source, observable) do
    logical_source
    |> dashboard_source_result_key(observable)
    |> RuntimeCacheKey.frame(
      placement_id: "placement_#{logical_source}_#{observable}",
      placement_size: %{width_px: 320, height_px: 120},
      display: %{density: :normal},
      frame_shape: :scalar
    )
  end

  defp dashboard_source_request(logical_source, observable) do
    %PlannedSourceRequest{
      request_id: "source_req_#{logical_source}_#{observable}",
      organization_id: "org-limit-cache",
      mission_id: "mission-limit-cache",
      logical_source: logical_source,
      observables: [observable],
      sampling: %{mode: :latest}
    }
  end

  defp dashboard_source_binding(logical_source) do
    %DataBinding{
      binding_id: dashboard_binding_id(logical_source),
      organization_id: "org-limit-cache",
      mission_id: "mission-limit-cache",
      realm: :flight,
      logical_source: logical_source,
      data_source_id: dashboard_data_source_id(logical_source),
      dataset: dashboard_dataset(logical_source)
    }
  end

  defp dashboard_data_source(logical_source) do
    %DataSource{
      data_source_id: dashboard_data_source_id(logical_source),
      adapter: dashboard_source_adapter(logical_source),
      capabilities: %{latest?: true, latest_state?: true, event_history?: true, watermarks?: true}
    }
  end

  defp dashboard_watermark(logical_source) do
    %SourceWatermark{
      logical_source: logical_source,
      request_id: "source_req_#{logical_source}",
      source_binding_id: dashboard_binding_id(logical_source),
      data_source_id: dashboard_data_source_id(logical_source),
      realm: :flight,
      dataset: dashboard_dataset(logical_source),
      complete_through: ~U[2026-06-17 12:00:00Z],
      latest_receipt_time: ~U[2026-06-17 12:00:00Z],
      retention_starts_at: ~U[2026-06-17 11:00:00Z],
      confidence: :best_effort,
      freshness_state: :fresh
    }
  end

  defp dashboard_source_result do
    %SourceResult{request_id: "source_req_limits", watermarks: []}
  end

  defp dashboard_frames(logical_source, frame_id) do
    [%Frame{frame_id: frame_id, source: logical_source, shape: :scalar, fields: []}]
  end

  defp dashboard_binding_id(:limits), do: "default_flight_limits"
  defp dashboard_binding_id(:telemetry), do: "default_flight_telemetry"

  defp dashboard_data_source_id(:limits), do: "managed_limits_projection"
  defp dashboard_data_source_id(:telemetry), do: "managed_questdb_primary"

  defp dashboard_dataset(:limits), do: "telemetry_latest_limit_states"
  defp dashboard_dataset(:telemetry), do: "flight"

  defp dashboard_source_adapter(:limits), do: Cadence.Dashboards.Sources.Limits
  defp dashboard_source_adapter(:telemetry), do: Cadence.Dashboards.Sources.Telemetry
end
