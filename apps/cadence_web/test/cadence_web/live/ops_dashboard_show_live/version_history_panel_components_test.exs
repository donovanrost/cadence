defmodule CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{
    ComparisonReviewQueue,
    DashboardSummary,
    Document,
    Version
  }

  alias CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelComponents

  test "versions_panel renders version pointers and version actions" do
    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: %DashboardSummary{
          dashboard_id: "dashboard-1",
          organization_id: "org-1",
          mission_id: "mission-1",
          name: "Dashboard",
          latest_version: 2,
          draft_version: 2,
          published_version: 1
        },
        dashboard_versions: [
          version(1, :publish, "published save"),
          version(2, :draft_save, "draft save")
        ],
        dashboard_lifecycle_events: [],
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-version-list > li")
             |> LazyHTML.attribute("id")
             |> Enum.map(&String.replace_prefix(&1, "dashboard-version-", ""))
             |> Enum.take(1)

    assert ["published"] =
             document
             |> LazyHTML.query("#dashboard-version-1 [data-version-pointer]")
             |> LazyHTML.attribute("data-version-pointer")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-version-2")
             |> LazyHTML.attribute("data-version-publish-available")

    assert ["already_latest"] =
             document
             |> LazyHTML.query("#dashboard-version-2")
             |> LazyHTML.attribute("data-version-restore-reason")

    assert "draft save" =
             document
             |> LazyHTML.query(~s(#dashboard-version-2 [data-version-field="Summary"]))
             |> selected_text()

    assert ["draft_save"] =
             document
             |> LazyHTML.query("#dashboard-version-2")
             |> LazyHTML.attribute("data-version-lineage-kind")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-version-2")
             |> LazyHTML.attribute("data-version-lineage-source-version")

    assert "Draft saved from v1" =
             document
             |> LazyHTML.query(~s(#dashboard-version-2 [data-version-field="Origin"]))
             |> selected_text()
  end

  test "versions_panel filters and selects health snapshot activity" do
    health_event =
      lifecycle_event(
        "dashboard-lifecycle-event-health",
        :health_snapshot_captured,
        occurred_at: ~U[2026-06-24 12:03:00Z],
        payload: %{
          "schema" => "dashboard_health_snapshot_capture.v1",
          "snapshot_id" => "health-snapshot-1",
          "snapshot_schema" => "dashboard_health_snapshot.v1",
          "health_state" => "attention",
          "health_severity" => "warning",
          "snapshot" => %{
            "schema" => "dashboard_health_snapshot.v1",
            "snapshot_id" => "health-snapshot-1"
          }
        }
      )

    published_event =
      lifecycle_event(
        "dashboard-lifecycle-event-published",
        :published,
        occurred_at: ~U[2026-06-24 12:02:00Z]
      )

    review_event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-review",
        occurred_at: ~U[2026-06-24 12:01:00Z]
      )

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [published_event, review_event, health_event],
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary([review_event]),
        dashboard_activity_filter: :health_snapshots,
        dashboard_activity_event_id: "dashboard-lifecycle-event-health",
        dashboard_review_placement_id: nil,
        dashboard_publish_readiness: nil,
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&selected_placement=placement-stale"
      )

    document = LazyHTML.from_fragment(html)

    assert ["health_snapshots"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-filter")

    assert ["health_snapshots"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-mode")

    assert ["health_snapshots"] =
             document
             |> LazyHTML.query("[data-dashboard-activity-filter-badge]")
             |> LazyHTML.attribute("data-dashboard-activity-filter-badge")

    assert [
             "",
             "version_changes",
             "comparison_reviews",
             "open_comparison_reviews",
             "health_snapshots",
             "publish_readiness"
           ] =
             document
             |> LazyHTML.query("[data-dashboard-activity-filter-option]")
             |> LazyHTML.attribute("data-dashboard-activity-filter-option")

    assert ["false", "false", "false", "false", "true", "false"] =
             document
             |> LazyHTML.query("[data-dashboard-activity-filter-option]")
             |> LazyHTML.attribute("data-dashboard-activity-filter-selected")

    assert ["dashboard-lifecycle-event-health"] =
             document
             |> LazyHTML.query("#dashboard-activity-list > li")
             |> LazyHTML.attribute("id")
             |> Enum.map(&String.replace_prefix(&1, "dashboard-activity-", ""))

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-health")
             |> LazyHTML.attribute("data-dashboard-activity-selected")

    assert ["dashboard-lifecycle-event-health"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event-visible")

    assert ["health_snapshot_captured"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event-type")

    assert "Health snapshot captured" =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-title]")
             |> selected_text()

    assert ["health-snapshot-1"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-event]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-id")

    assert ["select_activity_event"] =
             document
             |> LazyHTML.query("#dashboard-activity-select-dashboard-lifecycle-event-health")
             |> LazyHTML.attribute("phx-click")

    assert ["ClipboardButton"] =
             document
             |> LazyHTML.query("#dashboard-activity-link-copy-dashboard-lifecycle-event-health")
             |> LazyHTML.attribute("phx-hook")

    [activity_link] =
      document
      |> LazyHTML.query("#dashboard-activity-link-copy-dashboard-lifecycle-event-health")
      |> LazyHTML.attribute("data-clipboard-text")

    uri = URI.parse(activity_link)

    assert uri.path == "/missions/mission-1/ops/dashboards/dashboard-1"

    assert URI.decode_query(uri.query) == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_filter" => "health_snapshots",
             "activity_event" => "dashboard-lifecycle-event-health"
           }
  end

  test "versions_panel correlates selected version activity with runtime invalidation impact" do
    published_event =
      lifecycle_event(
        "dashboard-lifecycle-event-published",
        :published,
        dashboard_version: 3,
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [published_event],
        dashboard_recent_invalidations: [
          %{
            id: "invalidation-published",
            lifecycle_action: "published",
            document_version: "3",
            source_version: "-",
            context_match: "true",
            refresh_allowed: "true",
            refresh_action: "refresh_plan",
            context_reason_label: "matched",
            refresh_allowed_reason_label: "refresh allowed"
          }
        ],
        dashboard_activity_filter: :version_changes,
        dashboard_activity_event_id: "dashboard-lifecycle-event-published",
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["refresh_allowed"] =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-published")
             |> LazyHTML.attribute("data-dashboard-activity-runtime-impact-state")

    assert ["invalidation-published"] =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-published")
             |> LazyHTML.attribute("data-dashboard-activity-runtime-impact-invalidation")

    assert "Runtime refresh allowed: refresh_plan" =
             document
             |> LazyHTML.query(
               ~s(#dashboard-activity-dashboard-lifecycle-event-published [data-activity-field="Runtime"])
             )
             |> selected_text()

    assert ["refresh_allowed"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-runtime-impact-state")

    assert "Runtime refresh allowed: refresh_plan" =
             document
             |> LazyHTML.query(~s([data-dashboard-selected-activity-field="Runtime"]))
             |> selected_text()
  end

  defp dashboard_document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard"
    }
  end

  defp version(version, snapshot_kind, change_summary) do
    %Version{
      dashboard_version_id: "version-#{version}",
      organization_id: "org-1",
      mission_id: "mission-1",
      dashboard_id: "dashboard-1",
      version: version,
      document: dashboard_document(),
      snapshot_kind: snapshot_kind,
      parent_version: previous_version(version),
      based_on_version: previous_version(version),
      change_summary: change_summary,
      created_by: "operator",
      inserted_at: ~U[2026-06-24 12:00:00Z]
    }
  end

  defp previous_version(version) when is_integer(version) and version > 1, do: version - 1
  defp previous_version(_version), do: nil

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
