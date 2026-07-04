defmodule CadenceWeb.OpsDashboardShowLive.ActivityTimelineShellComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{ComparisonReviewQueue, Document}
  alias CadenceWeb.OpsDashboardShowLive.ActivityEventSummary
  alias CadenceWeb.OpsDashboardShowLive.ActivityTimelineShellComponents
  alias CadenceWeb.OpsDashboardShowLive.ActivityViewModel
  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewActionOutcome

  test "activity_timeline_shell renders filter controls and open review queue metadata" do
    open_request_event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-open",
        placement_ids: ["placement-open"],
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    resolved_request_event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-resolved",
        placement_ids: ["placement-resolved"],
        occurred_at: ~U[2026-06-24 12:01:00Z]
      )

    resolution_event =
      comparison_review_resolution_event(
        event_id: "dashboard-lifecycle-event-resolution",
        source_request_event_id: "dashboard-lifecycle-event-resolved",
        occurred_at: ~U[2026-06-24 12:02:00Z],
        payload: %{
          "schema" => "dashboard_comparison_review_resolution.v1",
          "source_request_event_id" => "dashboard-lifecycle-event-resolved",
          "disposition" => "review_completed"
        }
      )

    lifecycle_events = [open_request_event, resolved_request_event, resolution_event]

    activity =
      ActivityViewModel.build(lifecycle_events, :open_comparison_reviews,
        open_summary: ComparisonReviewQueue.open_summary(lifecycle_events),
        selected_placement_id: "placement-open"
      )

    html =
      render_shell(
        activity: activity,
        activity_rows: ActivityEventSummary.rows(activity.visible_events, nil, []),
        selected_activity_event:
          ActivityEventSummary.build(
            lifecycle_events,
            nil,
            activity.visible_events,
            activity,
            [],
            []
          ),
        dashboard_lifecycle_events: lifecycle_events,
        dashboard_review_placement_id: "placement-open"
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_comparison_reviews"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-mode")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue-count")

    assert ["open_versions"] =
             document
             |> LazyHTML.query("#dashboard-activity-clear-filter")
             |> LazyHTML.attribute("phx-click")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-activity-filter-open-reviews")
             |> LazyHTML.attribute("data-dashboard-activity-filter-selected")

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-activity-filter-reviews")
             |> LazyHTML.attribute("data-dashboard-activity-filter-selected")

    assert ["dashboard-lifecycle-event-open"] =
             document
             |> LazyHTML.query("#dashboard-activity-list > li")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue-item")
  end

  test "activity_timeline_shell renders the no lifecycle activity empty state" do
    activity =
      ActivityViewModel.build([], nil, open_summary: ComparisonReviewQueue.open_summary([]))

    html =
      render_shell(
        activity: activity,
        activity_rows: [],
        selected_activity_event: ActivityEventSummary.build([], nil, [], activity, [], []),
        dashboard_lifecycle_events: []
      )

    document = LazyHTML.from_fragment(html)

    assert ["no_lifecycle"] =
             document
             |> LazyHTML.query("[data-dashboard-activity-empty]")
             |> LazyHTML.attribute("data-dashboard-activity-empty")

    assert "No lifecycle activity." =
             document
             |> LazyHTML.query("[data-dashboard-activity-empty]")
             |> selected_text()
  end

  test "activity_timeline_shell renders comparison review action outcome metadata" do
    activity =
      ActivityViewModel.build([], nil, open_summary: ComparisonReviewQueue.open_summary([]))

    html =
      render_shell(
        activity: activity,
        activity_rows: [],
        selected_activity_event: ActivityEventSummary.build([], nil, [], activity, [], []),
        dashboard_lifecycle_events: [],
        dashboard_comparison_review_action_outcome:
          ComparisonReviewActionOutcome.new(
            status: :degraded,
            kind: :warning,
            reason: "comparison_review_bulk_decision_partially_applied",
            decision: "mark_conflict",
            source_request_event_id: "review-request-1",
            workflow_id: "review-request-1",
            requested: 2,
            applied: 1,
            failed: 1,
            result_event_ids: "decision-event-1",
            target_event_id: "review-request-1",
            message: "Comparison review decisions applied to 1 findings; 1 failed."
          )
      )

    document = LazyHTML.from_fragment(html)

    assert ["comparison_review_bulk_decision"] =
             document
             |> LazyHTML.query("#dashboard-comparison-review-action-outcome")
             |> LazyHTML.attribute("data-dashboard-comparison-review-action")

    assert ["degraded"] =
             document
             |> LazyHTML.query("#dashboard-comparison-review-action-outcome")
             |> LazyHTML.attribute("data-dashboard-comparison-review-action-status")

    assert ["warning"] =
             document
             |> LazyHTML.query("#dashboard-comparison-review-action-outcome")
             |> LazyHTML.attribute("data-dashboard-comparison-review-action-kind")

    assert ["comparison_review_bulk_decision_partially_applied"] =
             document
             |> LazyHTML.query("#dashboard-comparison-review-action-outcome")
             |> LazyHTML.attribute("data-dashboard-comparison-review-action-reason")

    assert "Partial" =
             document
             |> LazyHTML.query("#dashboard-comparison-review-action-outcome .badge")
             |> selected_text()

    [metadata_json] =
      document
      |> LazyHTML.query("#dashboard-comparison-review-action-outcome")
      |> LazyHTML.attribute("data-dashboard-comparison-review-action-metadata")

    assert Jason.decode!(metadata_json) == %{
             "decision" => "mark_conflict",
             "source_request_event_id" => "review-request-1",
             "workflow_id" => "review-request-1",
             "requested" => "2",
             "applied" => "1",
             "failed" => "1",
             "result_event_ids" => "decision-event-1",
             "target_event_id" => "review-request-1"
           }

    action_text =
      document
      |> LazyHTML.query("#dashboard-comparison-review-action-outcome")
      |> selected_text()

    assert action_text =~ "Comparison Review Action"
    assert action_text =~ "Comparison review decisions applied to 1 findings; 1 failed."
    assert action_text =~ "Requested"
    assert action_text =~ "2"
    assert action_text =~ "Applied"
    assert action_text =~ "1"
    assert action_text =~ "Failed"
    assert action_text =~ "review-request-1"
    assert action_text =~ "decision-event-1"
  end

  defp render_shell(assigns) do
    defaults = [
      dashboard_document: dashboard_document(),
      dashboard_activity_event_id: nil,
      dashboard_review_placement_id: nil,
      dashboard_readiness_return_intent: nil,
      dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
    ]

    render_component(
      &ActivityTimelineShellComponents.activity_timeline_shell/1,
      Keyword.merge(defaults, assigns)
    )
  end

  defp dashboard_document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard"
    }
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
