defmodule CadenceWeb.OpsDashboardShowLive.RenderWidgetModelTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias Cadence.Dashboards.{
    ComparisonReviewQueue,
    PlacementFrames,
    RenderWidget,
    ResolveWarning
  }

  alias CadenceWeb.OpsDashboardShowLive.RenderWidgetModel

  test "selected_data_ref_for_placement keeps global selections and matching placement selections" do
    global_ref = %{"target" => "telemetry_sample"}
    placement_ref = %{"target" => "telemetry_sample", "placement_id" => "placement-1"}

    assert RenderWidgetModel.selected_data_ref_for_placement(global_ref, "placement-1") ==
             global_ref

    assert RenderWidgetModel.selected_data_ref_for_placement(placement_ref, "placement-1") ==
             placement_ref

    assert RenderWidgetModel.selected_data_ref_for_placement(placement_ref, "placement-2") == nil
    assert RenderWidgetModel.selected_data_ref_for_placement(nil, "placement-1") == nil
  end

  test "widget_items prepares shell attrs and edit mode classes" do
    [widget_item] =
      assigns(%{
        edit_mode?: true,
        dashboard_render_items: [
          render_item("placement-1", %{layout: %{x: nil, y: 2, w: 5, h: 4}})
        ]
      })
      |> RenderWidgetModel.widget_items()

    assert widget_item.shell_attrs == %{
             :id => "widget-placement-1",
             :class => "grid-stack-item",
             :"gs-id" => "placement-1",
             :"gs-x" => nil,
             :"gs-y" => 2,
             :"gs-w" => 5,
             :"gs-h" => 4,
             :"gs-auto-position" => "true",
             "data-widget-lifecycle-state" => "no_data",
             "data-widget-lifecycle-severity" => "info",
             "data-widget-lifecycle-reasons" => "no_data",
             "data-widget-lifecycle-warning-codes" => "",
             "data-widget-placement-warning-codes" => "",
             "data-widget-source-state" => "",
             "data-widget-source-severity" => "",
             "data-widget-source-data-state" => "",
             "data-widget-source-stale" => "",
             "data-widget-source-warning-codes" => "",
             "data-widget-source-freshness-states" => "",
             "data-widget-source-confidences" => "",
             "data-widget-source-logical-sources" => "",
             "data-widget-source-request-ids" => "",
             "data-widget-source-data-source-ids" => "",
             "data-widget-source-binding-ids" => "",
             "data-widget-source-realms" => "",
             "data-widget-source-time-modes" => "",
             "data-widget-source-time-axes" => "",
             "data-widget-source-replay-run-ids" => "",
             "data-widget-source-scope-kinds" => "",
             "data-widget-source-scope-ids" => "",
             "data-widget-source-contact-ids" => "",
             "data-widget-source-source-endpoint-ids" => "",
             "data-widget-source-health-states" => "",
             "data-widget-source-health-reasons" => "",
             "data-widget-source-health-event-ids" => "",
             "data-widget-source-empty-reason" => ""
           }

    assert Enum.member?(
             widget_item.content_class,
             "grid-stack-item-content bg-base-200 border flex flex-col overflow-hidden"
           )

    assert Enum.member?(
             widget_item.content_class,
             "border-primary/40 ring-1 ring-primary/20 cursor-move"
           )

    [locked_widget_item] =
      assigns(%{
        edit_mode?: false,
        dashboard_render_items: [render_item("placement-2", %{layout: %{x: 1, y: 0, w: 4, h: 3}})]
      })
      |> RenderWidgetModel.widget_items()

    assert locked_widget_item.shell_attrs["gs-auto-position"] == nil

    assert Enum.member?(
             locked_widget_item.content_class,
             "border-base-300 hover:border-primary/60"
           )
  end

  test "widget_items prepares widget props with legacy data when no engine frame exists" do
    point = %{point_id: "HK.temp"}
    legacy_data = %{kind: :legacy_point}
    selected_ref = %{"target" => "telemetry_sample"}

    [widget_item] =
      assigns(%{
        dashboard_render_items: [render_item("placement-1")],
        widget_data: %{"placement-1" => legacy_data},
        points_by_id: %{"HK.temp" => point},
        dashboard_selected_data_ref: selected_ref,
        dashboard_time_mode: "replay_run",
        dashboard_time_context: %{"mode" => "replay_run", "axis" => "receipt_time"},
        dashboard_replay_run_id: "replay-run-1",
        dashboard_data_realm: "rehearsal",
        context_spacecraft_id: "SC-1",
        dashboard_data_source_id: "questdb-rehearsal",
        dashboard_source_binding_id: "binding-rehearsal",
        chart_epoch: 3,
        edit_mode?: true
      })
      |> RenderWidgetModel.widget_items()

    assert widget_item.item.placement_id == "placement-1"
    assert widget_item.props.data == legacy_data
    assert widget_item.props.compare_data == nil
    assert widget_item.props.point == point
    assert widget_item.props.backfill == nil
    assert widget_item.props.limit_markers == []
    assert widget_item.props.event_markers == []
    assert widget_item.props.selected_data_ref == selected_ref
    assert widget_item.props.context_spacecraft_id == "SC-1"
    assert widget_item.props.chart_epoch == 3
    assert widget_item.props.edit_mode == true
    assert widget_item.props.warnings == []

    assert widget_item.component_props == %{
             widget: widget_item.item.widget,
             placement_id: "placement-1",
             mission_id: nil,
             data: legacy_data,
             compare_data: nil,
             point: point,
             spacecraft: [],
             backfill: nil,
             compare_backfill: nil,
             limit_markers: [],
             event_markers: [],
             selected_data_ref: selected_ref,
             time_mode: "replay_run",
             time_axis: "receipt_time",
             replay_run_id: "replay-run-1",
             data_realm: "rehearsal",
             data_view: "canonical",
             compare_data_view: nil,
             data_source_id: "questdb-rehearsal",
             source_binding_id: "binding-rehearsal",
             comparison_summary: nil,
             context_spacecraft_id: "SC-1",
             chart_epoch: 3,
             edit_mode?: true,
             warnings: []
           }
  end

  test "widget_items prepares engine-backed widget props and placement warnings" do
    legacy_data = %{kind: :legacy_point}

    placement_frames = %PlacementFrames{
      warnings: [
        %ResolveWarning{
          code: :watermark_unknown,
          severity: :warning,
          scope: :placement,
          message: "Watermark unavailable",
          details: %{source_binding_id: "flight-binding"}
        }
      ]
    }

    [widget_item] =
      assigns(%{
        dashboard_render_items: [render_item("placement-1")],
        widget_data: %{"placement-1" => legacy_data},
        dashboard_engine_frames_by_placement: %{"placement-1" => placement_frames}
      })
      |> RenderWidgetModel.widget_items()

    assert widget_item.props.data.kind == :point
    assert widget_item.props.data.lifecycle_state == :no_data
    refute Map.equal?(widget_item.props.data, legacy_data)

    assert [
             %{
               code: :watermark_unknown,
               severity: :warning,
               message: "Watermark unavailable"
             }
           ] = widget_item.props.warnings
  end

  test "widget_items marks placements affected by focused comparison reviews" do
    lifecycle_events = [
      comparison_review_request_event(
        event_id: "review-request-1",
        placement_ids: ["placement-1"]
      )
    ]

    [focused_widget_item, ordinary_widget_item] =
      assigns(%{
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_review_placement_id: "placement-1",
        dashboard_lifecycle_events: lifecycle_events,
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary(lifecycle_events),
        dashboard_render_items: [
          render_item("placement-1"),
          render_item("placement-2")
        ]
      })
      |> RenderWidgetModel.widget_items()

    assert focused_widget_item.shell_attrs[:class] ==
             "grid-stack-item dashboard-review-placement-focus dashboard-review-placement-selected"

    assert focused_widget_item.shell_attrs["data-dashboard-review-placement-focus"] ==
             "open_comparison_reviews"

    assert focused_widget_item.shell_attrs["data-dashboard-review-placement-id"] == "placement-1"

    assert focused_widget_item.shell_attrs["data-dashboard-review-request-ids"] ==
             "review-request-1"

    assert focused_widget_item.shell_attrs["data-dashboard-review-placement-selected"] == "true"
    assert focused_widget_item.props.review_focus.request_ids == ["review-request-1"]
    assert focused_widget_item.props.review_focus.selected_placement_id == "placement-1"

    assert ordinary_widget_item.shell_attrs[:class] == "grid-stack-item"
    refute Map.has_key?(ordinary_widget_item.shell_attrs, "data-dashboard-review-placement-focus")
    assert ordinary_widget_item.props.review_focus == nil
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

  defp render_item(placement_id, attrs \\ %{}) do
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
end
