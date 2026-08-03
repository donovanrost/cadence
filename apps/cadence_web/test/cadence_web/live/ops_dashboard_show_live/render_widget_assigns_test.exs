defmodule CadenceWeb.OpsDashboardShowLive.RenderWidgetAssignsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias Cadence.Dashboards.{ComparisonReviewQueue, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.RenderWidgetAssigns
  alias Phoenix.LiveView.Socket

  test "projects widget render context with placement-scoped maps" do
    context = RenderWidgetAssigns.widget_context(%Socket{assigns: assigns()})

    assert context.render_items == [render_item("placement-1")]
    assert context.review_focus == nil
    assert context.edit_mode? == true
    assert context.spacecraft == [%{spacecraft_id: "SC-1"}]
    assert context.selected_data_ref == selected_data_ref()
    assert context.data_view == "all_revisions"
    assert context.compare_data_view == "canonical"
    assert context.context_spacecraft_id == "SC-1"
    assert context.chart_epoch == 4
    assert context.widget_data_by_placement == %{"placement-1" => %{kind: :legacy_point}}
    assert context.backfills_by_placement == %{"placement-1" => %{state: :requested}}
    assert context.frames_by_placement == %{"placement-1" => %{frame: :engine}}
    assert context.compare_frames_by_placement == %{"placement-1" => %{frame: :compare_engine}}
    assert context.points_by_id == %{"HK.temp" => %{point_id: "HK.temp"}}

    assert context.content_class == [
             "grid-stack-item-content cadence-dashboard-panel border flex flex-col overflow-hidden",
             "border-primary/40 ring-1 ring-primary/20 cursor-move"
           ]
  end

  test "normalizes missing placement-scoped maps and non-edit widget classes" do
    context =
      RenderWidgetAssigns.widget_context(
        assigns(%{
          edit_mode?: false,
          widget_data: nil,
          backfills: [],
          dashboard_engine_frames_by_placement: nil,
          dashboard_compare_engine_frames_by_placement: nil,
          points_by_id: []
        })
      )

    assert context.widget_data_by_placement == %{}
    assert context.backfills_by_placement == %{}
    assert context.frames_by_placement == %{}
    assert context.compare_frames_by_placement == %{}
    assert context.points_by_id == %{}

    assert context.content_class == [
             "grid-stack-item-content cadence-dashboard-panel border flex flex-col overflow-hidden",
             "border-base-300/80"
           ]
  end

  test "projects open comparison review placement focus" do
    lifecycle_events = [
      comparison_review_request_event(
        event_id: "review-request-1",
        placement_ids: ["placement-1", "placement-2"]
      ),
      comparison_review_request_event(
        event_id: "review-request-2",
        placement_ids: ["placement-3"]
      ),
      comparison_review_resolution_event(
        event_id: "review-resolution-2",
        source_request_event_id: "review-request-2"
      )
    ]

    context =
      RenderWidgetAssigns.widget_context(
        assigns(%{
          dashboard_activity_filter: :open_comparison_reviews,
          dashboard_lifecycle_events: lifecycle_events,
          dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary(lifecycle_events)
        })
      )

    assert context.review_focus == %{
             mode: :open_comparison_reviews,
             placement_ids: ["placement-1", "placement-2"],
             request_ids: ["review-request-1"],
             selected_placement_id: nil
           }
  end

  test "does not project open comparison review focus from lifecycle events alone" do
    context =
      RenderWidgetAssigns.widget_context(
        assigns(%{
          dashboard_activity_filter: :open_comparison_reviews,
          dashboard_lifecycle_events: [
            comparison_review_request_event(
              event_id: "review-request-1",
              placement_ids: ["placement-1"]
            )
          ],
          dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary([])
        })
      )

    assert context.review_focus == %{
             mode: :open_comparison_reviews,
             placement_ids: [],
             request_ids: [],
             selected_placement_id: nil
           }
  end

  test "detects context widgets" do
    assert RenderWidgetAssigns.context_widgets?([render_item("placement-1")])

    refute RenderWidgetAssigns.context_widgets?([
             %{
               placement_id: "placement-2",
               widget: %RenderWidget{
                 widget_id: "widget-2",
                 type: :value_tile,
                 title: "Temperature",
                 binding: %{source: :telemetry, mode: :static}
               }
             }
           ])

    refute RenderWidgetAssigns.context_widgets?(nil)
  end

  defp assigns(overrides \\ %{}) do
    Map.merge(
      %{
        dashboard_render_items: [render_item("placement-1")],
        dashboard_activity_filter: nil,
        dashboard_review_placement_id: nil,
        dashboard_lifecycle_events: [],
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary([]),
        dashboard_selected_data_ref: selected_data_ref(),
        dashboard_data_view: "all_revisions",
        dashboard_compare_data_view: "canonical",
        context_spacecraft_id: "SC-1",
        edit_mode?: true,
        spacecraft: [%{spacecraft_id: "SC-1"}],
        chart_epoch: 4,
        widget_data: %{"placement-1" => %{kind: :legacy_point}},
        backfills: %{"placement-1" => %{state: :requested}},
        dashboard_engine_frames_by_placement: %{"placement-1" => %{frame: :engine}},
        dashboard_compare_engine_frames_by_placement: %{
          "placement-1" => %{frame: :compare_engine}
        },
        points_by_id: %{"HK.temp" => %{point_id: "HK.temp"}}
      },
      overrides
    )
  end

  defp selected_data_ref do
    %{
      "target" => "telemetry_sample",
      "target_id" => "sample-1",
      "source_binding_id" => "rehearsal-binding"
    }
  end

  defp render_item(placement_id) do
    %{
      placement_id: placement_id,
      widget: %RenderWidget{
        widget_id: "widget-1",
        type: :value_tile,
        title: "Temperature",
        binding: %{source: :telemetry, mode: :context}
      }
    }
  end
end
