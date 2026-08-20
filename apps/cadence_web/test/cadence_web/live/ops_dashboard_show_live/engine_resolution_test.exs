defmodule CadenceWeb.OpsDashboardShowLive.EngineResolutionTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    Document,
    Field,
    Frame,
    PlacementFrames,
    RenderWidget,
    ResolutionContext,
    ResolveWarning,
    RuntimeCache,
    RuntimeComposition
  }

  alias CadenceWeb.OpsDashboardShowLive.DataViewComparison
  alias CadenceWeb.OpsDashboardShowLive.EngineResolution
  alias CadenceWeb.OpsDashboardShowLive.RuntimeDataRequest

  test "request builds the dashboard runtime data request boundary" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_document: %Document{dashboard_id: "dashboard-1"},
        dashboard_document_mode: :published,
        dashboard_scope_context: %{"primary" => %{"kind" => "mission", "ids" => ["mission-1"]}},
        dashboard_time_context: %{"mode" => "live"},
        dashboard_data_context: %{"realm" => "flight"},
        dashboard_limit_context: %{"semantics_mode" => "observed"}
      }
    }

    assert %RuntimeDataRequest{
             organization_id: "org-1",
             mission_id: "mission-1",
             dashboard_id: "dashboard-1",
             document_mode: :published,
             resolve_mode: :live_tick,
             scope_context: %{"primary" => %{"kind" => "mission", "ids" => ["mission-1"]}},
             time_context: %{"mode" => "live"},
             data_context: %{"realm" => "flight"},
             limit_context: %{"semantics_mode" => "observed"}
           } = EngineResolution.request(socket, :live_tick)
  end

  test "comparison_request builds a secondary request for a different data view" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_document: %Document{dashboard_id: "dashboard-1"},
        dashboard_document_mode: :published,
        dashboard_scope_context: %{"primary" => %{"kind" => "mission", "ids" => ["mission-1"]}},
        dashboard_time_context: %{"mode" => "archive"},
        dashboard_data_context: %{"realm" => "flight", "view" => "all_revisions"},
        dashboard_data_view: "all_revisions",
        dashboard_compare_data_view: "canonical",
        dashboard_limit_context: %{"semantics_mode" => "observed"}
      }
    }

    assert %RuntimeDataRequest{
             data_context: %{"realm" => "flight", "view" => "canonical"},
             resolve_mode: :context_change
           } = EngineResolution.comparison_request(socket, :context_change)
  end

  test "builds one explicit resolution context for the mounted runtime" do
    composition =
      RuntimeComposition.new!(
        runtime_cache: RuntimeCache.client(:runtime_cache, call_timeout_ms: 375),
        source_result_cache?: false,
        frame_cache?: true,
        source_health_events?: false,
        record_source_health_events?: false,
        source_watermark_events?: false
      )

    context =
      EngineResolution.build_resolution_context(
        composition,
        source_execution_timeout_ms: 2_500
      )

    assert %ResolutionContext{
             persisted?: true,
             validate_dashboard_contract?: true,
             persist_limit_selected_clock_audit_events?: true,
             runtime_cache: %RuntimeCache{
               server: :runtime_cache,
               call_timeout_ms: 375
             },
             plan_cache?: true,
             source_result_cache?: false,
             frame_cache?: true
           } = context

    assert context.source_execution_opts[:source_execution_timeout_ms] == 2_500
    assert context.source_execution_opts[:source_health_events?]
    refute context.source_execution_opts[:record_source_health_events?]
    assert context.source_execution_opts[:source_watermark_events?]

    assert is_function(
             get_in(context.source_execution_opts, [
               :source_opts,
               :telemetry,
               :backfill_lifecycle_events_fun
             ]),
             2
           )
  end

  test "disables every cache layer when no runtime cache owner exists" do
    context =
      EngineResolution.build_resolution_context(
        RuntimeComposition.new!(),
        source_execution_timeout_ms: :infinity
      )

    assert %ResolutionContext{
             runtime_cache: false,
             plan_cache?: false,
             source_result_cache?: false,
             frame_cache?: false
           } = context
  end

  test "apply_result attaches comparison results from runtime bundles" do
    primary_result = %{
      resolve_mode: :context_change,
      frames_by_placement: %{"primary-placement" => %PlacementFrames{}}
    }

    comparison_result = %{
      resolve_mode: :context_change,
      frames_by_placement: %{"comparison-placement" => %PlacementFrames{}}
    }

    socket =
      %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          dashboard_render_items: [],
          widget_data: %{}
        }
      }
      |> EngineResolution.apply_result(DataViewComparison.new(primary_result, comparison_result))

    assert socket.assigns.dashboard_engine_result == primary_result

    assert socket.assigns.dashboard_engine_frames_by_placement ==
             primary_result.frames_by_placement

    assert socket.assigns.dashboard_compare_engine_result == comparison_result

    assert socket.assigns.dashboard_compare_engine_frames_by_placement ==
             comparison_result.frames_by_placement
  end

  test "live ticks present merged primary data when an optional overlay request fails" do
    placement_id = "placement-power"

    telemetry_frame = %Frame{
      source: :telemetry,
      shape: :scalar,
      scope: %{primary: %{ids: ["spacecraft-alpha"]}},
      fields: [
        %Field{name: "time", kind: :time, values: [~U[2026-08-01 23:40:00Z]]},
        %Field{name: "HK.voltage", kind: :number, values: [28.4]}
      ],
      meta: %{
        observable_id: "HK.voltage",
        warning_codes: [],
        source_request_context: %{logical_source: :telemetry}
      }
    }

    previous_frames = %{
      placement_id => %PlacementFrames{primary: [telemetry_frame]}
    }

    limits_warning = %ResolveWarning{
      code: :source_unavailable,
      severity: :error,
      message: "Limits source unavailable",
      details: %{logical_source: :limits, source_request_id: "source-req-limits"}
    }

    result = %{
      resolve_mode: :live_tick,
      frames_by_placement: %{
        placement_id => %PlacementFrames{warnings: [limits_warning]}
      }
    }

    socket =
      %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          dashboard_engine_frames_by_placement: previous_frames,
          dashboard_render_items: [
            %{
              placement_id: placement_id,
              widget: %RenderWidget{type: :value_tile, binding: %{mode: :fixed}}
            }
          ],
          widget_data: %{}
        }
      }
      |> EngineResolution.apply_result(result)

    assert %PlacementFrames{
             primary: [^telemetry_frame],
             warnings: [^limits_warning]
           } = socket.assigns.dashboard_engine_frames_by_placement[placement_id]

    assert %{
             lifecycle_state: :ready,
             lifecycle: %{state: :ready, warning_codes: []},
             source_status: %{state: :fresh, warning_codes: []},
             sample: %{engineering_value: 28.4}
           } = socket.assigns.widget_data[placement_id]
  end

  test "refresh_ms uses positive dashboard document refresh defaults" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        dashboard_document: %Document{defaults: %{"time" => %{"refresh_ms" => 2_500}}}
      }
    }

    assert EngineResolution.refresh_ms(socket, 1_000) == 2_500
  end

  test "refresh_ms falls back when dashboard document refresh defaults are invalid" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        dashboard_document: %Document{defaults: %{"time" => %{"refresh_ms" => 0}}}
      }
    }

    assert EngineResolution.refresh_ms(socket, 1_000) == 1_000
  end
end
