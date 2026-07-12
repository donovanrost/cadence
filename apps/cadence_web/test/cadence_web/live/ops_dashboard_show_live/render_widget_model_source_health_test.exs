defmodule CadenceWeb.OpsDashboardShowLive.RenderWidgetModelSourceHealthTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    ComparisonReviewQueue,
    DashboardResolveRequest,
    Document,
    Engine,
    Placement,
    RenderWidget,
    WidgetDef
  }

  alias CadenceWeb.OpsDashboardShowLive.RenderWidgetModel

  test "widget_items carries stale operational source warnings into lifecycle attrs" do
    document = operational_command_queue_document()

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document
        },
        freshness_now: ~U[2026-06-17 12:05:02Z],
        source_freshness_policies: %{operational_observables: %{stale_after_ms: 1_000}},
        source_opts: %{
          operational_observables: [
            command_queue_entries_fun: fn _organization_id, _mission_id, _opts -> [] end,
            read_time: ~U[2026-06-17 12:05:00Z]
          ]
        }
      )

    [widget_item] =
      assigns(%{
        dashboard_document: document,
        dashboard_render_items: [
          render_item("placement-command-queue", %{
            widget:
              render_widget(%{
                type: :value_tile,
                title: "Command Queue",
                binding: %{
                  source: :operational_observables,
                  mode: :context,
                  point_id: "commanding.queue_depth",
                  point_ids: ["commanding.queue_depth"]
                }
              })
          })
        ],
        dashboard_engine_frames_by_placement: result.frames_by_placement
      })
      |> RenderWidgetModel.widget_items()

    assert widget_item.shell_attrs["data-widget-lifecycle-state"] == "stale"
    assert widget_item.shell_attrs["data-widget-lifecycle-severity"] == "warning"
    assert widget_item.shell_attrs["data-widget-lifecycle-reasons"] == "stale,stale_data"
    assert widget_item.shell_attrs["data-widget-lifecycle-warning-codes"] == "stale_data"
    assert widget_item.shell_attrs["data-widget-placement-warning-codes"] == "stale_data"
    assert widget_item.shell_attrs["data-widget-source-state"] == "stale"
    assert widget_item.shell_attrs["data-widget-source-severity"] == "warning"
    assert widget_item.shell_attrs["data-widget-source-data-state"] == "ready"
    assert widget_item.shell_attrs["data-widget-source-stale"] == "true"
    assert widget_item.shell_attrs["data-widget-source-warning-codes"] == "stale_data"

    assert widget_item.shell_attrs["data-widget-source-logical-sources"] ==
             "operational_observables"

    assert widget_item.shell_attrs["data-widget-source-data-source-ids"] ==
             "managed_operational_observables"

    assert widget_item.shell_attrs["data-widget-source-binding-ids"] ==
             "default_flight_operational_observables"

    assert widget_item.shell_attrs["data-widget-source-realms"] == "flight"
    assert widget_item.component_props.mission_id == "mission-render-widget"

    assert widget_item.props.data.lifecycle_state == :stale
    assert widget_item.props.data.sample.engineering_value == 0
  end

  defp assigns(overrides) do
    Map.merge(
      %{
        dashboard_render_items: [],
        dashboard_activity_filter: nil,
        dashboard_review_placement_id: nil,
        dashboard_lifecycle_events: [],
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary([]),
        dashboard_selected_data_ref: nil,
        dashboard_data_view: "canonical",
        dashboard_compare_data_view: nil,
        context_spacecraft_id: nil,
        edit_mode?: false,
        spacecraft: [],
        chart_epoch: 1,
        widget_data: %{},
        backfills: %{},
        dashboard_engine_frames_by_placement: %{},
        dashboard_compare_engine_frames_by_placement: %{},
        points_by_id: %{}
      },
      overrides
    )
  end

  defp render_item(placement_id, attrs) do
    Map.merge(
      %{
        placement_id: placement_id,
        layout: %{x: 0, y: 0, w: 4, h: 3},
        widget: render_widget()
      },
      attrs
    )
  end

  defp render_widget(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          widget_id: "widget-1",
          type: :value_tile,
          title: "Temperature",
          binding: %{
            source: :telemetry,
            mode: :context,
            spacecraft_id: nil,
            point_id: "HK.temp",
            point_ids: ["HK.temp"]
          },
          options: %{precision: 2, window_seconds: 300}
        },
        attrs
      )

    struct!(RenderWidget, attrs)
  end

  defp operational_command_queue_document do
    %Document{
      dashboard_id: "dashboard-command-queue",
      organization_id: "org-render-widget",
      mission_id: "mission-render-widget",
      name: "Command Queue",
      placements: [
        %Placement{
          placement_id: "placement-command-queue",
          layout: %{x: nil, y: nil, w: 3, h: 2},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.value_tile",
            widget_type_version: 1,
            title: "Command Queue",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"],
              scope_mode: :context,
              data_mode: :context,
              value_type: :engineering,
              sampling: :latest,
              overlays: []
            },
            options: %{precision: 0}
          }
        }
      ]
    }
  end
end
