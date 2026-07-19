defmodule Cadence.ReplayTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Replay.{Run, Scope}

  alias Cadence.Persistence.Schemas.{
    ManagedActionRequestRow,
    ManagedCapabilityRecordRow,
    ManagedTimerEventRow,
    RawEvidenceRow,
    ReplayDispatchDecisionRow,
    ReplayDispatchWorkItemRow,
    ReplayManagedActionRequestRow,
    ReplayManagedCapabilityRecordRow,
    ReplayManagedTimerEventRow,
    ReplayRunRow,
    ReplayTelemetrySampleRow,
    TelemetryLatestValueRow,
    TelemetrySampleRow
  }

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  test "replays persisted evidence into replay tables without mutating live canonical data" do
    binding_set = persist_binding_set_fixture()

    raw_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        raw: build_space_packet(42, 2, <<0, 7>>)
      })

    assert {:ok, _live_result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    live_sample_count = Repo.aggregate(TelemetrySampleRow, :count, :sample_id)
    live_latest_count = Repo.aggregate(TelemetryLatestValueRow, :count, :id)

    assert {:ok, replay_run} =
             Cadence.replay_telemetry_evidence(
               "mission-alpha",
               raw_evidence.evidence_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert replay_run.status == :completed
    assert replay_run.replayed_evidence_count == 1
    assert replay_run.replayed_packet_count == 1
    assert replay_run.replayed_sample_count == 1

    assert Repo.aggregate(ReplayRunRow, :count, :replay_run_id) == 1
    assert Repo.aggregate(ReplayDispatchDecisionRow, :count, :dispatch_decision_id) == 1
    assert Repo.aggregate(ReplayDispatchWorkItemRow, :count, :id) == 1
    assert Repo.aggregate(ReplayTelemetrySampleRow, :count, :sample_id) == 1

    assert Repo.aggregate(TelemetrySampleRow, :count, :sample_id) == live_sample_count
    assert Repo.aggregate(TelemetryLatestValueRow, :count, :id) == live_latest_count

    assert {:ok, fetched_run} = Cadence.fetch_replay_run(replay_run.replay_run_id)
    assert fetched_run.status == :completed
    assert fetched_run.replayed_sample_count == 1

    replay_samples = Cadence.replay_telemetry_samples(replay_run.replay_run_id)
    assert Enum.map(replay_samples, & &1.raw_value) == [7]

    diff_report = Cadence.diff_replay_run(replay_run.replay_run_id)
    assert diff_report.compared_count == 1
    assert diff_report.matching_count == 1
    assert diff_report.mismatches == []
    assert diff_report.missing_live == []
    assert diff_report.extra_live == []
  end

  test "lists replay runs for an organization and mission newest first" do
    persist_mission_scope("org-replay-list", "mission-replay-list")
    persist_mission_scope("org-replay-list", "mission-replay-other")

    older_run =
      replay_run("mission-replay-list", "replay-run-older", ~U[2026-06-17 11:00:00Z])

    newer_run =
      replay_run("mission-replay-list", "replay-run-newer", ~U[2026-06-17 12:00:00Z])

    other_mission_run =
      replay_run("mission-replay-other", "replay-run-other", ~U[2026-06-17 13:00:00Z])

    Repo.insert!(ReplayRunRow.changeset(older_run))
    Repo.insert!(ReplayRunRow.changeset(newer_run))
    Repo.insert!(ReplayRunRow.changeset(other_mission_run))

    assert ["replay-run-newer", "replay-run-older"] =
             "org-replay-list"
             |> Cadence.list_replay_runs("mission-replay-list")
             |> Enum.map(& &1.replay_run_id)

    assert ["replay-run-older"] =
             "org-replay-list"
             |> Cadence.list_replay_runs("mission-replay-list", order: :asc, limit: 1)
             |> Enum.map(& &1.replay_run_id)
  end

  test "replays an async scoped run over a filtered evidence window" do
    binding_set = persist_binding_set_fixture()

    older_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        spacecraft_id: "sc-1",
        receipt_time: DateTime.from_unix!(1_700_000_100, :second),
        raw: build_space_packet(42, 1, <<0, 10>>)
      })

    newer_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        spacecraft_id: "sc-2",
        receipt_time: DateTime.from_unix!(1_700_000_200, :second),
        raw: build_space_packet(42, 2, <<0, 20>>)
      })

    assert {:ok, _older_result} =
             Cadence.process_and_persist_telemetry_ingress(
               older_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, _newer_result} =
             Cadence.process_and_persist_telemetry_ingress(
               newer_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    scope =
      Scope.new(%{
        from_receipt_time: DateTime.from_unix!(1_700_000_150, :second),
        spacecraft_id: "sc-2"
      })

    assert {:ok, replay_run} =
             Cadence.start_replay_telemetry_scope(
               "mission-alpha",
               scope,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert replay_run.status == :running
    assert {:ok, queued_job} = Cadence.fetch_replay_job(replay_run.replay_run_id)
    assert queued_job.status == :queued

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert claimed_job.run_id == replay_run.replay_run_id

    assert {:ok, completed_job} = Cadence.Jobs.run_job(claimed_job.job_id)
    assert completed_job.status == :completed

    assert {:ok, completed_run} = Cadence.fetch_replay_run(replay_run.replay_run_id)

    assert completed_run.replayed_evidence_count == 1
    assert completed_run.replayed_packet_count == 1
    assert completed_run.replayed_sample_count == 1

    replay_samples = Cadence.replay_telemetry_samples(replay_run.replay_run_id)
    assert completed_job.job_type == :replay_telemetry_scope
    assert completed_job.attempt_count == 1
    assert Enum.map(replay_samples, & &1.raw_value) == [20]
  end

  test "reports replay mismatches against live canonical telemetry" do
    binding_set = persist_binding_set_fixture()

    raw_evidence =
      RawEvidence.new(%{
        mission_id: "mission-alpha",
        raw: build_space_packet(42, 3, <<0, 33>>)
      })

    assert {:ok, _live_result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {1, nil} =
             Repo.update_all(
               from(sample_row in TelemetrySampleRow,
                 where: sample_row.evidence_id == ^raw_evidence.evidence_id
               ),
               set: [raw_value: %{"value" => 99}, engineering_value: %{"value" => 99}]
             )

    assert {:ok, replay_run} =
             Cadence.replay_telemetry_evidence(
               "mission-alpha",
               raw_evidence.evidence_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    diff_report = Cadence.diff_replay_run(replay_run.replay_run_id)

    assert diff_report.compared_count == 1
    assert diff_report.matching_count == 0

    assert diff_report.mismatches == [
             %{
               evidence_id: raw_evidence.evidence_id,
               point_id: "HK.counter",
               replay_raw_value: 33,
               live_raw_value: 99,
               replay_engineering_value: 33,
               live_engineering_value: 99,
               replay_quality_state: "good",
               live_quality_state: "good"
             }
           ]
  end

  test "replays managed capability runtime records into replay tables and operational events" do
    mission_id = "mission-managed-replay"
    source_endpoint = persist_source_endpoint(mission_id)

    binding_set =
      persist_packet_counter_binding_set(mission_id, source_endpoint.source_endpoint_id)

    raw_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_endpoint_ref: source_endpoint.source_endpoint_id,
        spacecraft_id: source_endpoint.spacecraft_id,
        source_ref: source_endpoint.source_ref,
        receipt_time: DateTime.from_unix!(1_700_001_000, :second),
        raw: build_space_packet(42, 4, <<0, 1>>)
      })

    assert {:ok, _row} = Repo.insert(RawEvidenceRow.changeset(raw_evidence))

    live_capability_record_count =
      Repo.aggregate(ManagedCapabilityRecordRow, :count, :capability_record_id)

    live_action_request_count =
      Repo.aggregate(ManagedActionRequestRow, :count, :action_request_id)

    live_timer_event_count =
      Repo.aggregate(ManagedTimerEventRow, :count, :timer_event_id)

    assert {:ok, replay_run} =
             Cadence.replay_telemetry_evidence(
               mission_id,
               raw_evidence.evidence_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert replay_run.status == :completed
    assert replay_run.replayed_evidence_count == 1
    assert replay_run.replayed_packet_count == 1
    assert replay_run.replayed_sample_count == 0

    assert Repo.aggregate(ReplayManagedCapabilityRecordRow, :count, :capability_record_id) == 3
    assert Repo.aggregate(ReplayManagedActionRequestRow, :count, :action_request_id) == 1
    assert Repo.aggregate(ReplayManagedTimerEventRow, :count, :timer_event_id) == 2

    assert Repo.aggregate(ManagedCapabilityRecordRow, :count, :capability_record_id) ==
             live_capability_record_count

    assert Repo.aggregate(ManagedActionRequestRow, :count, :action_request_id) ==
             live_action_request_count

    assert Repo.aggregate(ManagedTimerEventRow, :count, :timer_event_id) == live_timer_event_count

    capability_records = Cadence.replay_managed_capability_records(replay_run.replay_run_id)
    assert length(capability_records) == 3

    assert Enum.map(capability_records, & &1.family_key) == [
             :packet_counter,
             :packet_counter,
             :packet_counter
           ]

    assert Enum.sort(Enum.map(capability_records, & &1.event_kind)) == [
             :initialized,
             :record_handled,
             :timer_handled
           ]

    initialized_record = Enum.find(capability_records, &(&1.event_kind == :initialized))
    handled_record = Enum.find(capability_records, &(&1.event_kind == :record_handled))
    timer_handled_record = Enum.find(capability_records, &(&1.event_kind == :timer_handled))

    assert DateTime.compare(initialized_record.recorded_at, raw_evidence.receipt_time) == :eq
    assert DateTime.compare(handled_record.recorded_at, raw_evidence.receipt_time) == :eq

    action_requests = Cadence.replay_managed_action_requests(replay_run.replay_run_id)
    assert Enum.map(action_requests, & &1.action_kind) == [:schedule_timer]
    assert Enum.map(action_requests, & &1.request_document["timer_key"]) == ["flush"]
    assert DateTime.compare(hd(action_requests).requested_at, raw_evidence.receipt_time) == :eq

    timer_events = Cadence.replay_managed_timer_events(replay_run.replay_run_id)
    assert Enum.map(timer_events, & &1.event_kind) == [:scheduled, :fired]
    assert Enum.map(timer_events, & &1.timer_key) == ["flush", "flush"]

    [scheduled_timer_event, fired_timer_event] = timer_events

    assert DateTime.compare(
             scheduled_timer_event.due_at,
             DateTime.add(raw_evidence.receipt_time, 25, :millisecond)
           ) == :eq

    assert DateTime.compare(fired_timer_event.occurred_at, scheduled_timer_event.due_at) == :eq

    assert DateTime.compare(timer_handled_record.recorded_at, fired_timer_event.occurred_at) ==
             :eq

    replay_runtime_events =
      Cadence.list_operational_events(mission_id,
        category: :runtime,
        replay_run_id: replay_run.replay_run_id,
        limit: 20,
        order: :asc
      )

    assert length(replay_runtime_events) == 6

    assert Enum.all?(
             replay_runtime_events,
             &(&1.actor == %{kind: :replay, id: replay_run.replay_run_id})
           )

    assert Enum.all?(
             replay_runtime_events,
             &(map_value(&1.causality, :replay_run_id) == replay_run.replay_run_id)
           )

    assert Enum.all?(
             replay_runtime_events,
             &(map_value(&1.scope, :replay_run_id) == replay_run.replay_run_id)
           )

    assert Enum.frequencies_by(replay_runtime_events, & &1.kind) == %{
             managed_action_requested: 1,
             managed_capability_initialized: 1,
             managed_capability_record_handled: 1,
             managed_capability_timer_handled: 1,
             managed_timer_fired: 1,
             managed_timer_scheduled: 1
           }

    assert Enum.frequencies_by(
             replay_runtime_events,
             &map_value(&1.causality, :source_record_kind)
           ) == %{
             managed_action_request: 1,
             managed_capability_record: 3,
             managed_timer_event: 2
           }

    assert Enum.map(replay_runtime_events, & &1.subject.kind) |> Enum.uniq() == [
             :capability_instance
           ]
  end

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp persist_binding_set_fixture do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_definition_id: "hk-replay",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "mission-alpha-replay",
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

    assert {:ok, ^binding_set} = Cadence.persist_binding_set(binding_set)
    binding_set
  end

  defp replay_run(mission_id, replay_run_id, started_at) do
    Run.new(%{
      replay_run_id: replay_run_id,
      mission_id: mission_id,
      binding_set_id: mission_id <> "-binding-set",
      binding_set_version: 1,
      status: :completed,
      replayed_evidence_count: 1,
      replayed_packet_count: 1,
      replayed_sample_count: 1,
      started_at: started_at,
      completed_at: DateTime.add(started_at, 60, :second)
    })
  end

  defp persist_packet_counter_binding_set(mission_id, source_endpoint_ref) do
    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "managed-replay-basis",
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: "packet-counter-managed-replay",
            family_key: :packet_counter,
            target_scope: :source_endpoint,
            source_endpoint_ref: source_endpoint_ref,
            capability_config:
              CapabilityConfig.inline(%{
                "metric_name" => "packet_window",
                "flush_interval_ms" => 25
              })
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: "packet-counter-replay-rule",
            capability_instance_id: "packet-counter-managed-replay",
            selector: %{
              scope: %{target_scope: :source_endpoint, source_endpoint_ref: source_endpoint_ref},
              match: %{packet_kind: :space_packet, apid: 42}
            },
            fanout_mode: :multi,
            priority: 10
          })
        ]
      })

    assert {:ok, ^binding_set} = Cadence.persist_binding_set(binding_set)
    binding_set
  end

  defp persist_source_endpoint(mission_id) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-" <> mission_id,
        mission_id: mission_id,
        display_name: "SC " <> mission_id
      })

    assert {:ok, _persisted_spacecraft} = Cadence.SpacecraftStore.persist_spacecraft(spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-" <> mission_id,
        mission_id: mission_id,
        spacecraft_id: "sc-" <> mission_id,
        source_ref: "provider/" <> mission_id
      })

    assert {:ok, ^source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(source_endpoint)

    source_endpoint
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
end
