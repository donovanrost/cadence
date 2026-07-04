defmodule CadenceWeb.OpsDashboardShowLive.RenderPanelAssignsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{ComparisonReviewQueue, Document}
  alias CadenceWeb.OpsDashboardShowLive.RenderPanelAssigns
  alias Phoenix.LiveView.Socket

  test "projects panel render context from sockets and assigns maps" do
    expected = %{
      panel: :add_widget,
      dashboard_activity_filter: :open_comparison_reviews,
      dashboard_activity_event_id: "event-1",
      dashboard_review_placement_id: "placement-1",
      dashboard_selected_publish_issue_id: "error:invalid-grid",
      dashboard_comparison_review_action_outcome: %{action: :comparison_review_bulk_decision},
      widget_form: nil,
      spacecraft: [%{spacecraft_id: "SC-1"}],
      operational_observables: [%{observable_id: "obs.temp"}],
      points: [],
      points_empty?: true,
      selected_point_id: "HK.temp",
      selected_point_ids: ["HK.temp", "obs.temp"],
      dashboard_scope_context: %{primary: %{kind: "spacecraft", ids: ["sc-1"]}},
      dashboard_editor_focus: nil,
      widget_error: "invalid widget",
      mission_id: "mission-1",
      dashboard_document: document(),
      dashboard_summary: %{draft_version: 2},
      dashboard_versions: [%{version: 2}],
      dashboard_lifecycle_events: [%{event_type: :published}],
      dashboard_comparison_review_queue: %{count: 1, requests: [%{event_id: "review-1"}]},
      dashboard_source_action_events: [%{source_health_event_id: "source-health-event-1"}],
      dashboard_recent_invalidations: [%{id: "invalidation-1"}],
      dashboard_publish_validation: %{valid?: true},
      dashboard_publish_validation_freshness: freshness(),
      historical_workflow_request_form: nil,
      data_link_action_outcome: nil
    }

    assert RenderPanelAssigns.panel_context(%Socket{assigns: assigns(%{points: []})}) ==
             expected

    assert RenderPanelAssigns.panel_context(assigns(%{points: []})) == expected
  end

  test "projects panel defaults" do
    assert RenderPanelAssigns.panel_context(%{}) == %{
             panel: nil,
             dashboard_activity_filter: nil,
             dashboard_activity_event_id: nil,
             dashboard_review_placement_id: nil,
             dashboard_selected_publish_issue_id: nil,
             dashboard_comparison_review_action_outcome: nil,
             widget_form: nil,
             spacecraft: [],
             operational_observables: [],
             points: [],
             points_empty?: true,
             selected_point_id: nil,
             selected_point_ids: [],
             dashboard_scope_context: nil,
             dashboard_editor_focus: nil,
             widget_error: nil,
             mission_id: nil,
             dashboard_document: nil,
             dashboard_summary: nil,
             dashboard_versions: [],
             dashboard_lifecycle_events: [],
             dashboard_comparison_review_queue: empty_review_queue(),
             dashboard_source_action_events: [],
             dashboard_recent_invalidations: [],
             dashboard_publish_validation: nil,
             dashboard_publish_validation_freshness: nil,
             historical_workflow_request_form: nil,
             data_link_action_outcome: nil
           }
  end

  defp assigns(overrides) do
    Map.merge(
      %{
        current_mission: %{mission_id: "mission-1"},
        dashboard_document: document(),
        dashboard_summary: %{draft_version: 2},
        dashboard_versions: [%{version: 2}],
        dashboard_lifecycle_events: [%{event_type: :published}],
        dashboard_comparison_review_queue: %{count: 1, requests: [%{event_id: "review-1"}]},
        dashboard_source_action_events: [%{source_health_event_id: "source-health-event-1"}],
        dashboard_recent_invalidations: [%{id: "invalidation-1"}],
        dashboard_publish_validation: %{valid?: true},
        dashboard_publish_validation_freshness: freshness(),
        spacecraft: [%{spacecraft_id: "SC-1"}],
        operational_observables: [%{observable_id: "obs.temp"}],
        points: [%{point_id: "HK.temp"}],
        selected_point_id: "HK.temp",
        selected_point_ids: ["HK.temp", "obs.temp"],
        dashboard_scope_context: %{primary: %{kind: "spacecraft", ids: ["sc-1"]}},
        widget_error: "invalid widget",
        panel: :add_widget,
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_activity_event_id: "event-1",
        dashboard_review_placement_id: "placement-1",
        dashboard_selected_publish_issue_id: "error:invalid-grid",
        dashboard_comparison_review_action_outcome: %{action: :comparison_review_bulk_decision},
        widget_form: nil,
        historical_workflow_request_form: nil
      },
      overrides
    )
  end

  defp document do
    %Document{dashboard_id: "dashboard-1"}
  end

  defp freshness do
    %{state: "current", evaluated_at: "2026-06-27T12:00:00Z"}
  end

  defp empty_review_queue do
    ComparisonReviewQueue.open_summary([])
  end
end
