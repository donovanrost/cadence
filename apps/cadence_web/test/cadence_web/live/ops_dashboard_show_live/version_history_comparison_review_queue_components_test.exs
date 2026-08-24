defmodule CadenceWeb.OpsDashboardShowLive.VersionHistoryComparisonReviewQueueComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{ComparisonReviewQueue, Document}
  alias CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelComponents

  test "versions_panel renders open comparison review activity queue" do
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
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: lifecycle_events,
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary(lifecycle_events),
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_activity_event_id: nil,
        dashboard_review_placement_id: "placement-open",
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)
    controls = activity_controls_presentation(html)
    header_items = controls["header"]["items"]

    assert ["open_comparison_reviews"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-mode")

    assert ["placement-open"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-review-selected-placement")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue-count")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-count")

    assert "Open reviews" =
             header_items
             |> Enum.find(&(&1["key"] == "active-filter-badge"))
             |> Map.fetch!("text")

    clear_filter = Enum.find(header_items, &(&1["id"] == "dashboard-activity-clear-filter"))
    assert "open_versions" = clear_filter["attrs"]["phx-click"]

    assert "open_comparison_reviews" =
             clear_filter["attrs"]["data-dashboard-activity-clear-filter"]

    assert ["dashboard-lifecycle-event-open"] =
             document
             |> LazyHTML.query("#dashboard-activity-list > li")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue-item")

    assert "Review Queue" =
             header_items
             |> Enum.find(&(&1["key"] == "title"))
             |> Map.fetch!("text")

    presentation = comparison_request_presentation(html, open_request_event)

    assert ["true"] =
             presentation
             |> placement_links()
             |> Enum.map(& &1["attrs"]["data-dashboard-review-placement-selected"])
  end

  test "versions_panel renders open comparison review activity from materialized queue" do
    queue_request =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-queued",
        placement_ids: ["placement-queued"],
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [],
        dashboard_comparison_review_queue: %{
          count: 1,
          count_text: "1",
          requests: [queue_request],
          request_ids: ["dashboard-lifecycle-event-queued"],
          request_ids_attr: "dashboard-lifecycle-event-queued",
          placement_ids: ["placement-queued"],
          placements_attr: "placement-queued"
        },
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_activity_event_id: nil,
        dashboard_review_placement_id: "placement-queued",
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_comparison_reviews"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-mode")

    assert ["dashboard-lifecycle-event-queued"] =
             document
             |> LazyHTML.query("#dashboard-activity-list > li")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue-item")

    assert ["dashboard-lifecycle-event-queued"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-requests")
  end

  defp dashboard_document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard"
    }
  end

  defp activity_controls_presentation(rendered) do
    vue = LiveVue.Test.get_vue(rendered, id: "dashboard-activity-controls-component")

    assert vue.component == "DashboardActivityControls"
    assert vue.class == "contents"
    assert vue.ssr == false

    vue.props["presentation"]
  end

  defp comparison_request_presentation(rendered, event) do
    vue =
      LiveVue.Test.get_vue(rendered,
        id: "dashboard-comparison-review-request-#{event.dashboard_lifecycle_event_id}-component"
      )

    assert vue.component == "ComparisonReviewActivityDetails"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    vue.props["presentation"]
  end

  defp placement_links(presentation) do
    presentation["details"]["rows"]
    |> Enum.find(&(&1["key"] == "placements"))
    |> Map.fetch!("links")
  end
end
