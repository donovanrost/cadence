defmodule Cadence.Dashboards.RuntimeCacheKeyTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Document,
    Engine,
    PlannedSourceRequest,
    RuntimeCacheKey
  }

  alias Cadence.DataSources.SourceWatermark

  alias Cadence.DataSources.{DataBinding, DataSource}

  @fixture_dir Path.expand("../../fixtures/dashboards", __DIR__)

  test "plan key changes when dashboard document identity changes" do
    %Document{} = document = load_fixture!("value_tile_latest.v1.json")
    renamed = %Document{document | name: "Renamed Power Latest"}

    key = RuntimeCacheKey.plan(resolve_request(document), document_version: 1)
    renamed_key = RuntimeCacheKey.plan(resolve_request(renamed), document_version: 2)

    assert key.layer == :plan
    assert key.parts.document.document_version == 1
    assert renamed_key.parts.document.document_version == 2
    assert key.fingerprint != renamed_key.fingerprint
  end

  test "plan key changes when source capability version changes" do
    document = load_fixture!("value_tile_latest.v1.json")
    request = resolve_request(document)

    old_key = RuntimeCacheKey.plan(request, source_capability_version: "sources:v1")
    new_key = RuntimeCacheKey.plan(request, source_capability_version: "sources:v2")

    assert old_key.fingerprint != new_key.fingerprint
  end

  test "plan key changes when source registry overrides change" do
    document = load_fixture!("value_tile_latest.v1.json")
    request = resolve_request(document)

    default_key =
      RuntimeCacheKey.plan(request,
        data_sources: [telemetry_source("flight-questdb")],
        data_bindings: [telemetry_binding("flight-binding", :flight, "flight-questdb")]
      )

    rehearsal_key =
      RuntimeCacheKey.plan(request,
        data_sources: [telemetry_source("rehearsal-questdb")],
        data_bindings: [telemetry_binding("rehearsal-binding", :rehearsal, "rehearsal-questdb")]
      )

    assert default_key.parts.source_registry_overrides.data_sources !=
             rehearsal_key.parts.source_registry_overrides.data_sources

    assert default_key.fingerprint != rehearsal_key.fingerprint
  end

  test "source result key changes when realm source binding changes" do
    source_request = planned_telemetry_request()
    flight_source = telemetry_source("flight-questdb")
    rehearsal_source = telemetry_source("rehearsal-questdb")

    flight_key =
      RuntimeCacheKey.source_result(source_request,
        source_binding: telemetry_binding("flight-binding", :flight, "flight-questdb"),
        data_source: flight_source
      )

    rehearsal_key =
      RuntimeCacheKey.source_result(source_request,
        source_binding: telemetry_binding("rehearsal-binding", :rehearsal, "rehearsal-questdb"),
        data_source: rehearsal_source
      )

    assert flight_key.layer == :source_result
    assert flight_key.parts.source_binding.realm == :flight
    assert rehearsal_key.parts.source_binding.realm == :rehearsal
    assert flight_key.fingerprint != rehearsal_key.fingerprint
  end

  test "source result key changes when data-management view changes" do
    canonical_request = planned_telemetry_request()

    all_revisions_request = %{
      canonical_request
      | data_context: %{canonical_request.data_context | view: :all_revisions}
    }

    canonical_key =
      RuntimeCacheKey.source_result(canonical_request,
        source_binding: telemetry_binding("flight-binding", :flight, "flight-questdb"),
        data_source: telemetry_source("flight-questdb")
      )

    all_revisions_key =
      RuntimeCacheKey.source_result(all_revisions_request,
        source_binding: telemetry_binding("flight-binding", :flight, "flight-questdb"),
        data_source: telemetry_source("flight-questdb")
      )

    assert canonical_key.parts.request.data_context.view in [nil, "canonical", :canonical]
    assert all_revisions_key.parts.request.data_context.view == :all_revisions
    assert canonical_key.fingerprint != all_revisions_key.fingerprint
  end

  test "source result key carries planned cross-source dependencies" do
    %PlannedSourceRequest{} = telemetry_request = planned_telemetry_request()

    request = %PlannedSourceRequest{
      telemetry_request
      | logical_source: :limits,
        request_id: "source_req_limits",
        sampling: %{mode: :latest_state, products: [:latest_state]},
        source_dependencies: []
    }

    dependent_request = %PlannedSourceRequest{
      request
      | source_dependencies: [
          %{
            logical_source: :telemetry,
            reason: :limit_latest_sample_input,
            products: [:latest_sample],
            sampling: %{mode: :latest}
          }
        ]
    }

    independent_key =
      RuntimeCacheKey.source_result(request,
        source_binding: limits_binding(),
        data_source: limits_source()
      )

    dependent_key =
      RuntimeCacheKey.source_result(dependent_request,
        source_binding: limits_binding(),
        data_source: limits_source()
      )

    assert independent_key.parts.request.source_dependencies == []

    assert [
             %{
               logical_source: :telemetry,
               reason: :limit_latest_sample_input,
               products: [:latest_sample]
             }
           ] = dependent_key.parts.request.source_dependencies

    assert independent_key.fingerprint != dependent_key.fingerprint
  end

  test "source and frame keys carry the full semantic runtime context" do
    %PlannedSourceRequest{} = base_request = planned_telemetry_request()

    source_request =
      %PlannedSourceRequest{
        base_request
        | time_context: %{
            mode: :replay_run,
            axis: :receipt_time,
            replay_run_id: "replay-run-1"
          },
          data_context: %{
            realm: :replay,
            data_source_id: "questdb-replay",
            source_binding_id: "binding-replay",
            view: :all_revisions
          },
          limit_context: %{semantics_mode: :as_recorded}
      }

    source_binding = telemetry_binding("binding-replay", :replay, "questdb-replay")
    data_source = telemetry_source("questdb-replay")
    source_binding_segments = [source_binding_segment("binding-event-1", :replay)]

    key =
      RuntimeCacheKey.source_result(source_request,
        cache_policy: :live,
        source_binding: source_binding,
        source_binding_segments: source_binding_segments,
        data_source: data_source,
        freshness_policy: %{stale_after_ms: 5_000},
        watermark:
          watermark(~U[2026-06-17 12:05:00Z],
            source_binding_id: "binding-replay",
            data_source_id: "questdb-replay",
            realm: :replay,
            replay_run_id: "replay-run-1",
            dataset: "replay",
            request_id: source_request.request_id
          ),
        data_revision: "telemetry-replay-rev-1",
        correction_cursor: "correction-cursor-1",
        backfill_cursor: "backfill-cursor-1"
      )

    assert key.parts.cache_policy == :live
    assert key.parts.request.time_context.replay_run_id == "replay-run-1"
    assert key.parts.request.data_context.realm == :replay
    assert key.parts.request.data_context.data_source_id == "questdb-replay"
    assert key.parts.request.data_context.source_binding_id == "binding-replay"
    assert key.parts.request.data_context.view == :all_revisions
    assert key.parts.request.limit_context.semantics_mode == :as_recorded
    assert key.parts.source_binding.binding_id == "binding-replay"
    assert key.parts.source_binding.realm == :replay
    assert key.parts.source_binding.data_source_id == "questdb-replay"
    assert key.parts.data_source.data_source_id == "questdb-replay"
    assert key.parts.source_binding_segments == source_binding_segments
    assert key.parts.watermark_cursor.replay_run_id == "replay-run-1"
    assert key.parts.data_revision == "telemetry-replay-rev-1"
    assert key.parts.correction_cursor == "correction-cursor-1"
    assert key.parts.backfill_cursor == "backfill-cursor-1"

    key_for = fn request, opts ->
      RuntimeCacheKey.source_result(
        request,
        Keyword.merge(
          [
            cache_policy: :live,
            source_binding: source_binding,
            source_binding_segments: source_binding_segments,
            data_source: data_source,
            freshness_policy: %{stale_after_ms: 5_000},
            watermark:
              watermark(~U[2026-06-17 12:05:00Z],
                source_binding_id: "binding-replay",
                data_source_id: "questdb-replay",
                realm: :replay,
                replay_run_id: request.time_context.replay_run_id,
                dataset: "replay",
                request_id: request.request_id
              ),
            data_revision: "telemetry-replay-rev-1",
            correction_cursor: "correction-cursor-1",
            backfill_cursor: "backfill-cursor-1"
          ],
          opts
        )
      )
    end

    replay_changed =
      key_for.(
        %PlannedSourceRequest{
          source_request
          | time_context: Map.put(source_request.time_context, :replay_run_id, "replay-run-2")
        },
        []
      )

    view_changed =
      key_for.(
        %PlannedSourceRequest{
          source_request
          | data_context: Map.put(source_request.data_context, :view, :canonical)
        },
        []
      )

    limit_changed =
      key_for.(
        %PlannedSourceRequest{
          source_request
          | limit_context: Map.put(source_request.limit_context, :semantics_mode, :current)
        },
        []
      )

    binding_changed =
      key_for.(source_request,
        source_binding: telemetry_binding("binding-replay-v2", :replay, "questdb-replay")
      )

    data_source_changed =
      key_for.(source_request,
        data_source: telemetry_source("questdb-replay-v2"),
        watermark:
          watermark(~U[2026-06-17 12:05:00Z],
            source_binding_id: "binding-replay",
            data_source_id: "questdb-replay-v2",
            realm: :replay,
            replay_run_id: "replay-run-1",
            dataset: "replay",
            request_id: source_request.request_id
          )
      )

    segment_changed =
      key_for.(source_request,
        source_binding_segments: [source_binding_segment("binding-event-2", :replay)]
      )

    assert replay_changed.fingerprint != key.fingerprint
    assert view_changed.fingerprint != key.fingerprint
    assert limit_changed.fingerprint != key.fingerprint
    assert binding_changed.fingerprint != key.fingerprint
    assert data_source_changed.fingerprint != key.fingerprint
    assert segment_changed.fingerprint != key.fingerprint

    frame_key =
      RuntimeCacheKey.frame(key,
        placement_id: "placement_power_trend",
        placement_size: %{width_px: 640, height_px: 240},
        display: %{density: :compact},
        frame_shape: :time_series,
        limit_context: source_request.limit_context,
        catalog_revision: "catalog:v1",
        telemetry_revision_dependency: %{
          observation_identity_id: "identity-1",
          fingerprint: "observation-fingerprint-1"
        }
      )

    assert frame_key.parts.source_result_fingerprint == key.fingerprint
    assert frame_key.parts.source_result_request.data_context.realm == :replay
    assert frame_key.parts.source_result_binding.binding_id == "binding-replay"
    assert frame_key.parts.source_result_data_source.data_source_id == "questdb-replay"
    assert frame_key.parts.source_result_binding_segments == source_binding_segments
    assert frame_key.parts.limit_context.semantics_mode == :as_recorded
    assert frame_key.parts.catalog_revision == "catalog:v1"

    assert frame_key.parts.telemetry_revision_dependency.fingerprint ==
             "observation-fingerprint-1"

    frame_limit_changed =
      RuntimeCacheKey.frame(key,
        placement_id: "placement_power_trend",
        placement_size: %{width_px: 640, height_px: 240},
        display: %{density: :compact},
        frame_shape: :time_series,
        limit_context: %{semantics_mode: :current},
        catalog_revision: "catalog:v1",
        telemetry_revision_dependency: %{
          observation_identity_id: "identity-1",
          fingerprint: "observation-fingerprint-1"
        }
      )

    assert frame_limit_changed.fingerprint != frame_key.fingerprint
  end

  test "limit semantics modes are isolated in source-result and frame cache keys" do
    %PlannedSourceRequest{} = base_request = planned_telemetry_request()
    source_binding = telemetry_binding("flight-binding", :flight, "flight-questdb")
    data_source = telemetry_source("flight-questdb")

    cache_keys =
      for semantics_mode <- [:observed, :current, :recomputed, :compare] do
        request = %PlannedSourceRequest{
          base_request
          | limit_context: %{semantics_mode: semantics_mode}
        }

        source_key =
          RuntimeCacheKey.source_result(request,
            source_binding: source_binding,
            data_source: data_source,
            watermark: watermark(~U[2026-06-17 12:00:00Z])
          )

        frame_key =
          RuntimeCacheKey.frame(source_key,
            placement_id: "placement_power_trend",
            placement_size: %{width_px: 640, height_px: 240},
            frame_shape: :time_series,
            limit_context: request.limit_context
          )

        {semantics_mode, source_key, frame_key}
      end

    assert Enum.map(cache_keys, fn {mode, source_key, _frame_key} ->
             {mode, source_key.parts.request.limit_context.semantics_mode}
           end) == [
             observed: :observed,
             current: :current,
             recomputed: :recomputed,
             compare: :compare
           ]

    source_fingerprints =
      Enum.map(cache_keys, fn {_mode, source_key, _frame_key} ->
        source_key.fingerprint
      end)

    frame_fingerprints =
      Enum.map(cache_keys, fn {_mode, _source_key, frame_key} ->
        frame_key.fingerprint
      end)

    assert MapSet.size(MapSet.new(source_fingerprints)) == 4
    assert MapSet.size(MapSet.new(frame_fingerprints)) == 4
  end

  test "source result key changes when freshness policy changes" do
    source_request = planned_telemetry_request()

    strict_key =
      RuntimeCacheKey.source_result(source_request,
        source_binding: telemetry_binding("flight-binding", :flight, "flight-questdb"),
        data_source: telemetry_source("flight-questdb"),
        freshness_policy: %{stale_after_ms: 5_000}
      )

    relaxed_key =
      RuntimeCacheKey.source_result(source_request,
        source_binding: telemetry_binding("flight-binding", :flight, "flight-questdb"),
        data_source: telemetry_source("flight-questdb"),
        freshness_policy: %{stale_after_ms: 30_000}
      )

    assert strict_key.parts.freshness_policy == %{stale_after_ms: 5_000}
    assert relaxed_key.parts.freshness_policy == %{stale_after_ms: 30_000}
    assert strict_key.fingerprint != relaxed_key.fingerprint
  end

  test "source result key changes when watermark cursor moves" do
    source_request = planned_telemetry_request()

    old_key =
      RuntimeCacheKey.source_result(source_request,
        source_binding: telemetry_binding("flight-binding", :flight, "flight-questdb"),
        data_source: telemetry_source("flight-questdb"),
        watermark: watermark(~U[2026-06-17 12:00:00Z])
      )

    new_key =
      RuntimeCacheKey.source_result(source_request,
        source_binding: telemetry_binding("flight-binding", :flight, "flight-questdb"),
        data_source: telemetry_source("flight-questdb"),
        watermark: watermark(~U[2026-06-17 12:05:00Z])
      )

    assert old_key.parts.watermark_cursor.complete_through == ~U[2026-06-17 12:00:00Z]
    assert new_key.parts.watermark_cursor.complete_through == ~U[2026-06-17 12:05:00Z]
    assert old_key.fingerprint != new_key.fingerprint
  end

  test "snapshot source result key ignores live freshness artifacts" do
    source_request =
      planned_telemetry_request()
      |> Map.put(:time_context, %{
        mode: :archive,
        axis: :receipt_time,
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:05:00Z]
      })

    old_key =
      RuntimeCacheKey.source_result(source_request,
        cache_policy: :snapshot,
        source_binding: telemetry_binding("flight-binding", :flight, "flight-questdb"),
        data_source: telemetry_source("flight-questdb"),
        freshness_policy: %{stale_after_ms: 5_000},
        watermark: watermark(~U[2026-06-17 12:00:00Z])
      )

    new_key =
      RuntimeCacheKey.source_result(source_request,
        cache_policy: :snapshot,
        source_binding: telemetry_binding("flight-binding", :flight, "flight-questdb"),
        data_source: telemetry_source("flight-questdb"),
        freshness_policy: %{stale_after_ms: 30_000},
        watermark: watermark(~U[2026-06-17 12:05:00Z])
      )

    assert old_key.parts.cache_policy == :snapshot
    refute Map.has_key?(old_key.parts, :freshness_policy)
    refute Map.has_key?(old_key.parts, :watermark_cursor)
    assert old_key.fingerprint == new_key.fingerprint
  end

  test "frame key changes when placement display size changes" do
    source_key =
      planned_telemetry_request()
      |> RuntimeCacheKey.source_result(
        source_binding: telemetry_binding("flight-binding", :flight, "flight-questdb"),
        data_source: telemetry_source("flight-questdb"),
        watermark: watermark(~U[2026-06-17 12:00:00Z])
      )

    narrow_key =
      RuntimeCacheKey.frame(source_key,
        placement_id: "placement_power_trend",
        placement_size: %{width_px: 320, height_px: 240},
        frame_shape: :wide
      )

    wide_key =
      RuntimeCacheKey.frame(source_key,
        placement_id: "placement_power_trend",
        placement_size: %{width_px: 960, height_px: 240},
        frame_shape: :wide
      )

    assert narrow_key.layer == :frame
    assert narrow_key.parts.source_result_fingerprint == source_key.fingerprint
    assert narrow_key.parts.placement_size.width_px == 320
    assert wide_key.parts.placement_size.width_px == 960
    assert narrow_key.fingerprint != wide_key.fingerprint
  end

  test "frame key carries source result cache policy" do
    source_request =
      planned_telemetry_request()
      |> Map.put(:time_context, %{
        mode: :archive,
        axis: :receipt_time,
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:05:00Z]
      })

    source_key =
      RuntimeCacheKey.source_result(source_request,
        cache_policy: :snapshot,
        source_binding: telemetry_binding("flight-binding", :flight, "flight-questdb"),
        data_source: telemetry_source("flight-questdb"),
        watermark: watermark(~U[2026-06-17 12:00:00Z])
      )

    frame_key =
      RuntimeCacheKey.frame(source_key,
        placement_id: "placement_power_trend",
        placement_size: %{width_px: 320, height_px: 240},
        frame_shape: :wide
      )

    assert frame_key.layer == :frame
    assert frame_key.parts.cache_policy == :snapshot
    assert frame_key.parts.source_result_fingerprint == source_key.fingerprint
  end

  defp planned_telemetry_request do
    document = load_fixture!("value_tile_latest.v1.json")

    document
    |> resolve_request()
    |> Engine.plan()
    |> then(fn result ->
      Enum.find(result.planned_source_requests, &(&1.logical_source == :telemetry))
    end)
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

  defp telemetry_binding(binding_id, realm, data_source_id) do
    %DataBinding{
      binding_id: binding_id,
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      realm: realm,
      logical_source: :telemetry,
      data_source_id: data_source_id,
      dataset: Atom.to_string(realm)
    }
  end

  defp telemetry_source(data_source_id) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      capabilities: %{latest?: true, range_scan?: true, watermarks?: true}
    }
  end

  defp limits_binding do
    %DataBinding{
      binding_id: "flight-limits",
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      realm: :flight,
      logical_source: :limits,
      data_source_id: "managed_limits_projection",
      dataset: "telemetry_latest_limit_states"
    }
  end

  defp limits_source do
    %DataSource{
      data_source_id: "managed_limits_projection",
      adapter: Cadence.Dashboards.Sources.Limits,
      capabilities: %{latest_state?: true}
    }
  end

  defp source_binding_segment(event_id, realm) do
    %{
      data_binding_event_id: event_id,
      source_binding_id: "binding-#{realm}",
      source_binding_version: 1,
      data_source_id: "questdb-#{realm}",
      realm: realm,
      dataset: Atom.to_string(realm),
      started_at: ~U[2026-06-17 12:00:00Z],
      ended_at: nil
    }
  end

  defp watermark(complete_through, overrides \\ []) do
    attrs =
      %{
        logical_source: :telemetry,
        request_id: "source_req_telemetry",
        source_binding_id: "flight-binding",
        data_source_id: "flight-questdb",
        realm: :flight,
        replay_run_id: nil,
        dataset: "flight",
        complete_through: complete_through,
        latest_receipt_time: complete_through,
        retention_starts_at: ~U[2026-06-17 11:00:00Z],
        confidence: :best_effort,
        freshness_state: :fresh
      }
      |> Map.merge(Map.new(overrides))

    struct!(SourceWatermark, attrs)
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> Dashboards.load_document!()
  end
end
