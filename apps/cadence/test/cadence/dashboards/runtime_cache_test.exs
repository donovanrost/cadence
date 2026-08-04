defmodule Cadence.Dashboards.RuntimeCacheTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DashboardResolveResult,
    Document,
    Engine,
    Frame,
    PlannedSourceRequest,
    RuntimeCache,
    RuntimeCacheKey,
    SourceResult
  }

  alias Cadence.DataSources.SourceWatermark

  alias Cadence.DataSources.{DataBinding, DataSource}

  @fixture_dir Path.expand("../../fixtures/dashboards", __DIR__)

  test "stores and resets plan results by runtime cache key" do
    cache = start_supervised!({RuntimeCache, name: nil})
    document = load_fixture!("value_tile_latest.v1.json")
    request = resolve_request(document)
    key = RuntimeCacheKey.plan(request)
    result = %DashboardResolveResult{dashboard_id: document.dashboard_id}

    assert RuntimeCache.get_plan(key, cache) == :miss
    assert :ok = RuntimeCache.put_plan(key, result, cache)
    assert {:ok, ^result} = RuntimeCache.get_plan(key, cache)
    assert :ok = RuntimeCache.reset(cache)
    assert RuntimeCache.get_plan(key, cache) == :miss
  end

  test "engine plan cache misses then hits for identical document and context" do
    cache = start_supervised!({RuntimeCache, name: nil})
    document = load_fixture!("value_tile_latest.v1.json")
    request = resolve_request(document)

    miss = Engine.plan(request, runtime_cache: cache)
    hit = Engine.plan(request, runtime_cache: cache)

    assert miss.plan_metadata.cache.plan_cache.status == :miss
    assert hit.plan_metadata.cache.plan_cache.status == :hit

    assert hit.plan_metadata.cache.plan_key.fingerprint ==
             miss.plan_metadata.cache.plan_key.fingerprint

    assert hit.planned_source_requests == miss.planned_source_requests
  end

  test "engine plan cache metadata records derived dependency versions" do
    cache = start_supervised!({RuntimeCache, name: nil})
    document = load_fixture!("value_tile_latest.v1.json")
    request = resolve_request(document)

    miss = Engine.plan(request, runtime_cache: cache)
    hit = Engine.plan(request, runtime_cache: cache)

    dependencies = miss.plan_metadata.cache.dependencies

    assert dependencies.document_schema_version == document.schema_version
    assert is_binary(dependencies.widget_registry_version)
    assert is_binary(dependencies.source_capability_version)

    assert miss.plan_metadata.cache.plan_key.parts.widget_registry_version ==
             dependencies.widget_registry_version

    assert miss.plan_metadata.cache.plan_key.parts.source_capability_version ==
             dependencies.source_capability_version

    assert hit.plan_metadata.cache.plan_cache.status == :hit
    assert hit.plan_metadata.cache.dependencies == dependencies
  end

  test "engine plan cache misses when runtime context changes" do
    cache = start_supervised!({RuntimeCache, name: nil})
    document = load_fixture!("value_tile_latest.v1.json")

    flight =
      Engine.plan(resolve_request(document, data_context: %{realm: :flight}),
        runtime_cache: cache
      )

    rehearsal =
      Engine.plan(resolve_request(document, data_context: %{realm: :rehearsal}),
        runtime_cache: cache
      )

    assert flight.plan_metadata.cache.plan_cache.status == :miss
    assert rehearsal.plan_metadata.cache.plan_cache.status == :miss

    assert flight.plan_metadata.cache.plan_key.fingerprint !=
             rehearsal.plan_metadata.cache.plan_key.fingerprint
  end

  test "engine plan cache misses when document version changes" do
    cache = start_supervised!({RuntimeCache, name: nil})
    document = load_fixture!("value_tile_latest.v1.json")

    v1 = Engine.plan(resolve_request(document), runtime_cache: cache, document_version: 1)
    v2 = Engine.plan(resolve_request(document), runtime_cache: cache, document_version: 2)

    assert v1.plan_metadata.cache.plan_cache.status == :miss
    assert v2.plan_metadata.cache.plan_cache.status == :miss

    assert v1.plan_metadata.cache.plan_key.fingerprint !=
             v2.plan_metadata.cache.plan_key.fingerprint
  end

  test "engine plan cache misses when source capability version changes" do
    cache = start_supervised!({RuntimeCache, name: nil})
    document = load_fixture!("value_tile_latest.v1.json")
    request = resolve_request(document)

    v1 = Engine.plan(request, runtime_cache: cache, source_capability_version: "sources:v1")
    v2 = Engine.plan(request, runtime_cache: cache, source_capability_version: "sources:v2")

    assert v1.plan_metadata.cache.plan_cache.status == :miss
    assert v2.plan_metadata.cache.plan_cache.status == :miss

    assert v1.plan_metadata.cache.plan_key.fingerprint !=
             v2.plan_metadata.cache.plan_key.fingerprint
  end

  test "engine plan cache misses when widget registry version changes" do
    cache = start_supervised!({RuntimeCache, name: nil})
    document = load_fixture!("value_tile_latest.v1.json")
    request = resolve_request(document)

    v1 = Engine.plan(request, runtime_cache: cache, widget_registry_version: "widgets:v1")
    hit = Engine.plan(request, runtime_cache: cache, widget_registry_version: "widgets:v1")
    v2 = Engine.plan(request, runtime_cache: cache, widget_registry_version: "widgets:v2")

    assert v1.plan_metadata.cache.plan_cache.status == :miss
    assert hit.plan_metadata.cache.plan_cache.status == :hit
    assert v2.plan_metadata.cache.plan_cache.status == :miss

    assert v1.plan_metadata.cache.plan_key.fingerprint !=
             v2.plan_metadata.cache.plan_key.fingerprint
  end

  test "engine plan cache misses when derived source capability fingerprint changes" do
    cache = start_supervised!({RuntimeCache, name: nil})
    document = load_fixture!("value_tile_latest.v1.json")
    request = resolve_request(document)

    capable_opts = registry_opts(watermarks?: true)
    changed_opts = registry_opts(watermarks?: false)

    capable = Engine.plan(request, Keyword.put(capable_opts, :runtime_cache, cache))
    capable_hit = Engine.plan(request, Keyword.put(capable_opts, :runtime_cache, cache))
    changed = Engine.plan(request, Keyword.put(changed_opts, :runtime_cache, cache))

    assert capable.plan_metadata.cache.plan_cache.status == :miss
    assert capable_hit.plan_metadata.cache.plan_cache.status == :hit
    assert changed.plan_metadata.cache.plan_cache.status == :miss

    assert capable.plan_metadata.cache.dependencies.source_capability_version !=
             changed.plan_metadata.cache.dependencies.source_capability_version

    assert capable.plan_metadata.cache.plan_key.fingerprint !=
             changed.plan_metadata.cache.plan_key.fingerprint
  end

  test "engine plan cache can be disabled per call" do
    cache = start_supervised!({RuntimeCache, name: nil})
    document = load_fixture!("value_tile_latest.v1.json")
    request = resolve_request(document)

    disabled = Engine.plan(request, runtime_cache: cache, plan_cache?: false)
    still_miss = Engine.plan(request, runtime_cache: cache)

    assert disabled.plan_metadata.cache.plan_cache.status == :disabled
    assert still_miss.plan_metadata.cache.plan_cache.status == :miss
  end

  test "invalidating one dashboard leaves other dashboard plans cached" do
    cache = start_supervised!({RuntimeCache, name: nil})
    %Document{} = first = load_fixture!("value_tile_latest.v1.json")
    second = %Document{first | dashboard_id: "dashboard_other_power_latest"}

    first_miss = Engine.plan(resolve_request(first), runtime_cache: cache)
    second_miss = Engine.plan(resolve_request(second), runtime_cache: cache)

    assert first_miss.plan_metadata.cache.plan_cache.status == :miss
    assert second_miss.plan_metadata.cache.plan_cache.status == :miss

    assert {:ok, 1} = RuntimeCache.invalidate_plans(cache, dashboard_id: first.dashboard_id)

    first_after_invalidation = Engine.plan(resolve_request(first), runtime_cache: cache)
    second_after_invalidation = Engine.plan(resolve_request(second), runtime_cache: cache)

    assert first_after_invalidation.plan_metadata.cache.plan_cache.status == :miss
    assert second_after_invalidation.plan_metadata.cache.plan_cache.status == :hit
  end

  test "invalidating a mission clears all cached plans for that mission" do
    cache = start_supervised!({RuntimeCache, name: nil})
    %Document{} = first = load_fixture!("value_tile_latest.v1.json")
    second = %Document{first | dashboard_id: "dashboard_other_power_latest"}

    _first_miss = Engine.plan(resolve_request(first), runtime_cache: cache)
    _second_miss = Engine.plan(resolve_request(second), runtime_cache: cache)

    assert {:ok, 2} = RuntimeCache.invalidate_plans(cache, mission_id: first.mission_id)

    assert Engine.plan(resolve_request(first), runtime_cache: cache).plan_metadata.cache.plan_cache.status ==
             :miss

    assert Engine.plan(resolve_request(second), runtime_cache: cache).plan_metadata.cache.plan_cache.status ==
             :miss
  end

  test "invalidating a logical source clears dependent plans only" do
    cache = start_supervised!({RuntimeCache, name: nil})
    %Document{} = telemetry_document = load_fixture!("value_tile_latest.v1.json")

    empty_document = %Document{
      telemetry_document
      | dashboard_id: "dashboard_empty",
        placements: []
    }

    _telemetry_miss = Engine.plan(resolve_request(telemetry_document), runtime_cache: cache)
    _empty_miss = Engine.plan(resolve_request(empty_document), runtime_cache: cache)

    assert {:ok, 1} = RuntimeCache.invalidate_plans(cache, logical_source: :telemetry)

    assert Engine.plan(resolve_request(telemetry_document), runtime_cache: cache).plan_metadata.cache.plan_cache.status ==
             :miss

    assert Engine.plan(resolve_request(empty_document), runtime_cache: cache).plan_metadata.cache.plan_cache.status ==
             :hit
  end

  test "invalidating a plan observable clears dependent plans only" do
    cache = start_supervised!({RuntimeCache, name: nil})
    %Document{} = battery_document = load_fixture!("value_tile_latest.v1.json")
    thermal_document = %Document{battery_document | dashboard_id: "dashboard_thermal_limits"}
    battery_key = RuntimeCacheKey.plan(resolve_request(battery_document))
    thermal_key = RuntimeCacheKey.plan(resolve_request(thermal_document))

    battery_plan = %DashboardResolveResult{
      dashboard_id: battery_document.dashboard_id,
      planned_source_requests: [source_request(:limits, observables: ["battery_voltage"])],
      plan_metadata: %{cache: %{plan_key: battery_key}}
    }

    thermal_plan = %DashboardResolveResult{
      dashboard_id: thermal_document.dashboard_id,
      planned_source_requests: [source_request(:limits, observables: ["battery_temperature"])],
      plan_metadata: %{cache: %{plan_key: thermal_key}}
    }

    assert :ok = RuntimeCache.put_plan(battery_key, battery_plan, cache)
    assert :ok = RuntimeCache.put_plan(thermal_key, thermal_plan, cache)

    assert {:ok, 1} =
             RuntimeCache.invalidate_plans(cache,
               mission_id: battery_document.mission_id,
               logical_source: :limits,
               observable: "battery_voltage"
             )

    assert RuntimeCache.get_plan(battery_key, cache) == :miss
    assert {:ok, ^thermal_plan} = RuntimeCache.get_plan(thermal_key, cache)
  end

  test "stores and resets source results by runtime cache key" do
    cache = start_supervised!({RuntimeCache, name: nil})
    key = source_result_key(:telemetry)
    result = source_result(:telemetry)

    assert RuntimeCache.get_source_result(key, cache) == :miss
    assert :ok = RuntimeCache.put_source_result(key, result, cache)
    assert {:ok, ^result} = RuntimeCache.get_source_result(key, cache)
    assert :ok = RuntimeCache.reset(cache)
    assert RuntimeCache.get_source_result(key, cache) == :miss
  end

  test "invalidating a source result logical source leaves other sources cached" do
    cache = start_supervised!({RuntimeCache, name: nil})
    telemetry_key = source_result_key(:telemetry)
    limits_key = source_result_key(:limits)
    telemetry_result = source_result(:telemetry)
    limits_result = source_result(:limits)

    assert :ok = RuntimeCache.put_source_result(telemetry_key, telemetry_result, cache)
    assert :ok = RuntimeCache.put_source_result(limits_key, limits_result, cache)

    assert {:ok, 1} = RuntimeCache.invalidate_source_results(cache, logical_source: :telemetry)

    assert RuntimeCache.get_source_result(telemetry_key, cache) == :miss
    assert {:ok, ^limits_result} = RuntimeCache.get_source_result(limits_key, cache)
  end

  test "runtime cache metadata tracks telemetry revision dependencies" do
    cache = start_supervised!({RuntimeCache, name: nil})
    conflict_dependency = telemetry_revision_dependency("identity-1", "conflict")
    resolved_dependency = telemetry_revision_dependency("identity-1", "resolved")

    conflict_source_key = source_result_key(:telemetry, request_id: "source_req_conflict")
    resolved_source_key = source_result_key(:telemetry, request_id: "source_req_resolved")
    conflict_frame_key = frame_key(:telemetry, telemetry_revision_dependency: conflict_dependency)
    resolved_frame_key = frame_key(:telemetry, telemetry_revision_dependency: resolved_dependency)

    conflict_result =
      source_result(:telemetry, telemetry_revision_dependency: conflict_dependency)

    resolved_result =
      source_result(:telemetry, telemetry_revision_dependency: resolved_dependency)

    conflict_frames = frames(:telemetry)
    resolved_frames = frames(:telemetry, frame_id: "frame_resolved")

    assert :ok = RuntimeCache.put_source_result(conflict_source_key, conflict_result, cache)
    assert :ok = RuntimeCache.put_source_result(resolved_source_key, resolved_result, cache)
    assert :ok = RuntimeCache.put_frame(conflict_frame_key, conflict_frames, cache)
    assert :ok = RuntimeCache.put_frame(resolved_frame_key, resolved_frames, cache)

    assert {:ok, 1} =
             RuntimeCache.invalidate_source_results(cache,
               telemetry_revision_dependency: conflict_dependency
             )

    assert {:ok, 1} =
             RuntimeCache.invalidate_frames(cache,
               telemetry_revision_dependency: conflict_dependency
             )

    assert RuntimeCache.get_source_result(conflict_source_key, cache) == :miss
    assert {:ok, ^resolved_result} = RuntimeCache.get_source_result(resolved_source_key, cache)
    assert RuntimeCache.get_frame(conflict_frame_key, cache) == :miss
    assert {:ok, ^resolved_frames} = RuntimeCache.get_frame(resolved_frame_key, cache)
  end

  test "invalidating a data source clears only source results for that source" do
    cache = start_supervised!({RuntimeCache, name: nil})
    flight_key = source_result_key(:telemetry, data_source_id: "flight-questdb")
    rehearsal_key = source_result_key(:telemetry, data_source_id: "rehearsal-questdb")
    flight_result = source_result(:telemetry, data_source_id: "flight-questdb")
    rehearsal_result = source_result(:telemetry, data_source_id: "rehearsal-questdb")

    assert :ok = RuntimeCache.put_source_result(flight_key, flight_result, cache)
    assert :ok = RuntimeCache.put_source_result(rehearsal_key, rehearsal_result, cache)

    assert {:ok, 1} =
             RuntimeCache.invalidate_source_results(cache, data_source_id: "flight-questdb")

    assert RuntimeCache.get_source_result(flight_key, cache) == :miss
    assert {:ok, ^rehearsal_result} = RuntimeCache.get_source_result(rehearsal_key, cache)
  end

  test "invalidating a data source matches segmented source result identities" do
    cache = start_supervised!({RuntimeCache, name: nil})
    segmented_key = segmented_source_result_key()

    other_key =
      segmented_source_result_key(
        request_id: "source_req_telemetry_rehearsal",
        source_binding_segments:
          source_binding_segments(
            source_binding_id: "rehearsal-telemetry-binding",
            first_data_source_id: "rehearsal-questdb-v1",
            second_data_source_id: "rehearsal-questdb-v2",
            first_dataset: "rehearsal-v1",
            second_dataset: "rehearsal-v2",
            realm: :rehearsal
          )
      )

    segmented_result =
      source_result(:telemetry, request_id: segmented_key.parts.request.request_id)

    other_result = source_result(:telemetry, request_id: other_key.parts.request.request_id)

    assert :ok = RuntimeCache.put_source_result(segmented_key, segmented_result, cache)
    assert :ok = RuntimeCache.put_source_result(other_key, other_result, cache)

    assert {:ok, 1} =
             RuntimeCache.invalidate_source_results(cache, data_source_id: "flight-questdb-v2")

    assert RuntimeCache.get_source_result(segmented_key, cache) == :miss
    assert {:ok, ^other_result} = RuntimeCache.get_source_result(other_key, cache)
  end

  test "invalidating a mission clears all source results for that mission" do
    cache = start_supervised!({RuntimeCache, name: nil})
    first_key = source_result_key(:telemetry, mission_id: "mission-one")
    second_key = source_result_key(:limits, mission_id: "mission-one")
    other_key = source_result_key(:telemetry, mission_id: "mission-two")
    first_result = source_result(:telemetry, mission_id: "mission-one")
    second_result = source_result(:limits, mission_id: "mission-one")
    other_result = source_result(:telemetry, mission_id: "mission-two")

    assert :ok = RuntimeCache.put_source_result(first_key, first_result, cache)
    assert :ok = RuntimeCache.put_source_result(second_key, second_result, cache)
    assert :ok = RuntimeCache.put_source_result(other_key, other_result, cache)

    assert {:ok, 2} = RuntimeCache.invalidate_source_results(cache, mission_id: "mission-one")

    assert RuntimeCache.get_source_result(first_key, cache) == :miss
    assert RuntimeCache.get_source_result(second_key, cache) == :miss
    assert {:ok, ^other_result} = RuntimeCache.get_source_result(other_key, cache)
  end

  test "invalidating a watermark cursor clears only matching source results" do
    cache = start_supervised!({RuntimeCache, name: nil})

    old_key =
      source_result_key(:telemetry,
        data_source_id: "flight-questdb",
        complete_through: ~U[2026-06-17 12:00:00Z]
      )

    new_key =
      source_result_key(:telemetry,
        data_source_id: "flight-questdb",
        complete_through: ~U[2026-06-17 12:05:00Z]
      )

    old_result = source_result(:telemetry, complete_through: ~U[2026-06-17 12:00:00Z])
    new_result = source_result(:telemetry, complete_through: ~U[2026-06-17 12:05:00Z])

    assert :ok = RuntimeCache.put_source_result(old_key, old_result, cache)
    assert :ok = RuntimeCache.put_source_result(new_key, new_result, cache)

    assert {:ok, 1} =
             RuntimeCache.invalidate_source_results(cache,
               watermark_cursor: old_key.parts.watermark_cursor
             )

    assert RuntimeCache.get_source_result(old_key, cache) == :miss
    assert {:ok, ^new_result} = RuntimeCache.get_source_result(new_key, cache)
  end

  test "invalidating a replay run clears only matching source results and frames" do
    cache = start_supervised!({RuntimeCache, name: nil})
    first_context = replay_time_context("replay-run-1")
    second_context = replay_time_context("replay-run-2")

    first_source_key =
      source_result_key(:telemetry,
        cache_policy: :snapshot,
        time_context: first_context
      )

    second_source_key =
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

    first_result =
      source_result(:telemetry, request_id: first_source_key.parts.request.request_id)

    second_result =
      source_result(:telemetry, request_id: second_source_key.parts.request.request_id)

    first_frames = frames(:telemetry, frame_id: "frame-replay-1")
    second_frames = frames(:telemetry, frame_id: "frame-replay-2")

    assert :ok = RuntimeCache.put_source_result(first_source_key, first_result, cache)
    assert :ok = RuntimeCache.put_source_result(second_source_key, second_result, cache)
    assert :ok = RuntimeCache.put_frame(first_frame_key, first_frames, cache)
    assert :ok = RuntimeCache.put_frame(second_frame_key, second_frames, cache)

    assert {:ok, 1} = RuntimeCache.invalidate_source_results(cache, replay_run_id: "replay-run-1")
    assert {:ok, 1} = RuntimeCache.invalidate_frames(cache, replay_run_id: "replay-run-1")

    assert RuntimeCache.get_source_result(first_source_key, cache) == :miss
    assert {:ok, ^second_result} = RuntimeCache.get_source_result(second_source_key, cache)
    assert RuntimeCache.get_frame(first_frame_key, cache) == :miss
    assert {:ok, ^second_frames} = RuntimeCache.get_frame(second_frame_key, cache)
  end

  test "stores and resets frame results by runtime cache key" do
    cache = start_supervised!({RuntimeCache, name: nil})
    key = frame_key(:telemetry)
    frames = frames(:telemetry)

    assert RuntimeCache.get_frame(key, cache) == :miss
    assert :ok = RuntimeCache.put_frame(key, frames, cache)
    assert {:ok, ^frames} = RuntimeCache.get_frame(key, cache)
    assert :ok = RuntimeCache.reset(cache)
    assert RuntimeCache.get_frame(key, cache) == :miss
  end

  test "invalidating source result fingerprint clears dependent frames only" do
    cache = start_supervised!({RuntimeCache, name: nil})
    first_key = frame_key(:telemetry, request_id: "source_req_first")
    second_key = frame_key(:telemetry, request_id: "source_req_second")
    first_frames = frames(:telemetry, frame_id: "frame-first")
    second_frames = frames(:telemetry, frame_id: "frame-second")

    assert :ok = RuntimeCache.put_frame(first_key, first_frames, cache)
    assert :ok = RuntimeCache.put_frame(second_key, second_frames, cache)

    assert {:ok, 1} =
             RuntimeCache.invalidate_frames(cache,
               source_result_fingerprint: first_key.parts.source_result_fingerprint
             )

    assert RuntimeCache.get_frame(first_key, cache) == :miss
    assert {:ok, ^second_frames} = RuntimeCache.get_frame(second_key, cache)
  end

  test "invalidating a placement clears only frames for that placement" do
    cache = start_supervised!({RuntimeCache, name: nil})
    first_key = frame_key(:telemetry, placement_id: "placement_power")
    second_key = frame_key(:telemetry, placement_id: "placement_thermal")
    first_frames = frames(:telemetry, frame_id: "frame-power")
    second_frames = frames(:telemetry, frame_id: "frame-thermal")

    assert :ok = RuntimeCache.put_frame(first_key, first_frames, cache)
    assert :ok = RuntimeCache.put_frame(second_key, second_frames, cache)

    assert {:ok, 1} = RuntimeCache.invalidate_frames(cache, placement_id: "placement_power")

    assert RuntimeCache.get_frame(first_key, cache) == :miss
    assert {:ok, ^second_frames} = RuntimeCache.get_frame(second_key, cache)
  end

  test "invalidating placement size clears only matching frame viewport bucket" do
    cache = start_supervised!({RuntimeCache, name: nil})
    narrow_key = frame_key(:telemetry, placement_size: %{width_px: 320, height_px: 120})
    wide_key = frame_key(:telemetry, placement_size: %{width_px: 960, height_px: 240})
    narrow_frames = frames(:telemetry, frame_id: "frame-narrow")
    wide_frames = frames(:telemetry, frame_id: "frame-wide")

    assert :ok = RuntimeCache.put_frame(narrow_key, narrow_frames, cache)
    assert :ok = RuntimeCache.put_frame(wide_key, wide_frames, cache)

    assert {:ok, 1} =
             RuntimeCache.invalidate_frames(cache,
               placement_size: %{width_px: 320, height_px: 120}
             )

    assert RuntimeCache.get_frame(narrow_key, cache) == :miss
    assert {:ok, ^wide_frames} = RuntimeCache.get_frame(wide_key, cache)
  end

  test "invalidating a logical source clears dependent frames only" do
    cache = start_supervised!({RuntimeCache, name: nil})
    telemetry_key = frame_key(:telemetry)
    limits_key = frame_key(:limits)
    telemetry_frames = frames(:telemetry)
    limits_frames = frames(:limits)

    assert :ok = RuntimeCache.put_frame(telemetry_key, telemetry_frames, cache)
    assert :ok = RuntimeCache.put_frame(limits_key, limits_frames, cache)

    assert {:ok, 1} = RuntimeCache.invalidate_frames(cache, logical_source: :telemetry)

    assert RuntimeCache.get_frame(telemetry_key, cache) == :miss
    assert {:ok, ^limits_frames} = RuntimeCache.get_frame(limits_key, cache)
  end

  test "invalidating a source binding matches segmented frame identities" do
    cache = start_supervised!({RuntimeCache, name: nil})
    segmented_key = segmented_frame_key()

    other_key =
      segmented_frame_key(
        request_id: "source_req_telemetry_rehearsal",
        placement_id: "placement_rehearsal",
        source_binding_segments:
          source_binding_segments(
            source_binding_id: "rehearsal-telemetry-binding",
            first_data_source_id: "rehearsal-questdb-v1",
            second_data_source_id: "rehearsal-questdb-v2",
            first_dataset: "rehearsal-v1",
            second_dataset: "rehearsal-v2",
            realm: :rehearsal
          )
      )

    segmented_frames = frames(:telemetry, frame_id: "frame-segmented")
    other_frames = frames(:telemetry, frame_id: "frame-segmented-rehearsal")

    assert :ok = RuntimeCache.put_frame(segmented_key, segmented_frames, cache)
    assert :ok = RuntimeCache.put_frame(other_key, other_frames, cache)

    assert {:ok, 1} =
             RuntimeCache.invalidate_frames(cache, source_binding_id: "flight-telemetry-binding")

    assert RuntimeCache.get_frame(segmented_key, cache) == :miss
    assert {:ok, ^other_frames} = RuntimeCache.get_frame(other_key, cache)
  end

  test "invalidating a frame cache policy clears only matching frames" do
    cache = start_supervised!({RuntimeCache, name: nil})
    live_key = frame_key(:telemetry, cache_policy: :live)
    snapshot_key = frame_key(:telemetry, cache_policy: :snapshot)
    live_frames = frames(:telemetry, frame_id: "frame-live")
    snapshot_frames = frames(:telemetry, frame_id: "frame-snapshot")

    assert live_key.parts.cache_policy == :live
    assert snapshot_key.parts.cache_policy == :snapshot

    assert :ok = RuntimeCache.put_frame(live_key, live_frames, cache)
    assert :ok = RuntimeCache.put_frame(snapshot_key, snapshot_frames, cache)

    assert {:ok, 1} = RuntimeCache.invalidate_frames(cache, cache_policy: :snapshot)

    assert {:ok, ^live_frames} = RuntimeCache.get_frame(live_key, cache)
    assert RuntimeCache.get_frame(snapshot_key, cache) == :miss
  end

  test "invalidating limit context and catalog revision clears matching frames" do
    cache = start_supervised!({RuntimeCache, name: nil})

    observed_key =
      frame_key(:limits,
        limit_context: %{semantics_mode: "observed"},
        catalog_revision: "catalog:v1"
      )

    current_key =
      frame_key(:limits,
        limit_context: %{semantics_mode: "current"},
        catalog_revision: "catalog:v2"
      )

    observed_frames = frames(:limits, frame_id: "frame-observed")
    current_frames = frames(:limits, frame_id: "frame-current")

    assert :ok = RuntimeCache.put_frame(observed_key, observed_frames, cache)
    assert :ok = RuntimeCache.put_frame(current_key, current_frames, cache)

    assert {:ok, 1} =
             RuntimeCache.invalidate_frames(cache,
               limit_context: %{semantics_mode: "observed"},
               catalog_revision: "catalog:v1"
             )

    assert RuntimeCache.get_frame(observed_key, cache) == :miss
    assert {:ok, ^current_frames} = RuntimeCache.get_frame(current_key, cache)
  end

  defp resolve_request(%Document{} = document, opts \\ []) do
    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context:
        Keyword.get(opts, :scope_context, %{
          primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}
        }),
      data_context: Keyword.get(opts, :data_context, %{}),
      interaction_context: %{
        placement_sizes: %{"placement_battery_voltage" => %{width_px: 320, height_px: 128}}
      }
    }
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> Dashboards.load_document!()
  end

  defp registry_opts(telemetry_capabilities) do
    telemetry_capabilities = Map.new(telemetry_capabilities)

    telemetry_source = %DataSource{
      data_source_id: "flight-questdb",
      adapter: Cadence.Dashboards.Sources.Telemetry,
      capabilities:
        Map.merge(%{latest?: true, range_scan?: true, watermarks?: true}, telemetry_capabilities)
    }

    limits_source = %DataSource{
      data_source_id: "managed_limits_projection",
      adapter: Cadence.Dashboards.Sources.Limits,
      kind: :projection,
      capabilities: %{latest_state?: true, event_history?: true, watermarks?: true}
    }

    [
      data_sources: [telemetry_source, limits_source],
      data_bindings: [
        source_binding(:telemetry, :flight, "flight-questdb", []),
        source_binding(:limits, :flight, "managed_limits_projection", [])
      ]
    ]
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
      data_context: Keyword.get(opts, :data_context, %{}),
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
