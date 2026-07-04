defmodule CadenceWeb.OpsDashboardShowLive.ActivityTimelineComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{ComparisonReviewQueue, Document}
  alias CadenceWeb.OpsDashboardShowLive.ActivityTimelineComponents

  test "activity_timeline renders open comparison review activity queue" do
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

    html =
      render_component(&ActivityTimelineComponents.activity_timeline/1,
        dashboard_document: dashboard_document(),
        dashboard_lifecycle_events: lifecycle_events,
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary(lifecycle_events),
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_activity_event_id: nil,
        dashboard_review_placement_id: "placement-open",
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
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

    assert ["dashboard-lifecycle-event-open"] =
             document
             |> LazyHTML.query("#dashboard-activity-list > li")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue-item")

    assert "Review Queue" =
             document
             |> LazyHTML.query("[data-dashboard-activity-title]")
             |> selected_text()
  end

  test "activity_timeline offers recovery when selected activity is hidden by filter" do
    published_event = lifecycle_event("dashboard-lifecycle-event-published", :published)
    health_event = lifecycle_event("dashboard-lifecycle-event-health", :health_snapshot_captured)

    html =
      render_component(&ActivityTimelineComponents.activity_timeline/1,
        dashboard_document: dashboard_document(),
        dashboard_lifecycle_events: [published_event, health_event],
        dashboard_activity_filter: :health_snapshots,
        dashboard_activity_event_id: "dashboard-lifecycle-event-published",
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["hidden"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-recovery")
             |> LazyHTML.attribute("data-dashboard-selected-activity-recovery")

    assert "This event exists but is hidden by the current activity filter." =
             document
             |> LazyHTML.query("#dashboard-selected-activity-recovery")
             |> selected_text()
             |> String.replace("Show all activity", "")
             |> String.trim()

    assert [href] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-recovery-link")
             |> LazyHTML.attribute("href")

    assert URI.decode_query(URI.parse(href).query) == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_event" => "dashboard-lifecycle-event-published"
           }
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
