defmodule CadenceWeb.OpsDashboardShowLive.VersionHistoryComparisonReviewQueueStateComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{ComparisonReviewQueue, Document}
  alias CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelComponents

  test "versions_panel renders explicit empty review queue state" do
    request_event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-resolved",
        placement_ids: ["placement-resolved"],
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    resolution_event =
      comparison_review_resolution_event(
        event_id: "dashboard-lifecycle-event-resolution",
        source_request_event_id: "dashboard-lifecycle-event-resolved",
        occurred_at: ~U[2026-06-24 12:01:00Z],
        payload: %{
          "schema" => "dashboard_comparison_review_resolution.v1",
          "source_request_event_id" => "dashboard-lifecycle-event-resolved",
          "disposition" => "review_completed"
        }
      )

    lifecycle_events = [request_event, resolution_event]

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: lifecycle_events,
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary(lifecycle_events),
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_activity_event_id: nil,
        dashboard_review_placement_id: nil,
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["empty"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-queue-state")

    assert ["empty"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-queue-state-message]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-queue-state-message")

    assert "No open comparison reviews." =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-queue-state-message]")
             |> selected_text()

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-activity-empty-filter]")
             |> LazyHTML.attribute("data-dashboard-activity-empty-filter")
  end

  test "versions_panel renders stale selected placement queue state" do
    open_request_event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-open",
        placement_ids: ["placement-current"],
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [open_request_event],
        dashboard_comparison_review_queue:
          ComparisonReviewQueue.open_summary([open_request_event]),
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_activity_event_id: nil,
        dashboard_review_placement_id: "placement-stale",
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["selection_stale"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-queue-state")

    assert ["selection_stale"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-queue-state-message]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-queue-state-message")

    assert "Selected review placement is no longer part of the open review queue." =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-queue-state-message]")
             |> selected_text()

    assert ["false"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-placement-link]")
             |> LazyHTML.attribute("data-dashboard-review-placement-selected")
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
