defmodule CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelRecoveryComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelComponents

  test "versions_panel offers recovery when selected activity is hidden by filter" do
    published_event = lifecycle_event("dashboard-lifecycle-event-published", :published)
    health_event = lifecycle_event("dashboard-lifecycle-event-health", :health_snapshot_captured)

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [published_event, health_event],
        dashboard_activity_filter: :health_snapshots,
        dashboard_activity_event_id: "dashboard-lifecycle-event-published",
        dashboard_publish_readiness: nil,
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

    query =
      href
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert query == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_event" => "dashboard-lifecycle-event-published"
           }
  end

  test "versions_panel offers recovery when selected activity is unavailable" do
    health_event = lifecycle_event("dashboard-lifecycle-event-health", :health_snapshot_captured)

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [health_event],
        dashboard_activity_filter: :publish_readiness,
        dashboard_activity_event_id: "dashboard-lifecycle-event-missing",
        dashboard_publish_readiness: nil,
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&activity_event=dashboard-lifecycle-event-missing"
      )

    document = LazyHTML.from_fragment(html)

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event-found")

    assert ["missing"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-recovery")
             |> LazyHTML.attribute("data-dashboard-selected-activity-recovery")

    assert "This event is no longer available in the dashboard activity log." =
             document
             |> LazyHTML.query("#dashboard-selected-activity-recovery")
             |> selected_text()
             |> String.replace("Clear selection", "")
             |> String.trim()

    assert [href] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-recovery-link")
             |> LazyHTML.attribute("href")

    query =
      href
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert query == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions"
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
