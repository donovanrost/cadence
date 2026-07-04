defmodule Cadence.Dashboards.RuntimeInvalidationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataBinding,
    DataSource,
    Document,
    Engine,
    Frame,
    PlannedSourceRequest,
    RuntimeCache,
    RuntimeCacheKey,
    RuntimeInvalidation,
    RuntimeInvalidation.Event,
    SourceResult,
    SourceWatermark
  }

  @fixture_dir Path.expand("../../fixtures/dashboards", __DIR__)

  test "coverage matrix documents every runtime invalidation boundary" do
    expected = %{
      dashboard_version_changed: %{
        layers: [:plan],
        default_cache_policy: nil,
        producer_status: :wired
      },
      catalog_revision_changed: %{
        layers: [:plan, :source_result, :frame],
        default_cache_policy: nil,
        producer_status: :wired
      },
      limit_definition_changed: %{
        layers: [:plan, :source_result, :frame],
        default_cache_policy: nil,
        producer_status: :wired
      },
      data_source_binding_changed: %{
        layers: [:plan, :source_result, :frame],
        default_cache_policy: nil,
        producer_status: :wired
      },
      source_watermark_changed: %{
        layers: [:source_result, :frame],
        default_cache_policy: :live,
        producer_status: :wired
      },
      historical_data_changed: %{
        layers: [:source_result, :frame],
        default_cache_policy: :snapshot,
        producer_status: :wired
      },
      telemetry_revision_state_changed: %{
        layers: [:source_result, :frame],
        default_cache_policy: nil,
        producer_status: :wired
      },
      source_health_changed: %{
        layers: [:source_result, :frame],
        default_cache_policy: :live,
        producer_status: :wired
      },
      events_changed: %{
        layers: [:source_result, :frame],
        default_cache_policy: :live,
        producer_status: :wired
      }
    }

    matrix = RuntimeInvalidation.coverage_matrix()

    assert MapSet.new(Enum.map(matrix, & &1.boundary)) == MapSet.new(Map.keys(expected))

    for row <- matrix do
      assert function_exported?(RuntimeInvalidation, row.boundary, 2)
      assert row.domain_fact == row.boundary
      assert row.producer != ""
      assert row.notes != ""

      assert Map.take(row, [:layers, :default_cache_policy, :producer_status]) ==
               Map.fetch!(expected, row.boundary)
    end
  end

  test "emits telemetry for runtime invalidation boundary calls" do
    cache = start_supervised!({RuntimeCache, name: nil})
    attach_runtime_invalidation_telemetry(self())

    source_key =
      source_result_key(:telemetry,
        data_source_id: "telemetry-questdb",
        source_binding_id: "flight-telemetry-binding"
      )

    frame_key =
      frame_key(:telemetry,
        data_source_id: "telemetry-questdb",
        source_binding_id: "flight-telemetry-binding"
      )

    source_result = source_result(:telemetry)
    telemetry_frames = frames(:telemetry)

    assert :ok = RuntimeCache.put_source_result(source_key, source_result, cache)
    assert :ok = RuntimeCache.put_frame(frame_key, telemetry_frames, cache)

    assert %{plans: 0, source_results: 1, frames: 1} =
             RuntimeInvalidation.source_watermark_changed(
               %{
                 logical_source: "telemetry",
                 source_id: "telemetry-questdb",
                 binding_id: "flight-telemetry-binding",
                 observable: "battery_voltage",
                 evidence_ref: %{kind: "telemetry_storage_write", id: "write-1"}
               },
               runtime_cache: cache
             )

    assert_receive {:runtime_invalidation_telemetry, event, measurements, metadata}
    assert event == RuntimeInvalidation.telemetry_event()
    assert measurements.plans == 0
    assert measurements.source_results == 1
    assert measurements.frames == 1
    assert measurements.total == 2
    assert is_integer(measurements.duration)

    assert metadata.boundary == :source_watermark_changed
    assert metadata.domain_fact == :source_watermark_changed
    assert metadata.layers == [:source_result, :frame]
    assert metadata.runtime_cache == cache
    assert %DateTime{} = metadata.occurred_at

    assert metadata.filters.logical_source == :telemetry
    assert metadata.filters.cache_policy == :live
    assert metadata.filters.data_source_id == "telemetry-questdb"
    assert metadata.filters.source_binding_id == "flight-telemetry-binding"
    assert metadata.filters.observable == "battery_voltage"
    assert metadata.filters.evidence_ref == %{kind: "telemetry_storage_write", id: "write-1"}
    refute Map.has_key?(metadata.filters, :source_id)
    refute Map.has_key?(metadata.filters, :binding_id)

    assert metadata.layer_filters.source_result.cache_policy == :live
    assert metadata.layer_filters.source_result.data_source_id == "telemetry-questdb"
    assert metadata.layer_filters.source_result.source_binding_id == "flight-telemetry-binding"
    refute Map.has_key?(metadata.layer_filters.source_result, :evidence_ref)

    assert metadata.layer_filters.frame.cache_policy == :live
    assert metadata.layer_filters.frame.data_source_id == "telemetry-questdb"
    assert metadata.layer_filters.frame.source_binding_id == "flight-telemetry-binding"
    refute Map.has_key?(metadata.layer_filters.frame, :evidence_ref)
  end

  test "broadcasts runtime invalidation events to scoped dashboard subscribers" do
    cache = start_supervised!({RuntimeCache, name: nil})
    unique = System.unique_integer([:positive])
    organization_id = "org-runtime-invalidation-#{unique}"
    mission_id = "mission-runtime-invalidation-#{unique}"
    dashboard_id = "dashboard-runtime-invalidation-#{unique}"

    assert :ok =
             RuntimeInvalidation.subscribe(%{
               organization_id: organization_id,
               mission_id: mission_id,
               dashboard_id: dashboard_id
             })

    assert %{plans: 0, source_results: 0, frames: 0} =
             RuntimeInvalidation.historical_data_changed(
               %{
                 organization_id: organization_id,
                 mission_id: mission_id,
                 logical_source: :telemetry,
                 time_range: %{
                   from: "2026-06-17T12:00:00Z",
                   to: "2026-06-17T12:05:00Z"
                 }
               },
               runtime_cache: cache
             )

    assert_receive {:dashboard_runtime_invalidated, event}
    assert %Event{} = event
    assert event.boundary == :historical_data_changed
    assert event.domain_fact == :historical_data_changed
    assert event.layers == [:source_result, :frame]
    assert event.layer_filters.source_result.cache_policy == :snapshot
    assert event.layer_filters.frame.cache_policy == :snapshot
    assert event.filters.organization_id == organization_id
    assert event.filters.mission_id == mission_id
    assert event.filters.logical_source == :telemetry
    assert event.filters.cache_policy == :snapshot
    assert event.measurements.total == 0
    assert %DateTime{} = event.occurred_at
  end

  test "dashboard version changes invalidate matching plans only" do
    cache = start_supervised!({RuntimeCache, name: nil})
    %Document{} = first = load_fixture!("value_tile_latest.v1.json")
    second = %Document{first | dashboard_id: "dashboard_other_power_latest"}

    first_plan = Engine.plan(resolve_request(first), runtime_cache: cache)
    second_plan = Engine.plan(resolve_request(second), runtime_cache: cache)
    source_key = source_result_key(:telemetry)
    frame_key = frame_key(:telemetry)
    source_result = source_result(:telemetry)
    telemetry_frames = frames(:telemetry)

    assert :ok = RuntimeCache.put_source_result(source_key, source_result, cache)
    assert :ok = RuntimeCache.put_frame(frame_key, telemetry_frames, cache)

    assert %{plans: 1, source_results: 0, frames: 0} =
             RuntimeInvalidation.dashboard_version_changed(
               %{dashboard_id: first.dashboard_id},
               runtime_cache: cache
             )

    assert Engine.plan(resolve_request(first), runtime_cache: cache).plan_metadata.cache.plan_cache.status ==
             :miss

    assert Engine.plan(resolve_request(second), runtime_cache: cache).plan_metadata.cache.plan_cache.status ==
             :hit

    assert {:ok, ^source_result} = RuntimeCache.get_source_result(source_key, cache)
    assert {:ok, ^telemetry_frames} = RuntimeCache.get_frame(frame_key, cache)

    assert first_plan.dashboard_id == first.dashboard_id
    assert second_plan.dashboard_id == second.dashboard_id
  end

  test "dashboard version invalidation retains lifecycle action diagnostics" do
    attach_runtime_invalidation_telemetry(self())

    assert %{plans: 0, source_results: 0, frames: 0} =
             RuntimeInvalidation.dashboard_version_changed(%{
               organization_id: "org-runtime",
               mission_id: "mission-runtime",
               dashboard_id: "dashboard-runtime",
               document_version: 3,
               lifecycle_action: :reverted,
               source_version: 1
             })

    assert_receive {:runtime_invalidation_telemetry, event_name, _measurements, metadata}
    assert event_name == RuntimeInvalidation.telemetry_event()
    assert metadata.boundary == :dashboard_version_changed
    assert metadata.filters.lifecycle_action == :reverted
    assert metadata.filters.document_version == 3
    assert metadata.filters.source_version == 1
    assert metadata.layer_filters.plan.dashboard_id == "dashboard-runtime"
    refute Map.has_key?(metadata.layer_filters.plan, :lifecycle_action)
  end

  test "data source binding changes invalidate source-bound artifacts and dependent plans" do
    cache = start_supervised!({RuntimeCache, name: nil})
    document = load_fixture!("value_tile_latest.v1.json")
    _plan = Engine.plan(resolve_request(document), runtime_cache: cache)

    flight_key = source_result_key(:telemetry, data_source_id: "flight-questdb")
    rehearsal_key = source_result_key(:telemetry, data_source_id: "rehearsal-questdb")
    flight_result = source_result(:telemetry, data_source_id: "flight-questdb")
    rehearsal_result = source_result(:telemetry, data_source_id: "rehearsal-questdb")
    flight_frame_key = frame_key(:telemetry, data_source_id: "flight-questdb")
    rehearsal_frame_key = frame_key(:telemetry, data_source_id: "rehearsal-questdb")
    flight_frames = frames(:telemetry, frame_id: "frame-flight")
    rehearsal_frames = frames(:telemetry, frame_id: "frame-rehearsal")

    assert :ok = RuntimeCache.put_source_result(flight_key, flight_result, cache)
    assert :ok = RuntimeCache.put_source_result(rehearsal_key, rehearsal_result, cache)
    assert :ok = RuntimeCache.put_frame(flight_frame_key, flight_frames, cache)
    assert :ok = RuntimeCache.put_frame(rehearsal_frame_key, rehearsal_frames, cache)

    assert %{plans: 1, source_results: 1, frames: 1} =
             RuntimeInvalidation.data_source_binding_changed(
               %{
                 logical_source: :telemetry,
                 data_source_id: "flight-questdb"
               },
               runtime_cache: cache
             )

    assert Engine.plan(resolve_request(document), runtime_cache: cache).plan_metadata.cache.plan_cache.status ==
             :miss

    assert RuntimeCache.get_source_result(flight_key, cache) == :miss
    assert {:ok, ^rehearsal_result} = RuntimeCache.get_source_result(rehearsal_key, cache)
    assert RuntimeCache.get_frame(flight_frame_key, cache) == :miss
    assert {:ok, ^rehearsal_frames} = RuntimeCache.get_frame(rehearsal_frame_key, cache)
  end

  test "data source binding changes invalidate segmented source-bound artifacts" do
    cache = start_supervised!({RuntimeCache, name: nil})
    source_key = segmented_source_result_key()
    frame_key = segmented_frame_key()
    source_result = source_result(:telemetry, request_id: source_key.parts.request.request_id)
    telemetry_frames = frames(:telemetry, frame_id: "frame-segmented")

    assert :ok = RuntimeCache.put_source_result(source_key, source_result, cache)
    assert :ok = RuntimeCache.put_frame(frame_key, telemetry_frames, cache)

    assert %{plans: 0, source_results: 1, frames: 1} =
             RuntimeInvalidation.data_source_binding_changed(
               %{
                 logical_source: :telemetry,
                 data_source_id: "flight-questdb-v2"
               },
               runtime_cache: cache
             )

    assert RuntimeCache.get_source_result(source_key, cache) == :miss
    assert RuntimeCache.get_frame(frame_key, cache) == :miss
  end

  test "limit definition changes default to the limits source" do
    cache = start_supervised!({RuntimeCache, name: nil})
    telemetry_key = source_result_key(:telemetry)
    limits_key = source_result_key(:limits)
    telemetry_result = source_result(:telemetry)
    limits_result = source_result(:limits)
    telemetry_frame_key = frame_key(:telemetry)
    limits_frame_key = frame_key(:limits)
    telemetry_frames = frames(:telemetry)
    limits_frames = frames(:limits)

    assert :ok = RuntimeCache.put_source_result(telemetry_key, telemetry_result, cache)
    assert :ok = RuntimeCache.put_source_result(limits_key, limits_result, cache)
    assert :ok = RuntimeCache.put_frame(telemetry_frame_key, telemetry_frames, cache)
    assert :ok = RuntimeCache.put_frame(limits_frame_key, limits_frames, cache)

    assert %{plans: 0, source_results: 1, frames: 1} =
             RuntimeInvalidation.limit_definition_changed(
               %{mission_id: "mission_dashboards", observable: "battery_voltage"},
               runtime_cache: cache
             )

    assert {:ok, ^telemetry_result} = RuntimeCache.get_source_result(telemetry_key, cache)
    assert RuntimeCache.get_source_result(limits_key, cache) == :miss
    assert {:ok, ^telemetry_frames} = RuntimeCache.get_frame(telemetry_frame_key, cache)
    assert RuntimeCache.get_frame(limits_frame_key, cache) == :miss
  end

  test "catalog revision changes can target materialized frames by revision" do
    cache = start_supervised!({RuntimeCache, name: nil})
    old_key = frame_key(:limits, catalog_revision: "catalog:v1")
    current_key = frame_key(:limits, catalog_revision: "catalog:v2")
    old_frames = frames(:limits, frame_id: "frame-old-catalog")
    current_frames = frames(:limits, frame_id: "frame-current-catalog")

    assert :ok = RuntimeCache.put_frame(old_key, old_frames, cache)
    assert :ok = RuntimeCache.put_frame(current_key, current_frames, cache)

    assert %{plans: 0, source_results: 0, frames: 1} =
             RuntimeInvalidation.catalog_revision_changed(
               %{catalog_revision: "catalog:v1"},
               runtime_cache: cache
             )

    assert RuntimeCache.get_frame(old_key, cache) == :miss
    assert {:ok, ^current_frames} = RuntimeCache.get_frame(current_key, cache)
  end

  test "historical data changes invalidate overlapping snapshot artifacts only" do
    cache = start_supervised!({RuntimeCache, name: nil})

    overlapping_context =
      archive_time_context(~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:10:00Z])

    outside_context =
      archive_time_context(~U[2026-06-17 13:00:00Z], ~U[2026-06-17 13:10:00Z])

    snapshot_key =
      source_result_key(:telemetry,
        cache_policy: :snapshot,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry-binding",
        time_context: overlapping_context
      )

    outside_snapshot_key =
      source_result_key(:telemetry,
        cache_policy: :snapshot,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry-binding",
        request_id: "source_req_telemetry_outside",
        time_context: outside_context
      )

    live_key =
      source_result_key(:telemetry,
        cache_policy: :live,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry-binding",
        request_id: "source_req_telemetry_live",
        time_context: overlapping_context
      )

    snapshot_frame_key =
      frame_key(:telemetry,
        cache_policy: :snapshot,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry-binding",
        time_context: overlapping_context
      )

    outside_frame_key =
      frame_key(:telemetry,
        cache_policy: :snapshot,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry-binding",
        request_id: "source_req_telemetry_outside",
        placement_id: "placement_power_outside",
        time_context: outside_context
      )

    live_frame_key =
      frame_key(:telemetry,
        cache_policy: :live,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry-binding",
        request_id: "source_req_telemetry_live",
        placement_id: "placement_power_live",
        time_context: overlapping_context
      )

    snapshot_result = source_result(:telemetry, request_id: snapshot_key.parts.request.request_id)

    outside_result =
      source_result(:telemetry, request_id: outside_snapshot_key.parts.request.request_id)

    live_result = source_result(:telemetry, request_id: live_key.parts.request.request_id)
    snapshot_frames = frames(:telemetry, frame_id: "frame-snapshot")
    outside_frames = frames(:telemetry, frame_id: "frame-outside")
    live_frames = frames(:telemetry, frame_id: "frame-live")

    assert :ok = RuntimeCache.put_source_result(snapshot_key, snapshot_result, cache)
    assert :ok = RuntimeCache.put_source_result(outside_snapshot_key, outside_result, cache)
    assert :ok = RuntimeCache.put_source_result(live_key, live_result, cache)
    assert :ok = RuntimeCache.put_frame(snapshot_frame_key, snapshot_frames, cache)
    assert :ok = RuntimeCache.put_frame(outside_frame_key, outside_frames, cache)
    assert :ok = RuntimeCache.put_frame(live_frame_key, live_frames, cache)

    assert %{plans: 0, source_results: 1, frames: 1} =
             RuntimeInvalidation.historical_data_changed(
               %{
                 logical_source: :telemetry,
                 source_id: "flight-questdb",
                 binding_id: "flight-telemetry-binding",
                 reason: :backfill,
                 revision: "telemetry-revision-42",
                 evidence_ref: %{kind: "ingest_batch", id: "batch-42"},
                 time_range: %{
                   axis: :receipt_time,
                   from: ~U[2026-06-17 12:05:00Z],
                   to: ~U[2026-06-17 12:06:00Z]
                 }
               },
               runtime_cache: cache
             )

    assert RuntimeCache.get_source_result(snapshot_key, cache) == :miss
    assert {:ok, ^outside_result} = RuntimeCache.get_source_result(outside_snapshot_key, cache)
    assert {:ok, ^live_result} = RuntimeCache.get_source_result(live_key, cache)
    assert RuntimeCache.get_frame(snapshot_frame_key, cache) == :miss
    assert {:ok, ^outside_frames} = RuntimeCache.get_frame(outside_frame_key, cache)
    assert {:ok, ^live_frames} = RuntimeCache.get_frame(live_frame_key, cache)
  end

  test "historical data changes invalidate overlapping segmented snapshot artifacts" do
    cache = start_supervised!({RuntimeCache, name: nil})

    overlapping_context =
      archive_time_context(~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:10:00Z])

    outside_context =
      archive_time_context(~U[2026-06-17 13:00:00Z], ~U[2026-06-17 13:10:00Z])

    overlapping_key =
      segmented_source_result_key(
        cache_policy: :snapshot,
        time_context: overlapping_context
      )

    outside_key =
      segmented_source_result_key(
        cache_policy: :snapshot,
        request_id: "source_req_telemetry_segmented_outside",
        time_context: outside_context
      )

    overlapping_frame_key =
      segmented_frame_key(
        cache_policy: :snapshot,
        time_context: overlapping_context
      )

    outside_frame_key =
      segmented_frame_key(
        cache_policy: :snapshot,
        request_id: "source_req_telemetry_segmented_outside",
        placement_id: "placement_segmented_outside",
        time_context: outside_context
      )

    overlapping_result =
      source_result(:telemetry, request_id: overlapping_key.parts.request.request_id)

    outside_result = source_result(:telemetry, request_id: outside_key.parts.request.request_id)
    overlapping_frames = frames(:telemetry, frame_id: "frame-segmented-overlapping")
    outside_frames = frames(:telemetry, frame_id: "frame-segmented-outside")

    assert :ok = RuntimeCache.put_source_result(overlapping_key, overlapping_result, cache)
    assert :ok = RuntimeCache.put_source_result(outside_key, outside_result, cache)
    assert :ok = RuntimeCache.put_frame(overlapping_frame_key, overlapping_frames, cache)
    assert :ok = RuntimeCache.put_frame(outside_frame_key, outside_frames, cache)

    assert %{plans: 0, source_results: 1, frames: 1} =
             RuntimeInvalidation.historical_data_changed(
               %{
                 logical_source: :telemetry,
                 source_id: "flight-questdb-v2",
                 binding_id: "flight-telemetry-binding",
                 time_range: %{
                   axis: :receipt_time,
                   from: ~U[2026-06-17 12:06:00Z],
                   to: ~U[2026-06-17 12:07:00Z]
                 }
               },
               runtime_cache: cache
             )

    assert RuntimeCache.get_source_result(overlapping_key, cache) == :miss
    assert {:ok, ^outside_result} = RuntimeCache.get_source_result(outside_key, cache)
    assert RuntimeCache.get_frame(overlapping_frame_key, cache) == :miss
    assert {:ok, ^outside_frames} = RuntimeCache.get_frame(outside_frame_key, cache)
  end

  test "historical data changes do not invalidate non-overlapping snapshot ranges" do
    cache = start_supervised!({RuntimeCache, name: nil})
    time_context = archive_time_context(~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:10:00Z])

    source_key =
      source_result_key(:telemetry, cache_policy: :snapshot, time_context: time_context)

    frame_key = frame_key(:telemetry, cache_policy: :snapshot, time_context: time_context)
    source_result = source_result(:telemetry)
    telemetry_frames = frames(:telemetry)

    assert :ok = RuntimeCache.put_source_result(source_key, source_result, cache)
    assert :ok = RuntimeCache.put_frame(frame_key, telemetry_frames, cache)

    assert %{plans: 0, source_results: 0, frames: 0} =
             RuntimeInvalidation.historical_data_changed(
               %{
                 logical_source: :telemetry,
                 time_range: %{
                   axis: :receipt_time,
                   from: ~U[2026-06-17 12:11:00Z],
                   to: ~U[2026-06-17 12:12:00Z]
                 }
               },
               runtime_cache: cache
             )

    assert {:ok, ^source_result} = RuntimeCache.get_source_result(source_key, cache)
    assert {:ok, ^telemetry_frames} = RuntimeCache.get_frame(frame_key, cache)
  end

  test "historical data changes can target one replay run snapshot" do
    cache = start_supervised!({RuntimeCache, name: nil})
    attach_runtime_invalidation_telemetry(self())
    first_context = replay_time_context("replay-run-1")
    second_context = replay_time_context("replay-run-2")

    first_key =
      source_result_key(:telemetry,
        cache_policy: :snapshot,
        time_context: first_context
      )

    second_key =
      source_result_key(:telemetry,
        cache_policy: :snapshot,
        request_id: "source_req_telemetry_replay_2",
        time_context: second_context
      )

    first_frame_key =
      frame_key(:telemetry,
        cache_policy: :snapshot,
        time_context: first_context
      )

    second_frame_key =
      frame_key(:telemetry,
        cache_policy: :snapshot,
        request_id: "source_req_telemetry_replay_2",
        placement_id: "placement_replay_2",
        time_context: second_context
      )

    first_result = source_result(:telemetry, request_id: first_key.parts.request.request_id)
    second_result = source_result(:telemetry, request_id: second_key.parts.request.request_id)
    first_frames = frames(:telemetry, frame_id: "frame-replay-1")
    second_frames = frames(:telemetry, frame_id: "frame-replay-2")

    assert :ok = RuntimeCache.put_source_result(first_key, first_result, cache)
    assert :ok = RuntimeCache.put_source_result(second_key, second_result, cache)
    assert :ok = RuntimeCache.put_frame(first_frame_key, first_frames, cache)
    assert :ok = RuntimeCache.put_frame(second_frame_key, second_frames, cache)

    assert %{plans: 0, source_results: 1, frames: 1} =
             RuntimeInvalidation.historical_data_changed(
               %{
                 logical_source: :telemetry,
                 replay_run_id: "replay-run-1"
               },
               runtime_cache: cache
             )

    assert_receive {:runtime_invalidation_telemetry, _event, _measurements, metadata}
    assert metadata.filters.replay_run_id == "replay-run-1"
    assert metadata.layer_filters.source_result.replay_run_id == "replay-run-1"
    assert metadata.layer_filters.frame.replay_run_id == "replay-run-1"

    assert RuntimeCache.get_source_result(first_key, cache) == :miss
    assert {:ok, ^second_result} = RuntimeCache.get_source_result(second_key, cache)
    assert RuntimeCache.get_frame(first_frame_key, cache) == :miss
    assert {:ok, ^second_frames} = RuntimeCache.get_frame(second_frame_key, cache)
  end

  test "source watermark changes default to live cache entries" do
    cache = start_supervised!({RuntimeCache, name: nil})
    time_context = archive_time_context(~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:10:00Z])
    live_key = source_result_key(:telemetry, cache_policy: :live, time_context: time_context)

    snapshot_key =
      source_result_key(:telemetry, cache_policy: :snapshot, time_context: time_context)

    live_frame_key = frame_key(:telemetry, cache_policy: :live, time_context: time_context)

    snapshot_frame_key =
      frame_key(:telemetry, cache_policy: :snapshot, time_context: time_context)

    live_result = source_result(:telemetry, request_id: "source_req_telemetry")
    snapshot_result = source_result(:telemetry, request_id: "source_req_telemetry")
    live_frames = frames(:telemetry, frame_id: "frame-live")
    snapshot_frames = frames(:telemetry, frame_id: "frame-snapshot")

    assert :ok = RuntimeCache.put_source_result(live_key, live_result, cache)
    assert :ok = RuntimeCache.put_source_result(snapshot_key, snapshot_result, cache)
    assert :ok = RuntimeCache.put_frame(live_frame_key, live_frames, cache)
    assert :ok = RuntimeCache.put_frame(snapshot_frame_key, snapshot_frames, cache)

    assert %{plans: 0, source_results: 1, frames: 1} =
             RuntimeInvalidation.source_watermark_changed(
               %{logical_source: :telemetry},
               runtime_cache: cache
             )

    assert RuntimeCache.get_source_result(live_key, cache) == :miss
    assert {:ok, ^snapshot_result} = RuntimeCache.get_source_result(snapshot_key, cache)
    assert RuntimeCache.get_frame(live_frame_key, cache) == :miss
    assert {:ok, ^snapshot_frames} = RuntimeCache.get_frame(snapshot_frame_key, cache)
  end

  test "source watermark changes invalidate only matching replay run live artifacts" do
    cache = start_supervised!({RuntimeCache, name: nil})
    attach_runtime_invalidation_telemetry(self())
    first_context = replay_time_context("replay-run-1")
    second_context = replay_time_context("replay-run-2")

    first_key =
      source_result_key(:telemetry,
        cache_policy: :live,
        data_source_id: "replay-questdb",
        source_binding_id: "replay-telemetry-binding",
        realm: :replay,
        time_context: first_context
      )

    second_key =
      source_result_key(:telemetry,
        cache_policy: :live,
        data_source_id: "replay-questdb",
        source_binding_id: "replay-telemetry-binding",
        realm: :replay,
        request_id: "source_req_telemetry_replay_2",
        time_context: second_context
      )

    first_frame_key =
      frame_key(:telemetry,
        cache_policy: :live,
        data_source_id: "replay-questdb",
        source_binding_id: "replay-telemetry-binding",
        realm: :replay,
        time_context: first_context
      )

    second_frame_key =
      frame_key(:telemetry,
        cache_policy: :live,
        data_source_id: "replay-questdb",
        source_binding_id: "replay-telemetry-binding",
        realm: :replay,
        request_id: "source_req_telemetry_replay_2",
        placement_id: "placement_replay_2",
        time_context: second_context
      )

    first_result = source_result(:telemetry, request_id: first_key.parts.request.request_id)
    second_result = source_result(:telemetry, request_id: second_key.parts.request.request_id)
    first_frames = frames(:telemetry, frame_id: "frame-watermark-replay-1")
    second_frames = frames(:telemetry, frame_id: "frame-watermark-replay-2")

    assert :ok = RuntimeCache.put_source_result(first_key, first_result, cache)
    assert :ok = RuntimeCache.put_source_result(second_key, second_result, cache)
    assert :ok = RuntimeCache.put_frame(first_frame_key, first_frames, cache)
    assert :ok = RuntimeCache.put_frame(second_frame_key, second_frames, cache)

    assert %{plans: 0, source_results: 1, frames: 1} =
             RuntimeInvalidation.source_watermark_changed(
               %{
                 organization_id: "org_dashboards",
                 mission_id: "mission_dashboards",
                 logical_source: :telemetry,
                 data_source_id: "replay-questdb",
                 source_binding_id: "replay-telemetry-binding",
                 realm: :replay,
                 replay_run_id: "replay-run-1"
               },
               runtime_cache: cache
             )

    assert_receive {:runtime_invalidation_telemetry, _event, _measurements, metadata}
    assert metadata.filters.replay_run_id == "replay-run-1"
    assert metadata.layer_filters.source_result.replay_run_id == "replay-run-1"
    assert metadata.layer_filters.frame.replay_run_id == "replay-run-1"

    assert RuntimeCache.get_source_result(first_key, cache) == :miss
    assert {:ok, ^second_result} = RuntimeCache.get_source_result(second_key, cache)
    assert RuntimeCache.get_frame(first_frame_key, cache) == :miss
    assert {:ok, ^second_frames} = RuntimeCache.get_frame(second_frame_key, cache)
  end

  test "telemetry revision state changes invalidate matching live and snapshot artifacts" do
    cache = start_supervised!({RuntimeCache, name: nil})
    matching_dependency = telemetry_revision_dependency("identity-affected", "conflict")
    unrelated_dependency = telemetry_revision_dependency("identity-other", "other")

    live_key =
      source_result_key(:telemetry,
        request_id: "source_req_telemetry_live_revision",
        cache_policy: :live
      )

    snapshot_key =
      source_result_key(:telemetry,
        request_id: "source_req_telemetry_snapshot_revision",
        cache_policy: :snapshot
      )

    unrelated_key =
      source_result_key(:telemetry,
        request_id: "source_req_telemetry_other_revision",
        cache_policy: :live
      )

    live_frame_key =
      frame_key(:telemetry,
        request_id: "source_req_telemetry_live_revision",
        cache_policy: :live,
        telemetry_revision_dependency: matching_dependency
      )

    snapshot_frame_key =
      frame_key(:telemetry,
        request_id: "source_req_telemetry_snapshot_revision",
        cache_policy: :snapshot,
        telemetry_revision_dependency: matching_dependency
      )

    unrelated_frame_key =
      frame_key(:telemetry,
        request_id: "source_req_telemetry_other_revision",
        cache_policy: :live,
        telemetry_revision_dependency: unrelated_dependency
      )

    live_result =
      source_result(:telemetry,
        request_id: "source_req_telemetry_live_revision",
        telemetry_revision_dependency: matching_dependency
      )

    snapshot_result =
      source_result(:telemetry,
        request_id: "source_req_telemetry_snapshot_revision",
        telemetry_revision_dependency: matching_dependency
      )

    unrelated_result =
      source_result(:telemetry,
        request_id: "source_req_telemetry_other_revision",
        telemetry_revision_dependency: unrelated_dependency
      )

    live_frames = frames(:telemetry, frame_id: "frame-live-revision")
    snapshot_frames = frames(:telemetry, frame_id: "frame-snapshot-revision")
    unrelated_frames = frames(:telemetry, frame_id: "frame-other-revision")

    assert :ok = RuntimeCache.put_source_result(live_key, live_result, cache)
    assert :ok = RuntimeCache.put_source_result(snapshot_key, snapshot_result, cache)
    assert :ok = RuntimeCache.put_source_result(unrelated_key, unrelated_result, cache)
    assert :ok = RuntimeCache.put_frame(live_frame_key, live_frames, cache)
    assert :ok = RuntimeCache.put_frame(snapshot_frame_key, snapshot_frames, cache)
    assert :ok = RuntimeCache.put_frame(unrelated_frame_key, unrelated_frames, cache)

    assert %{plans: 0, source_results: 2, frames: 2} =
             RuntimeInvalidation.telemetry_revision_state_changed(
               %{
                 organization_id: "org_dashboards",
                 mission_id: "mission_dashboards",
                 data_source_id: "telemetry-questdb",
                 source_binding_id: "flight-telemetry-binding",
                 realm: :flight,
                 observable: "battery_voltage",
                 observation_identity_id: "identity-affected"
               },
               runtime_cache: cache
             )

    assert RuntimeCache.get_source_result(live_key, cache) == :miss
    assert RuntimeCache.get_source_result(snapshot_key, cache) == :miss
    assert {:ok, ^unrelated_result} = RuntimeCache.get_source_result(unrelated_key, cache)
    assert RuntimeCache.get_frame(live_frame_key, cache) == :miss
    assert RuntimeCache.get_frame(snapshot_frame_key, cache) == :miss
    assert {:ok, ^unrelated_frames} = RuntimeCache.get_frame(unrelated_frame_key, cache)
  end

  test "source health changes invalidate scoped live artifacts and preserve snapshots" do
    cache = start_supervised!({RuntimeCache, name: nil})
    time_context = archive_time_context(~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:10:00Z])

    live_key =
      source_result_key(:telemetry,
        cache_policy: :live,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry-binding",
        time_context: time_context
      )

    snapshot_key =
      source_result_key(:telemetry,
        cache_policy: :snapshot,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry-binding",
        time_context: time_context
      )

    unrelated_live_key =
      source_result_key(:telemetry,
        cache_policy: :live,
        data_source_id: "rehearsal-questdb",
        source_binding_id: "rehearsal-telemetry-binding",
        request_id: "source_req_telemetry_rehearsal",
        time_context: time_context
      )

    live_frame_key =
      frame_key(:telemetry,
        cache_policy: :live,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry-binding",
        time_context: time_context
      )

    snapshot_frame_key =
      frame_key(:telemetry,
        cache_policy: :snapshot,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry-binding",
        time_context: time_context
      )

    unrelated_frame_key =
      frame_key(:telemetry,
        cache_policy: :live,
        data_source_id: "rehearsal-questdb",
        source_binding_id: "rehearsal-telemetry-binding",
        request_id: "source_req_telemetry_rehearsal",
        placement_id: "placement_power_rehearsal",
        time_context: time_context
      )

    live_result = source_result(:telemetry, request_id: live_key.parts.request.request_id)
    snapshot_result = source_result(:telemetry, request_id: snapshot_key.parts.request.request_id)

    unrelated_live_result =
      source_result(:telemetry, request_id: unrelated_live_key.parts.request.request_id)

    live_frames = frames(:telemetry, frame_id: "frame-live-health")
    snapshot_frames = frames(:telemetry, frame_id: "frame-snapshot-health")
    unrelated_frames = frames(:telemetry, frame_id: "frame-rehearsal-health")

    assert :ok = RuntimeCache.put_source_result(live_key, live_result, cache)
    assert :ok = RuntimeCache.put_source_result(snapshot_key, snapshot_result, cache)
    assert :ok = RuntimeCache.put_source_result(unrelated_live_key, unrelated_live_result, cache)
    assert :ok = RuntimeCache.put_frame(live_frame_key, live_frames, cache)
    assert :ok = RuntimeCache.put_frame(snapshot_frame_key, snapshot_frames, cache)
    assert :ok = RuntimeCache.put_frame(unrelated_frame_key, unrelated_frames, cache)

    assert %{plans: 0, source_results: 1, frames: 1} =
             RuntimeInvalidation.source_health_changed(
               %{
                 organization_id: "org_dashboards",
                 mission_id: "mission_dashboards",
                 logical_source: "telemetry",
                 source_id: "flight-questdb",
                 binding_id: "flight-telemetry-binding",
                 source_health: :degraded,
                 previous_source_health: :healthy,
                 reason: :source_probe_failed,
                 observed_at: ~U[2026-06-17 12:02:00Z],
                 evidence_ref: %{kind: "source_health_probe", id: "probe-42"}
               },
               runtime_cache: cache
             )

    assert RuntimeCache.get_source_result(live_key, cache) == :miss
    assert {:ok, ^snapshot_result} = RuntimeCache.get_source_result(snapshot_key, cache)

    assert {:ok, ^unrelated_live_result} =
             RuntimeCache.get_source_result(unrelated_live_key, cache)

    assert RuntimeCache.get_frame(live_frame_key, cache) == :miss
    assert {:ok, ^snapshot_frames} = RuntimeCache.get_frame(snapshot_frame_key, cache)
    assert {:ok, ^unrelated_frames} = RuntimeCache.get_frame(unrelated_frame_key, cache)
  end

  test "source health changes invalidate only matching replay run live artifacts" do
    cache = start_supervised!({RuntimeCache, name: nil})
    attach_runtime_invalidation_telemetry(self())
    first_context = replay_time_context("replay-run-health-1")
    second_context = replay_time_context("replay-run-health-2")

    first_key =
      source_result_key(:telemetry,
        cache_policy: :live,
        data_source_id: "replay-questdb",
        source_binding_id: "replay-telemetry-binding",
        realm: :replay,
        time_context: first_context
      )

    second_key =
      source_result_key(:telemetry,
        cache_policy: :live,
        data_source_id: "replay-questdb",
        source_binding_id: "replay-telemetry-binding",
        realm: :replay,
        request_id: "source_req_telemetry_health_replay_2",
        time_context: second_context
      )

    first_frame_key =
      frame_key(:telemetry,
        cache_policy: :live,
        data_source_id: "replay-questdb",
        source_binding_id: "replay-telemetry-binding",
        realm: :replay,
        time_context: first_context
      )

    second_frame_key =
      frame_key(:telemetry,
        cache_policy: :live,
        data_source_id: "replay-questdb",
        source_binding_id: "replay-telemetry-binding",
        realm: :replay,
        request_id: "source_req_telemetry_health_replay_2",
        placement_id: "placement_health_replay_2",
        time_context: second_context
      )

    first_result = source_result(:telemetry, request_id: first_key.parts.request.request_id)
    second_result = source_result(:telemetry, request_id: second_key.parts.request.request_id)
    first_frames = frames(:telemetry, frame_id: "frame-health-replay-1")
    second_frames = frames(:telemetry, frame_id: "frame-health-replay-2")

    assert :ok = RuntimeCache.put_source_result(first_key, first_result, cache)
    assert :ok = RuntimeCache.put_source_result(second_key, second_result, cache)
    assert :ok = RuntimeCache.put_frame(first_frame_key, first_frames, cache)
    assert :ok = RuntimeCache.put_frame(second_frame_key, second_frames, cache)

    assert %{plans: 0, source_results: 1, frames: 1} =
             RuntimeInvalidation.source_health_changed(
               %{
                 organization_id: "org_dashboards",
                 mission_id: "mission_dashboards",
                 logical_source: :telemetry,
                 data_source_id: "replay-questdb",
                 source_binding_id: "replay-telemetry-binding",
                 realm: :replay,
                 replay_run_id: "replay-run-health-1",
                 source_health: :degraded,
                 previous_source_health: :healthy,
                 reason: :source_probe_failed,
                 observed_at: ~U[2026-06-17 12:02:00Z]
               },
               runtime_cache: cache
             )

    assert_receive {:runtime_invalidation_telemetry, _event, _measurements, metadata}
    assert metadata.filters.replay_run_id == "replay-run-health-1"
    assert metadata.layer_filters.source_result.replay_run_id == "replay-run-health-1"
    assert metadata.layer_filters.frame.replay_run_id == "replay-run-health-1"

    assert RuntimeCache.get_source_result(first_key, cache) == :miss
    assert {:ok, ^second_result} = RuntimeCache.get_source_result(second_key, cache)
    assert RuntimeCache.get_frame(first_frame_key, cache) == :miss
    assert {:ok, ^second_frames} = RuntimeCache.get_frame(second_frame_key, cache)
  end

  test "events changes invalidate live event source artifacts and preserve snapshots" do
    cache = start_supervised!({RuntimeCache, name: nil})
    time_context = archive_time_context(~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:10:00Z])

    live_key =
      source_result_key(:events,
        cache_policy: :live,
        data_source_id: "events-store",
        source_binding_id: "flight-events-binding",
        time_context: time_context
      )

    snapshot_key =
      source_result_key(:events,
        cache_policy: :snapshot,
        data_source_id: "events-store",
        source_binding_id: "flight-events-binding",
        time_context: time_context
      )

    live_frame_key =
      frame_key(:events,
        cache_policy: :live,
        data_source_id: "events-store",
        source_binding_id: "flight-events-binding",
        time_context: time_context
      )

    snapshot_frame_key =
      frame_key(:events,
        cache_policy: :snapshot,
        data_source_id: "events-store",
        source_binding_id: "flight-events-binding",
        time_context: time_context
      )

    live_result = source_result(:events, data_source_id: "events-store")
    snapshot_result = source_result(:events, data_source_id: "events-store")
    live_frames = frames(:events, frame_id: "frame-events-live")
    snapshot_frames = frames(:events, frame_id: "frame-events-snapshot")

    assert :ok = RuntimeCache.put_source_result(live_key, live_result, cache)
    assert :ok = RuntimeCache.put_source_result(snapshot_key, snapshot_result, cache)
    assert :ok = RuntimeCache.put_frame(live_frame_key, live_frames, cache)
    assert :ok = RuntimeCache.put_frame(snapshot_frame_key, snapshot_frames, cache)

    assert %{plans: 0, source_results: 1, frames: 1} =
             RuntimeInvalidation.events_changed(
               %{
                 organization_id: "org_dashboards",
                 mission_id: "mission_dashboards",
                 data_source_id: "events-store",
                 source_binding_id: "flight-events-binding"
               },
               runtime_cache: cache
             )

    assert RuntimeCache.get_source_result(live_key, cache) == :miss
    assert {:ok, ^snapshot_result} = RuntimeCache.get_source_result(snapshot_key, cache)
    assert RuntimeCache.get_frame(live_frame_key, cache) == :miss
    assert {:ok, ^snapshot_frames} = RuntimeCache.get_frame(snapshot_frame_key, cache)
  end

  defp resolve_request(%Document{} = document) do
    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
      interaction_context: %{
        placement_sizes: %{"placement_battery_voltage" => %{width_px: 320, height_px: 128}}
      }
    }
  end

  defp attach_runtime_invalidation_telemetry(test_pid) do
    handler_id = "dashboard-runtime-invalidation-test-#{System.unique_integer([:positive])}"

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

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> Dashboards.load_document!()
  end

  defp source_result_key(logical_source, opts \\ []) do
    request = source_request(logical_source, opts)
    data_source_id = Keyword.get(opts, :data_source_id, "#{logical_source}-questdb")
    realm = Keyword.get(opts, :realm, :flight)

    RuntimeCacheKey.source_result(request,
      cache_policy: Keyword.get(opts, :cache_policy, :live),
      source_binding: source_binding(logical_source, realm, data_source_id, opts),
      data_source: data_source(logical_source, data_source_id),
      watermark: source_watermark(logical_source, data_source_id, opts)
    )
  end

  defp source_request(logical_source, opts) do
    %PlannedSourceRequest{
      request_id: Keyword.get(opts, :request_id, "source_req_#{logical_source}"),
      organization_id: Keyword.get(opts, :organization_id, "org_dashboards"),
      mission_id: Keyword.get(opts, :mission_id, "mission_dashboards"),
      logical_source: logical_source,
      observables: Keyword.get(opts, :observables, ["battery_voltage"]),
      time_context: Keyword.get(opts, :time_context, %{}),
      sampling: %{mode: :latest}
    }
  end

  defp source_result(logical_source, opts \\ []) do
    data_source_id = Keyword.get(opts, :data_source_id, "#{logical_source}-questdb")

    %SourceResult{
      request_id: Keyword.get(opts, :request_id, "source_req_#{logical_source}"),
      meta:
        opts
        |> Keyword.take([:telemetry_revision_dependency])
        |> Map.new(),
      watermarks: [source_watermark(logical_source, data_source_id, opts)]
    }
  end

  defp frame_key(logical_source, opts \\ []) do
    logical_source
    |> source_result_key(opts)
    |> RuntimeCacheKey.frame(
      placement_id: Keyword.get(opts, :placement_id, "placement_power"),
      placement_size: Keyword.get(opts, :placement_size, %{width_px: 320, height_px: 120}),
      display: Keyword.get(opts, :display, %{density: :normal}),
      frame_shape: Keyword.get(opts, :frame_shape, frame_shape(logical_source)),
      limit_context: Keyword.get(opts, :limit_context),
      catalog_revision: Keyword.get(opts, :catalog_revision),
      telemetry_revision_dependency: Keyword.get(opts, :telemetry_revision_dependency)
    )
  end

  defp segmented_source_result_key(opts \\ []) do
    RuntimeCacheKey.source_result(
      source_request(:telemetry, opts),
      cache_policy: Keyword.get(opts, :cache_policy, :snapshot),
      source_binding_segments:
        Keyword.get(opts, :source_binding_segments, source_binding_segments())
    )
  end

  defp segmented_frame_key(opts \\ []) do
    opts
    |> segmented_source_result_key()
    |> RuntimeCacheKey.frame(
      placement_id: Keyword.get(opts, :placement_id, "placement_power"),
      placement_size: Keyword.get(opts, :placement_size, %{width_px: 320, height_px: 120}),
      display: Keyword.get(opts, :display, %{density: :normal}),
      frame_shape: Keyword.get(opts, :frame_shape, :wide),
      limit_context: Keyword.get(opts, :limit_context),
      catalog_revision: Keyword.get(opts, :catalog_revision)
    )
  end

  defp source_binding_segments(opts \\ []) do
    source_binding_id = Keyword.get(opts, :source_binding_id, "flight-telemetry-binding")
    realm = Keyword.get(opts, :realm, :flight)

    [
      %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:05:00Z],
        binding_id: source_binding_id,
        data_binding_event_id: Keyword.get(opts, :first_event_id, "binding-event-v1"),
        data_source_id: Keyword.get(opts, :first_data_source_id, "flight-questdb-v1"),
        dataset: Keyword.get(opts, :first_dataset, "flight-v1"),
        realm: realm
      },
      %{
        from: ~U[2026-06-17 12:05:00Z],
        to: ~U[2026-06-17 12:10:00Z],
        binding_id: source_binding_id,
        data_binding_event_id: Keyword.get(opts, :second_event_id, "binding-event-v2"),
        data_source_id: Keyword.get(opts, :second_data_source_id, "flight-questdb-v2"),
        dataset: Keyword.get(opts, :second_dataset, "flight-v2"),
        realm: realm
      }
    ]
  end

  defp frames(logical_source, opts \\ []) do
    [
      %Frame{
        frame_id: Keyword.get(opts, :frame_id, "frame_#{logical_source}"),
        source: logical_source,
        shape: frame_shape(logical_source),
        fields: []
      }
    ]
  end

  defp frame_shape(:limits), do: :events
  defp frame_shape(:events), do: :events
  defp frame_shape(_logical_source), do: :scalar

  defp telemetry_revision_dependency(observation_identity_id, fingerprint) do
    %{
      kind: :telemetry_observation_identity_state,
      fingerprint: fingerprint,
      observation_identity_ids: [observation_identity_id]
    }
  end

  defp source_binding(logical_source, realm, data_source_id, opts) do
    %DataBinding{
      binding_id: Keyword.get(opts, :source_binding_id, "#{realm}-#{logical_source}-binding"),
      organization_id: Keyword.get(opts, :organization_id, "org_dashboards"),
      mission_id: Keyword.get(opts, :mission_id, "mission_dashboards"),
      realm: realm,
      logical_source: logical_source,
      data_source_id: data_source_id,
      dataset: Atom.to_string(realm)
    }
  end

  defp data_source(logical_source, data_source_id) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: source_adapter(logical_source),
      capabilities: %{latest?: true, range_scan?: true, watermarks?: true}
    }
  end

  defp source_adapter(:telemetry), do: Cadence.Dashboards.Sources.Telemetry
  defp source_adapter(:limits), do: Cadence.Dashboards.Sources.Limits
  defp source_adapter(:events), do: Cadence.Dashboards.Sources.Events

  defp archive_time_context(from, to) do
    %{mode: :archive, axis: :receipt_time, from: from, to: to}
  end

  defp source_watermark(logical_source, data_source_id, opts) do
    complete_through = Keyword.get(opts, :complete_through, ~U[2026-06-17 12:00:00Z])
    realm = Keyword.get(opts, :realm, :flight)

    %SourceWatermark{
      logical_source: logical_source,
      request_id: Keyword.get(opts, :request_id, "source_req_#{logical_source}"),
      source_binding_id:
        Keyword.get(opts, :source_binding_id, "#{realm}-#{logical_source}-binding"),
      data_source_id: data_source_id,
      realm: realm,
      dataset: Atom.to_string(realm),
      complete_through: complete_through,
      latest_receipt_time: complete_through,
      retention_starts_at: ~U[2026-06-17 11:00:00Z],
      confidence: Keyword.get(opts, :watermark_confidence, :best_effort),
      freshness_state: Keyword.get(opts, :watermark_freshness_state, :fresh)
    }
  end

  defp replay_time_context(replay_run_id) do
    %{mode: :replay_run, axis: :generation_time, replay_run_id: replay_run_id}
  end
end
