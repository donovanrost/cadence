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

    activity = activity_timeline_presentation(html)
    queue_message = activity["queue_message"]

    assert "empty" =
             activity["root"]["attrs"]["data-dashboard-comparison-review-queue-state"]

    assert "empty" =
             queue_message["attrs"]["data-dashboard-comparison-review-queue-state-message"]

    assert "No open comparison reviews." = queue_message["text"]

    assert false =
             activity["empty_states"]
             |> Enum.find(&(&1["key"] == "empty-filter"))
             |> Map.fetch!("visible")
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

    activity = activity_timeline_presentation(html)
    queue_message = activity["queue_message"]

    assert "selection_stale" =
             activity["root"]["attrs"]["data-dashboard-comparison-review-queue-state"]

    assert "selection_stale" =
             queue_message["attrs"]["data-dashboard-comparison-review-queue-state-message"]

    assert "Selected review placement is no longer part of the open review queue." =
             queue_message["text"]

    presentation = comparison_request_presentation(html, open_request_event)

    assert ["false"] =
             presentation
             |> placement_links()
             |> Enum.map(& &1["attrs"]["data-dashboard-review-placement-selected"])
  end

  defp dashboard_document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard"
    }
  end

  defp activity_timeline_presentation(rendered) do
    vue = LiveVue.Test.get_vue(rendered, id: "dashboard-activity-timeline-component")

    assert vue.component == "ActivityTimeline"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue.props["presentation"]
  end

  defp comparison_request_presentation(rendered, event) do
    event_id = event.dashboard_lifecycle_event_id

    row =
      rendered
      |> activity_timeline_presentation()
      |> get_in(["list", "rows"])
      |> Enum.find(&(&1["key"] == event_id))

    assert row["key"] == event_id
    assert is_integer(row["order"])
    assert row["presentation"]["root"]["id"] == "dashboard-activity-#{event_id}"
    assert row["presentation"] == Jason.decode!(Jason.encode!(row["presentation"]))

    child = row["presentation"]["comparison_review"]["request"]
    assert child["attrs"] == %{"data-name" => "ComparisonReviewActivityDetails"}
    child["presentation"]
  end

  defp placement_links(presentation) do
    presentation["details"]["rows"]
    |> Enum.find(&(&1["key"] == "placements"))
    |> Map.fetch!("links")
  end
end
