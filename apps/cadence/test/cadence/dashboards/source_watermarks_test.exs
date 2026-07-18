defmodule Cadence.Dashboards.SourceWatermarksTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    PlannedSourceRequest,
    SourceFacts,
    SourceRegistry,
    SourceResult,
    SourceWatermark,
    SourceWatermarks
  }

  alias Cadence.Telemetry.Sample

  @organization_id "org-source-watermarks"
  @mission_id "mission-source-watermarks"
  @source_identity %{
    organization_id: @organization_id,
    mission_id: @mission_id,
    logical_source: :telemetry,
    data_source_id: "flight-questdb",
    source_binding_id: "flight-telemetry",
    realm: :flight,
    dataset: "flight"
  }

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    :ok
  end

  test "records source watermark transitions and maintains latest status projection" do
    assert {:ok, observed_event, observed_status} =
             @source_identity
             |> Map.merge(%{
               complete_through: ~U[2026-06-21 12:00:00Z],
               latest_receipt_time: ~U[2026-06-21 12:00:00Z],
               retention_starts_at: ~U[2026-06-21 11:00:00Z],
               sample_count: 10,
               confidence: :best_effort,
               reason: :telemetry_storage_write,
               observed_at: ~U[2026-06-21 12:00:01Z],
               payload: %{write_id: "write-1"}
             })
             |> SourceWatermarks.record_source_watermark(invalidate_runtime_cache?: false)

    assert observed_event.event_type == :observed
    assert observed_status.complete_through == ~U[2026-06-21 12:00:00.000000Z]
    assert observed_status.latest_receipt_time == ~U[2026-06-21 12:00:00.000000Z]
    assert observed_status.retention_starts_at == ~U[2026-06-21 11:00:00.000000Z]
    assert observed_status.sample_count == 10
    assert observed_status.transition_count == 1

    assert {:ok, :unchanged, unchanged_status} =
             @source_identity
             |> Map.merge(%{
               complete_through: ~U[2026-06-21 12:00:00Z],
               latest_receipt_time: ~U[2026-06-21 12:00:00Z],
               retention_starts_at: ~U[2026-06-21 11:30:00Z],
               sample_count: 10,
               confidence: :best_effort,
               reason: :telemetry_storage_write,
               observed_at: ~U[2026-06-21 12:00:10Z],
               payload: %{write_id: "write-2"}
             })
             |> SourceWatermarks.record_source_watermark(invalidate_runtime_cache?: false)

    assert unchanged_status.source_watermark_event_id == observed_event.source_watermark_event_id
    assert unchanged_status.retention_starts_at == ~U[2026-06-21 11:00:00.000000Z]
    assert unchanged_status.last_seen_at == ~U[2026-06-21 12:00:10.000000Z]

    assert {:ok, advanced_event, advanced_status} =
             @source_identity
             |> Map.merge(%{
               complete_through: ~U[2026-06-21 12:05:00Z],
               latest_receipt_time: ~U[2026-06-21 12:05:00Z],
               retention_starts_at: ~U[2026-06-21 11:45:00Z],
               sample_count: 5,
               confidence: :authoritative,
               reason: :telemetry_storage_write,
               observed_at: ~U[2026-06-21 12:05:01Z],
               payload: %{write_id: "write-3"}
             })
             |> SourceWatermarks.record_source_watermark(invalidate_runtime_cache?: false)

    assert advanced_event.event_type == :advanced
    assert advanced_event.previous_complete_through == ~U[2026-06-21 12:00:00.000000Z]
    assert advanced_status.complete_through == ~U[2026-06-21 12:05:00.000000Z]
    assert advanced_status.retention_starts_at == ~U[2026-06-21 11:00:00.000000Z]
    assert advanced_status.transition_count == 2

    assert [latest_status] =
             SourceWatermarks.list_source_watermark_statuses(@organization_id, @mission_id)

    assert latest_status.source_watermark_event_id == advanced_event.source_watermark_event_id

    assert [latest_event, first_event] =
             SourceWatermarks.list_source_watermark_events(@organization_id, @mission_id)

    assert latest_event.event_type == :advanced
    assert first_event.event_type == :observed

    assert [operational_event] =
             Cadence.list_operational_events(
               @organization_id,
               @mission_id,
               category: :data_source,
               kind: :source_watermark_observed,
               source_record_kind: :source_watermark_event,
               source_record_id: observed_event.source_watermark_event_id
             )

    assert operational_event.event_id ==
             "operational_event:source_watermark_event:#{observed_event.source_watermark_event_id}"

    assert operational_event.occurred_at == ~U[2026-06-21 12:00:01.000000Z]
    assert operational_event.effective_at == ~U[2026-06-21 12:00:01.000000Z]
    assert operational_event.severity == :info
    assert operational_event.subject == %{kind: :data_source, id: "flight-questdb"}
    assert operational_event.causality.source_record_kind == :source_watermark_event

    assert operational_event.causality.source_record_id ==
             observed_event.source_watermark_event_id

    assert operational_event.payload["event_type"] == "observed"
    assert operational_event.payload["logical_source"] == "telemetry"
    assert operational_event.payload["confidence"] == "best_effort"
    assert operational_event.current["confidence"] == "best_effort"
    assert operational_event.current["sample_count"] == 10
  end

  test "keeps replay-run source watermarks isolated in status identity" do
    for replay_run_id <- ["replay-run-1", "replay-run-2"] do
      assert {:ok, event, status} =
               @source_identity
               |> Map.merge(%{
                 realm: :replay,
                 replay_run_id: replay_run_id,
                 complete_through: ~U[2026-06-21 12:00:00Z],
                 latest_receipt_time: ~U[2026-06-21 12:00:00Z],
                 retention_starts_at: ~U[2026-06-21 11:00:00Z],
                 sample_count: 1,
                 confidence: :best_effort,
                 reason: :telemetry_storage_write,
                 observed_at: ~U[2026-06-21 12:00:01Z]
               })
               |> SourceWatermarks.record_source_watermark(invalidate_runtime_cache?: false)

      assert event.replay_run_id == replay_run_id
      assert status.replay_run_id == replay_run_id
    end

    statuses =
      SourceWatermarks.list_source_watermark_statuses(@organization_id, @mission_id,
        realm: :replay
      )

    assert Enum.map(statuses, & &1.replay_run_id) |> Enum.sort() == [
             "replay-run-1",
             "replay-run-2"
           ]

    assert [replay_one_status] =
             SourceWatermarks.list_source_watermark_statuses(@organization_id, @mission_id,
               realm: :replay,
               replay_run_id: "replay-run-1"
             )

    assert replay_one_status.source_watermark_key !=
             statuses
             |> Enum.find(&(&1.replay_run_id == "replay-run-2"))
             |> Map.fetch!(:source_watermark_key)

    assert [replay_one_event] =
             SourceWatermarks.list_source_watermark_events(@organization_id, @mission_id,
               realm: :replay,
               replay_run_id: "replay-run-1"
             )

    assert replay_one_event.replay_run_id == "replay-run-1"
  end

  test "source registry facts prefer durable source watermark when enabled" do
    request = source_request()

    assert {:ok, _event, _status} =
             @source_identity
             |> Map.merge(%{
               complete_through: ~U[2026-06-21 14:00:00Z],
               latest_receipt_time: ~U[2026-06-21 14:00:00Z],
               retention_starts_at: ~U[2026-06-21 13:00:00Z],
               sample_count: 3,
               confidence: :authoritative,
               reason: :telemetry_storage_write,
               observed_at: ~U[2026-06-21 14:00:01Z]
             })
             |> SourceWatermarks.record_source_watermark(invalidate_runtime_cache?: false)

    assert {:ok, %SourceFacts{} = facts} =
             SourceRegistry.facts(request,
               source_watermark_events?: true,
               source_health_events?: false,
               data_sources: [data_source()],
               data_bindings: [data_binding()],
               source_opts: %{
                 telemetry: [
                   latest_fun: &telemetry_sample/4,
                   watermark_fun: &adapter_watermark/4
                 ]
               }
             )

    assert %SourceWatermark{} = facts.watermark
    assert facts.watermark.complete_through == ~U[2026-06-21 14:00:00.000000Z]
    assert facts.watermark.sample_count == 3
    assert facts.watermark.confidence == :authoritative
    assert facts.watermark.meta.durable_source_watermark?
    assert facts.meta.durable_source_watermark?
    assert facts.meta.source_watermark_reason == :telemetry_storage_write
  end

  test "source registry facts select matching replay-run source watermark" do
    assert {:ok, _event, stale_status} =
             @source_identity
             |> Map.merge(%{
               realm: :replay,
               replay_run_id: "replay-run-stale",
               complete_through: ~U[2026-06-21 13:00:00Z],
               latest_receipt_time: ~U[2026-06-21 13:00:00Z],
               retention_starts_at: ~U[2026-06-21 12:00:00Z],
               sample_count: 99,
               confidence: :best_effort,
               reason: :telemetry_storage_write,
               observed_at: ~U[2026-06-21 13:00:01Z]
             })
             |> SourceWatermarks.record_source_watermark(invalidate_runtime_cache?: false)

    assert {:ok, _event, replay_status} =
             @source_identity
             |> Map.merge(%{
               realm: :replay,
               replay_run_id: "replay-run-1",
               complete_through: ~U[2026-06-21 14:00:00Z],
               latest_receipt_time: ~U[2026-06-21 14:00:00Z],
               retention_starts_at: ~U[2026-06-21 13:00:00Z],
               sample_count: 3,
               confidence: :authoritative,
               reason: :telemetry_storage_write,
               observed_at: ~U[2026-06-21 14:00:01Z]
             })
             |> SourceWatermarks.record_source_watermark(invalidate_runtime_cache?: false)

    request =
      source_request(
        data_context: %{realm: :replay, replay_run_id: "replay-run-1"},
        time_context: %{mode: :replay_run, axis: :receipt_time, replay_run_id: "replay-run-1"}
      )

    assert {:ok, %SourceFacts{} = facts} =
             SourceRegistry.facts(request,
               source_watermark_events?: true,
               source_health_events?: false,
               data_sources: [data_source()],
               data_bindings: [data_binding(realm: :replay, dataset: "flight")],
               source_opts: %{
                 telemetry: [
                   latest_fun: &telemetry_sample/4,
                   watermark_fun: &adapter_watermark/4
                 ]
               }
             )

    assert facts.watermark.replay_run_id == "replay-run-1"
    assert facts.watermark.sample_count == 3

    assert facts.watermark.meta.source_watermark_event_id ==
             replay_status.source_watermark_event_id

    refute facts.watermark.meta.source_watermark_event_id ==
             stale_status.source_watermark_event_id
  end

  test "source registry facts fall back to source-level watermark when exact replay watermark is missing" do
    assert {:ok, _event, source_level_status} =
             @source_identity
             |> Map.merge(%{
               source_binding_id: nil,
               realm: nil,
               replay_run_id: nil,
               dataset: nil,
               complete_through: ~U[2026-06-21 15:00:00Z],
               latest_receipt_time: ~U[2026-06-21 15:00:00Z],
               retention_starts_at: ~U[2026-06-21 14:00:00Z],
               sample_count: 7,
               confidence: :authoritative,
               reason: :source_watermark_observed,
               observed_at: ~U[2026-06-21 15:00:01Z]
             })
             |> SourceWatermarks.record_source_watermark(invalidate_runtime_cache?: false)

    request =
      source_request(
        data_context: %{realm: :replay, replay_run_id: "replay-run-fallback"},
        time_context: %{
          mode: :replay_run,
          axis: :receipt_time,
          replay_run_id: "replay-run-fallback"
        }
      )

    assert {:ok, %SourceFacts{} = facts} =
             SourceRegistry.facts(request,
               source_watermark_events?: true,
               source_health_events?: false,
               data_sources: [data_source()],
               data_bindings: [data_binding(realm: :replay, dataset: "flight")],
               source_opts: %{
                 telemetry: [
                   latest_fun: &telemetry_sample/4,
                   watermark_fun: &adapter_watermark/4
                 ]
               }
             )

    assert facts.watermark.complete_through == ~U[2026-06-21 15:00:00.000000Z]
    assert facts.watermark.sample_count == 7
    assert facts.watermark.replay_run_id == nil
    assert facts.watermark.meta.durable_source_watermark?

    assert facts.watermark.meta.source_watermark_event_id ==
             source_level_status.source_watermark_event_id
  end

  test "source registry resolve overlays exact replay watermark on source result" do
    assert {:ok, _event, source_level_status} =
             @source_identity
             |> Map.merge(%{
               source_binding_id: nil,
               realm: nil,
               replay_run_id: nil,
               dataset: nil,
               complete_through: ~U[2026-06-21 13:00:00Z],
               latest_receipt_time: ~U[2026-06-21 13:00:00Z],
               retention_starts_at: ~U[2026-06-21 12:00:00Z],
               sample_count: 99,
               confidence: :best_effort,
               reason: :source_watermark_observed,
               observed_at: ~U[2026-06-21 13:00:01Z]
             })
             |> SourceWatermarks.record_source_watermark(invalidate_runtime_cache?: false)

    assert {:ok, _event, exact_status} =
             @source_identity
             |> Map.merge(%{
               realm: :replay,
               replay_run_id: "replay-run-result",
               complete_through: ~U[2026-06-21 16:00:00Z],
               latest_receipt_time: ~U[2026-06-21 16:00:00Z],
               retention_starts_at: ~U[2026-06-21 15:00:00Z],
               sample_count: 8,
               confidence: :authoritative,
               reason: :telemetry_storage_write,
               observed_at: ~U[2026-06-21 16:00:01Z]
             })
             |> SourceWatermarks.record_source_watermark(invalidate_runtime_cache?: false)

    result =
      source_request(
        data_context: %{realm: :replay, replay_run_id: "replay-run-result"},
        time_context: %{
          mode: :replay_run,
          axis: :receipt_time,
          replay_run_id: "replay-run-result"
        }
      )
      |> SourceRegistry.resolve(
        source_result_watermark_opts(data_binding(realm: :replay, dataset: "flight"))
      )

    assert %SourceResult{warnings: [], watermarks: [%SourceWatermark{} = watermark]} = result
    assert watermark.replay_run_id == "replay-run-result"
    assert watermark.complete_through == ~U[2026-06-21 16:00:00.000000Z]
    assert watermark.sample_count == 8
    assert watermark.meta.durable_source_watermark?
    assert result.meta.durable_source_watermark?
    assert result.meta.source_watermark_event_id == exact_status.source_watermark_event_id
    refute result.meta.source_watermark_event_id == source_level_status.source_watermark_event_id

    assert has_evidence_ref?(
             Map.get(result.meta, :evidence),
             :source_watermark_event,
             exact_status.source_watermark_event_id
           )

    assert [%{meta: frame_meta} | _rest] = result.frames

    assert has_evidence_ref?(
             Map.get(frame_meta, :evidence),
             :source_watermark_event,
             exact_status.source_watermark_event_id
           )
  end

  test "source registry resolve falls back to source-level watermark on source result" do
    assert {:ok, _event, source_level_status} =
             @source_identity
             |> Map.merge(%{
               source_binding_id: nil,
               realm: nil,
               replay_run_id: nil,
               dataset: nil,
               complete_through: ~U[2026-06-21 17:00:00Z],
               latest_receipt_time: ~U[2026-06-21 17:00:00Z],
               retention_starts_at: ~U[2026-06-21 16:00:00Z],
               sample_count: 11,
               confidence: :authoritative,
               reason: :source_watermark_observed,
               observed_at: ~U[2026-06-21 17:00:01Z]
             })
             |> SourceWatermarks.record_source_watermark(invalidate_runtime_cache?: false)

    result =
      source_request(
        data_context: %{realm: :replay, replay_run_id: "replay-run-result-fallback"},
        time_context: %{
          mode: :replay_run,
          axis: :receipt_time,
          replay_run_id: "replay-run-result-fallback"
        }
      )
      |> SourceRegistry.resolve(
        source_result_watermark_opts(data_binding(realm: :replay, dataset: "flight"))
      )

    assert %SourceResult{warnings: [], watermarks: [%SourceWatermark{} = watermark]} = result
    assert watermark.replay_run_id == nil
    assert watermark.complete_through == ~U[2026-06-21 17:00:00.000000Z]
    assert watermark.sample_count == 11
    assert watermark.meta.durable_source_watermark?
    assert result.meta.durable_source_watermark?
    assert result.meta.source_watermark_event_id == source_level_status.source_watermark_event_id
  end

  test "source registry durable source result watermark clears adapter unknown watermark warnings" do
    assert {:ok, _event, source_level_status} =
             @source_identity
             |> Map.merge(%{
               source_binding_id: nil,
               realm: nil,
               replay_run_id: nil,
               dataset: nil,
               complete_through: ~U[2026-06-21 18:00:00Z],
               latest_receipt_time: ~U[2026-06-21 18:00:00Z],
               retention_starts_at: ~U[2026-06-21 17:00:00Z],
               sample_count: 12,
               confidence: :best_effort,
               reason: :source_watermark_observed,
               observed_at: ~U[2026-06-21 18:00:01Z]
             })
             |> SourceWatermarks.record_source_watermark(invalidate_runtime_cache?: false)

    result =
      source_request()
      |> SourceRegistry.resolve(
        source_result_watermark_opts(data_binding(), watermark_fun: &unknown_adapter_watermark/4)
      )

    assert %SourceResult{warnings: [], watermarks: [%SourceWatermark{} = watermark]} = result
    assert watermark.confidence == :best_effort
    assert watermark.complete_through == ~U[2026-06-21 18:00:00.000000Z]
    assert watermark.meta.durable_source_watermark?
    assert result.meta.durable_source_watermark?
    assert result.meta.source_watermark_event_id == source_level_status.source_watermark_event_id

    assert [%{meta: frame_meta} | _rest] = result.frames
    refute :watermark_unknown in Map.get(frame_meta, :warning_codes, [])
    refute "watermark_unknown" in Map.get(frame_meta, :warning_codes, [])
  end

  defp source_request(opts \\ []) do
    %PlannedSourceRequest{
      request_id: "source-request-watermark",
      organization_id: @organization_id,
      mission_id: @mission_id,
      logical_source: :telemetry,
      observables: ["HK.counter"],
      data_context: Keyword.get(opts, :data_context, %{realm: :flight}),
      time_context: Keyword.get(opts, :time_context, %{}),
      sampling: %{mode: :latest}
    }
  end

  defp data_binding(opts \\ []) do
    realm = Keyword.get(opts, :realm, :flight)

    %DataBinding{
      binding_id: "flight-telemetry",
      organization_id: @organization_id,
      mission_id: @mission_id,
      realm: realm,
      logical_source: :telemetry,
      data_source_id: "flight-questdb",
      dataset: Keyword.get(opts, :dataset, Atom.to_string(realm))
    }
  end

  defp data_source do
    %DataSource{
      data_source_id: "flight-questdb",
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: @organization_id,
      mission_id: @mission_id,
      capabilities: %{latest?: true, range_scan?: true, watermarks?: true}
    }
  end

  defp source_result_watermark_opts(%DataBinding{} = binding, opts \\ []) do
    [
      source_watermark_events?: true,
      source_health_events?: false,
      data_sources: [data_source()],
      data_bindings: [binding],
      source_opts: %{
        telemetry: [
          latest_fun: &telemetry_sample/4,
          watermark_fun: Keyword.get(opts, :watermark_fun, &adapter_watermark/4)
        ]
      }
    ]
  end

  defp telemetry_sample(_organization_id, mission_id, point_id, _opts) do
    %Sample{
      sample_id: "sample-watermark",
      mission_id: mission_id,
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-watermark",
      packet_definition_version: 1,
      packet_id: "packet-watermark",
      evidence_id: "evidence-watermark",
      raw_value: 1,
      engineering_value: 1,
      quality_state: :good,
      receipt_time: ~U[2026-06-21 13:59:00Z],
      provenance: %{}
    }
  end

  defp adapter_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:ok,
     %{
       complete_through: ~U[2026-06-21 13:00:00Z],
       latest_receipt_time: ~U[2026-06-21 13:00:00Z],
       retention_starts_at: ~U[2026-06-21 12:00:00Z],
       sample_count: 1,
       confidence: :best_effort
     }}
  end

  defp unknown_adapter_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:error, :source_watermark_not_available}
  end

  defp has_evidence_ref?(evidence, kind, id) do
    Enum.any?(List.wrap(evidence), &match?(%{kind: ^kind, id: ^id}, &1))
  end
end
