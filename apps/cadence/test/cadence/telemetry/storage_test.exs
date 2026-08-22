defmodule Cadence.Telemetry.StorageTest do
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  use Cadence.ConfigCase, async: false

  alias Cadence.Dashboards.{
    Frame,
    PlannedSourceRequest,
    RuntimeCache,
    RuntimeCacheKey,
    RuntimeFactConsumer,
    RuntimeInvalidation,
    SourceResult
  }

  alias Cadence.Projections.DataSources.Watermarks, as: SourceWatermarks

  alias Cadence.DataSources.SourceWatermark

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage

  setup do
    current_value_store_policy = current_value_store_policy()
    start_supervised!(CurrentValueStore.child_spec(current_value_store_policy))
    CurrentValueStore.reset(current_value_store_policy)

    :ok
  end

  test "persists samples through configured observation writer" do
    sample = sample("sample-1", "mission-storage", "HK.counter", 42)

    assert :ok =
             Storage.persist_samples(storage_policy(), [sample],
               organization_id: "org-storage",
               source_endpoint_id: "station-a",
               recorded_at: ~U[2026-06-17 12:00:05Z]
             )

    assert_receive {:telemetry_storage_envelopes, [envelope]}

    assert envelope.organization_id == "org-storage"
    assert envelope.mission_id == "mission-storage"
    assert envelope.realm == :flight
    assert envelope.data_source_id == "managed_questdb_primary"
    assert envelope.binding_id == "default_flight_telemetry"
    assert envelope.source_endpoint_id == "station-a"
    assert envelope.sample_id == "sample-1"
    assert envelope.raw_value == 42
  end

  test "records backfill lifecycle events for identified historical writes" do
    sample = sample("sample-backfill", "mission-storage-backfill", "HK.counter", 42)

    assert :ok =
             Storage.persist_samples(storage_policy(), [sample],
               organization_id: "org-storage",
               realm: :backfill,
               data_source_id: "managed_questdb_backfill",
               binding_id: "backfill_telemetry",
               source_endpoint_id: "station-a",
               recorded_at: ~U[2026-06-17 12:00:05Z],
               backfill_run_id: "backfill-run-1",
               actor_id: "operator-1",
               actor_kind: "user"
             )

    assert_receive {:telemetry_storage_envelopes, [_envelope]}

    [event] =
      Storage.list_backfill_lifecycle_events("mission-storage-backfill",
        organization_id: "org-storage",
        data_source_id: "managed_questdb_backfill",
        binding_id: "backfill_telemetry",
        observable_id: "HK.counter",
        source_from: ~U[2026-06-17 11:59:00Z],
        source_to: ~U[2026-06-17 12:01:00Z]
      )

    assert event.backfill_run_id == "backfill-run-1"
    assert event.event_type == :backfill_completed
    assert event.realm == :backfill
    assert event.source_from == ~U[2026-06-17 12:00:00.000000Z]
    assert event.source_to == ~U[2026-06-17 12:00:00.000000Z]
    assert event.receipt_from == ~U[2026-06-17 12:00:03.000000Z]
    assert event.receipt_to == ~U[2026-06-17 12:00:03.000000Z]
    assert event.sample_count == 1
    assert event.authority == :authoritative
    assert event.reason == :telemetry_backfill_write
    assert event.actor_id == "operator-1"
    assert event.actor_kind == "user"
    assert event.occurred_at == ~U[2026-06-17 12:00:05.000000Z]
    assert event.payload["kind"] == "telemetry_storage_write"
    assert event.payload["sample_ids"] == ["sample-backfill"]
    assert event.payload["source_endpoint_id"] == "station-a"
  end

  test "does not record backfill lifecycle events for ordinary live writes" do
    sample = sample("sample-live", "mission-storage-live", "HK.counter", 42)

    assert :ok =
             Storage.persist_samples(storage_policy(), [sample],
               organization_id: "org-storage",
               recorded_at: ~U[2026-06-17 12:00:05Z]
             )

    assert_receive {:telemetry_storage_envelopes, [_envelope]}

    assert [] =
             Storage.list_backfill_lifecycle_events("mission-storage-live",
               organization_id: "org-storage"
             )
  end

  test "records failed backfill lifecycle events when identified historical writes fail" do
    sample = sample("sample-backfill-failed", "mission-storage-backfill-failed", "HK.counter", 42)

    assert {:error, :questdb_unavailable} =
             Storage.persist_samples(
               storage_policy(writer_opts: [test_pid: self(), fail_with: :questdb_unavailable]),
               [sample],
               organization_id: "org-storage",
               backfill_run_id: "backfill-run-failed",
               recorded_at: ~U[2026-06-17 12:00:05Z]
             )

    assert_receive {:telemetry_storage_envelopes, [_envelope]}

    [event] =
      Storage.list_backfill_lifecycle_events("mission-storage-backfill-failed",
        organization_id: "org-storage",
        backfill_run_id: "backfill-run-failed"
      )

    assert event.event_type == :backfill_failed
    assert event.reason == :telemetry_backfill_write_failed
    assert event.sample_count == 1
    assert event.payload["sample_ids"] == ["sample-backfill-failed"]
    assert event.payload["error"] == ":questdb_unavailable"
  end

  test "workflow runner wraps telemetry storage writes without duplicate outcome events" do
    sample = sample("sample-workflow-write", "mission-storage-workflow", "HK.counter", 42)

    attrs = %{
      backfill_run_id: "backfill-run-storage-workflow",
      organization_id: "org-storage",
      mission_id: "mission-storage-workflow",
      realm: :backfill,
      data_source_id: "managed_questdb_backfill",
      binding_id: "backfill_telemetry",
      observable_id: "HK.counter",
      source_from: ~U[2026-06-17 12:00:00Z],
      source_to: ~U[2026-06-17 12:00:00Z],
      actor_id: "operator-1",
      actor_kind: "user"
    }

    assert :ok =
             Storage.execute_backfill_lifecycle_workflow(
               :backfill,
               attrs,
               [
                 organization_id: "org-storage",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 recorded_at: ~U[2026-06-17 12:00:05Z]
               ],
               fn write_opts ->
                 Storage.persist_samples(storage_policy(), [sample], write_opts)
               end,
               dashboard_runtime_invalidation?: false
             )

    assert_receive {:telemetry_storage_envelopes, [_envelope]}

    events =
      Storage.list_backfill_lifecycle_events("mission-storage-workflow",
        organization_id: "org-storage",
        backfill_run_id: "backfill-run-storage-workflow"
      )

    assert Enum.map(events, & &1.event_type) == [
             :backfill_requested,
             :backfill_approved,
             :backfill_started,
             :backfill_completed
           ]

    assert Enum.map(events, & &1.sample_count) == [nil, nil, nil, nil]
  end

  test "groups sample writes by mission" do
    first = sample("sample-1", "mission-a", "HK.counter", 1)
    second = sample("sample-2", "mission-b", "HK.counter", 2)

    assert :ok =
             Storage.persist_samples(storage_policy(), [first, second],
               organization_id: "org-storage"
             )

    assert_receive {:telemetry_storage_envelopes, [first_envelope]}
    assert_receive {:telemetry_storage_envelopes, [second_envelope]}

    assert [first_envelope.mission_id, second_envelope.mission_id] |> Enum.sort() == [
             "mission-a",
             "mission-b"
           ]
  end

  test "records current values from storage-enriched canonical observations" do
    canonical = sample("sample-current-canonical", "mission-storage-current", "HK.counter", 42)

    conflict =
      sample("sample-current-conflict", "mission-storage-current", "HK.counter", 99)

    assert :ok =
             Storage.persist_samples(storage_policy(), [canonical],
               organization_id: "org-storage",
               recorded_at: ~U[2026-06-17 12:00:05Z]
             )

    assert_receive {:telemetry_storage_envelopes, [_canonical_envelope]}

    latest =
      TelemetryReads.latest_value("mission-storage-current", "HK.counter",
        spacecraft_id: "sc-1",
        current_value_store_policy: current_value_store_policy()
      )

    assert latest.sample_id == "sample-current-canonical"
    assert latest.raw_value == 42
    assert latest.provenance["storage"]["validity_state"] == "canonical"
    assert is_binary(latest.provenance["storage"]["observation_identity_id"])

    assert :ok =
             Storage.persist_samples(storage_policy(), [conflict],
               organization_id: "org-storage",
               validity_state: :conflict,
               recorded_at: ~U[2026-06-17 12:00:10Z]
             )

    assert_receive {:telemetry_storage_envelopes, [_conflict_envelope]}

    latest =
      TelemetryReads.latest_value("mission-storage-current", "HK.counter",
        spacecraft_id: "sc-1",
        current_value_store_policy: current_value_store_policy()
      )

    assert latest.sample_id == "sample-current-canonical"
    assert latest.raw_value == 42
  end

  test "returns writer errors" do
    assert {:error, {:missing_field, :replay_run_id}} =
             Storage.persist_samples(
               storage_policy(
                 writer: Cadence.Telemetry.Storage.Writers.Noop,
                 writer_opts: [],
                 storage_opts: [
                   realm: :replay,
                   data_source_id: "managed_questdb_primary",
                   binding_id: "default_flight_telemetry"
                 ]
               ),
               [sample("sample-1", "mission-storage", "HK.counter", 42)],
               organization_id: "org-storage"
             )
  end

  test "replay telemetry writes record replay-scoped source watermarks" do
    assert :ok =
             Storage.persist_samples(
               storage_policy(),
               [sample("sample-replay-watermark", "mission-storage-replay", "HK.counter", 42)],
               organization_id: "org-storage",
               realm: :replay,
               replay_run_id: "replay-run-1",
               data_source_id: "managed_questdb_replay",
               binding_id: "replay_telemetry",
               recorded_at: ~U[2026-06-17 12:00:05Z],
               source_watermark_events?: true,
               dashboard_runtime_invalidation?: false
             )

    assert_receive {:telemetry_storage_envelopes, [envelope]}
    assert envelope.replay_run_id == "replay-run-1"

    assert [status] =
             SourceWatermarks.list_source_watermark_statuses(
               "org-storage",
               "mission-storage-replay",
               realm: :replay,
               replay_run_id: "replay-run-1"
             )

    assert status.data_source_id == "managed_questdb_replay"
    assert status.source_binding_id == "replay_telemetry"
    assert status.replay_run_id == "replay-run-1"
    assert status.payload["replay_run_id"] == "replay-run-1"
    assert status.payload["sample_ids"] == ["sample-replay-watermark"]
  end

  test "replay historical writes record replay-scoped backfill lifecycle events" do
    assert :ok =
             Storage.persist_samples(
               storage_policy(),
               [
                 sample(
                   "sample-replay-backfill",
                   "mission-storage-replay-backfill",
                   "HK.counter",
                   42
                 )
               ],
               organization_id: "org-storage",
               realm: :replay,
               replay_run_id: "replay-run-1",
               data_source_id: "managed_questdb_replay",
               binding_id: "replay_telemetry",
               recorded_at: ~U[2026-06-17 12:00:05Z],
               backfill_run_id: "backfill-run-replay-1",
               dashboard_runtime_invalidation?: false
             )

    assert_receive {:telemetry_storage_envelopes, [envelope]}
    assert envelope.replay_run_id == "replay-run-1"

    assert [event] =
             Storage.list_backfill_lifecycle_events("mission-storage-replay-backfill",
               organization_id: "org-storage",
               realm: :replay,
               replay_run_id: "replay-run-1",
               data_source_id: "managed_questdb_replay",
               binding_id: "replay_telemetry"
             )

    assert event.backfill_run_id == "backfill-run-replay-1"
    assert event.replay_run_id == "replay-run-1"
    assert event.event_type == :backfill_completed
    assert event.payload["replay_run_id"] == "replay-run-1"
    assert event.payload["sample_ids"] == ["sample-replay-backfill"]

    assert [] =
             Storage.list_backfill_lifecycle_events("mission-storage-replay-backfill",
               organization_id: "org-storage",
               realm: :replay,
               replay_run_id: "replay-run-2"
             )
  end

  test "replay telemetry writes emit replay-scoped runtime invalidations" do
    cache = start_supervised!({RuntimeCache, name: nil})
    use_dashboard_runtime_cache!(cache)
    attach_runtime_invalidation_telemetry(self())

    assert :ok =
             Storage.persist_samples(
               storage_policy(storage_opts: [dashboard_runtime_invalidation?: true]),
               [sample("sample-replay-invalidation", "mission-storage-replay", "HK.counter", 42)],
               organization_id: "org-storage",
               realm: :replay,
               replay_run_id: "replay-run-1",
               data_source_id: "managed_questdb_replay",
               binding_id: "replay_telemetry",
               recorded_at: ~U[2026-06-17 12:00:05Z],
               runtime_cache: RuntimeCache.client(cache),
               dashboard_runtime_invalidation?: true
             )

    assert_receive {:telemetry_storage_envelopes, [_envelope]}

    assert_runtime_invalidation_event(:source_watermark_changed, fn _measurements, metadata ->
      metadata.filters.realm == :replay and
        metadata.filters.replay_run_id == "replay-run-1" and
        metadata.filters.data_source_id == "managed_questdb_replay" and
        metadata.filters.source_binding_id == "replay_telemetry"
    end)

    assert_runtime_invalidation_event(:historical_data_changed, fn _measurements, metadata ->
      metadata.filters.realm == :replay and
        metadata.filters.replay_run_id == "replay-run-1" and
        metadata.filters.time_range.axis in [:receipt_time, :generation_time]
    end)
  end

  test "telemetry writes invalidate live and overlapping snapshot dashboard caches" do
    cache = start_supervised!({RuntimeCache, name: nil})
    use_dashboard_runtime_cache!(cache)
    attach_runtime_invalidation_telemetry(self())

    time_context = archive_time_context(~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:10:00Z])
    snapshot_key = source_result_key(cache_policy: :snapshot, time_context: time_context)
    snapshot_frame_key = frame_key(cache_policy: :snapshot, time_context: time_context)
    live_key = source_result_key(cache_policy: :live)
    live_frame_key = frame_key(cache_policy: :live)
    snapshot_result = source_result()
    live_result = source_result()
    snapshot_frames = frames("frame-snapshot")
    live_frames = frames("frame-live")

    assert :ok = RuntimeCache.put_source_result(snapshot_key, snapshot_result, cache)
    assert :ok = RuntimeCache.put_source_result(live_key, live_result, cache)
    assert :ok = RuntimeCache.put_frame(snapshot_frame_key, snapshot_frames, cache)
    assert :ok = RuntimeCache.put_frame(live_frame_key, live_frames, cache)

    assert :ok =
             Storage.persist_samples(
               storage_policy(storage_opts: [dashboard_runtime_invalidation?: true]),
               [sample("sample-1", "mission-storage", "HK.counter", 42)],
               organization_id: "org-storage",
               runtime_cache: RuntimeCache.client(cache),
               dashboard_runtime_invalidation?: true
             )

    assert_receive {:telemetry_storage_envelopes, [_envelope]}

    assert_runtime_invalidation_event(:source_watermark_changed, fn measurements, metadata ->
      measurements.source_results == 1 and measurements.frames == 1 and
        metadata.filters.cache_policy == :live and
        metadata.filters.source_binding_id == "default_flight_telemetry"
    end)

    assert_runtime_invalidation_event(:historical_data_changed, fn measurements, metadata ->
      measurements.source_results == 1 and measurements.frames == 1 and
        metadata.filters.cache_policy == :snapshot and
        metadata.filters.time_range.axis in [:receipt_time, :generation_time] and
        metadata.filters.evidence_ref.kind == "telemetry_storage_write"
    end)

    assert RuntimeCache.get_source_result(snapshot_key, cache) == :miss
    assert RuntimeCache.get_source_result(live_key, cache) == :miss
    assert RuntimeCache.get_frame(snapshot_frame_key, cache) == :miss
    assert RuntimeCache.get_frame(live_frame_key, cache) == :miss
  end

  test "telemetry writes leave non-overlapping snapshot dashboard caches in place" do
    cache = start_supervised!({RuntimeCache, name: nil})
    use_dashboard_runtime_cache!(cache)
    time_context = archive_time_context(~U[2026-06-17 13:00:00Z], ~U[2026-06-17 13:10:00Z])
    snapshot_key = source_result_key(cache_policy: :snapshot, time_context: time_context)
    snapshot_frame_key = frame_key(cache_policy: :snapshot, time_context: time_context)
    snapshot_result = source_result()
    snapshot_frames = frames("frame-snapshot")

    assert :ok = RuntimeCache.put_source_result(snapshot_key, snapshot_result, cache)
    assert :ok = RuntimeCache.put_frame(snapshot_frame_key, snapshot_frames, cache)

    assert :ok =
             Storage.persist_samples(
               storage_policy(storage_opts: [dashboard_runtime_invalidation?: true]),
               [sample("sample-1", "mission-storage", "HK.counter", 42)],
               organization_id: "org-storage",
               runtime_cache: RuntimeCache.client(cache),
               dashboard_runtime_invalidation?: true
             )

    assert_receive {:telemetry_storage_envelopes, [_envelope]}

    assert {:ok, ^snapshot_result} = RuntimeCache.get_source_result(snapshot_key, cache)
    assert {:ok, ^snapshot_frames} = RuntimeCache.get_frame(snapshot_frame_key, cache)
  end

  defp current_value_store_policy do
    CurrentValueStore.policy(module: Cadence.Telemetry.CurrentValueStore.ETS)
  end

  defp storage_policy(opts \\ []) do
    storage_opts =
      [
        realm: :flight,
        data_source_id: "managed_questdb_primary",
        binding_id: "default_flight_telemetry",
        dashboard_runtime_invalidation?: false
      ]
      |> Keyword.merge(Keyword.get(opts, :storage_opts, []))

    config =
      [
        writer:
          Keyword.get(
            opts,
            :writer,
            Cadence.TestSupport.CapturingTelemetryStorageWriter
          ),
        writer_opts: Keyword.get(opts, :writer_opts, test_pid: self())
      ] ++ storage_opts

    Storage.policy(config, current_value_store_policy: current_value_store_policy())
  end

  defp sample(sample_id, mission_id, point_id, raw_value) do
    %Sample{
      sample_id: sample_id,
      mission_id: mission_id,
      spacecraft_id: "sc-1",
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-1",
      raw_value: raw_value,
      engineering_value: raw_value,
      quality_state: :good,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:03Z],
      provenance: %{}
    }
  end

  defp source_result_key(opts) do
    request = source_request(opts)

    RuntimeCacheKey.source_result(request,
      cache_policy: Keyword.get(opts, :cache_policy, :live),
      source_binding: source_binding(),
      data_source: data_source(),
      watermark: source_watermark()
    )
  end

  defp source_request(opts) do
    %PlannedSourceRequest{
      request_id: Keyword.get(opts, :request_id, "source_req_telemetry"),
      organization_id: "org-storage",
      mission_id: "mission-storage",
      logical_source: :telemetry,
      observables: ["HK.counter"],
      time_context: Keyword.get(opts, :time_context, %{}),
      sampling: %{mode: :latest}
    }
  end

  defp frame_key(opts) do
    opts
    |> source_result_key()
    |> RuntimeCacheKey.frame(
      placement_id: Keyword.get(opts, :placement_id, "placement-counter"),
      placement_size: %{width_px: 320, height_px: 120},
      display: %{density: :normal},
      frame_shape: :scalar
    )
  end

  defp source_result do
    %SourceResult{
      request_id: "source_req_telemetry",
      watermarks: [source_watermark()]
    }
  end

  defp frames(frame_id) do
    [
      %Frame{
        frame_id: frame_id,
        source: :telemetry,
        shape: :scalar,
        fields: []
      }
    ]
  end

  defp source_binding do
    %DataBinding{
      binding_id: "default_flight_telemetry",
      organization_id: "org-storage",
      mission_id: "mission-storage",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "managed_questdb_primary",
      dataset: "flight"
    }
  end

  defp data_source do
    %DataSource{
      data_source_id: "managed_questdb_primary",
      adapter: Cadence.Dashboards.Sources.Telemetry,
      capabilities: %{latest?: true, range_scan?: true, watermarks?: true}
    }
  end

  defp source_watermark do
    %SourceWatermark{
      logical_source: :telemetry,
      request_id: "source_req_telemetry",
      source_binding_id: "default_flight_telemetry",
      data_source_id: "managed_questdb_primary",
      realm: :flight,
      dataset: "flight",
      complete_through: ~U[2026-06-17 12:00:03Z],
      latest_receipt_time: ~U[2026-06-17 12:00:03Z],
      retention_starts_at: ~U[2026-06-17 11:00:00Z],
      confidence: :best_effort,
      freshness_state: :fresh
    }
  end

  defp archive_time_context(from, to) do
    %{mode: :archive, axis: :receipt_time, from: from, to: to}
  end

  defp attach_runtime_invalidation_telemetry(test_pid) do
    handler_id =
      "telemetry-storage-runtime-invalidation-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [RuntimeInvalidation.telemetry_event()],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:runtime_invalidation_telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp assert_runtime_invalidation_event(boundary, predicate) when is_function(predicate, 2) do
    assert_runtime_invalidation_event(
      boundary,
      predicate,
      System.monotonic_time(:millisecond) + 1_000
    )
  end

  defp assert_runtime_invalidation_event(boundary, predicate, deadline) do
    receive do
      {:runtime_invalidation_telemetry, event, measurements, metadata} ->
        if event == RuntimeInvalidation.telemetry_event() and metadata.boundary == boundary and
             predicate.(measurements, metadata) do
          {measurements, metadata}
        else
          assert_runtime_invalidation_event(boundary, predicate, deadline)
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("expected runtime invalidation telemetry for #{inspect(boundary)}")
    end
  end

  defp use_dashboard_runtime_cache!(cache) do
    start_supervised!(
      {RuntimeFactConsumer, name: nil, enabled?: true, runtime_cache: RuntimeCache.client(cache)}
    )
  end
end
