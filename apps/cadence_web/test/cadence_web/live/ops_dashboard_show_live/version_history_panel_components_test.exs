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

    summary = version_history_summary_presentation(html)
    version_list = summary["version_list"]

    [draft, published] = version_list["versions"]["list"]["rows"]

    assert ["2"] =
             version_list["versions"]["list"]["rows"]
             |> Enum.map(& &1["attrs"]["id"])
             |> Enum.map(&String.replace_prefix(&1, "dashboard-version-", ""))
             |> Enum.take(1)

    assert ["published"] =
             Enum.map(
               published["identity"]["pointers"],
               & &1["attrs"]["data-version-pointer"]
             )

    assert "true" = draft["attrs"]["data-version-publish-available"]

    assert "already_latest" = draft["attrs"]["data-version-restore-reason"]

    assert "draft save" = draft["summary"]["text"]

    assert "draft_save" = draft["attrs"]["data-version-lineage-kind"]

    assert "1" = draft["attrs"]["data-version-lineage-source-version"]

    assert "Draft saved from v1" =
             draft["details"]["rows"]
             |> Enum.find(&(&1["key"] == "origin"))
             |> get_in(["value", "text"])

    assert summary["publish_validation"] == nil

    assert summary["publish_impact"]["root"]["attrs"] == %{
             "id" => "dashboard-publish-impact",
             "class" => "space-y-2 border border-base-300/70 bg-base-100/40 p-2",
             "data-dashboard-publish-impact-state" => "no_runtime_context_change",
             "data-dashboard-publish-impact-severity" => "success",
             "data-dashboard-publish-impact-from-version" => "v1",
             "data-dashboard-publish-impact-to-version" => "v2",
             "data-dashboard-publish-impact-from-realm" => "nil",
             "data-dashboard-publish-impact-to-realm" => "nil",
             "data-dashboard-publish-impact-from-source-binding" => "nil",
             "data-dashboard-publish-impact-to-source-binding" => "nil",
             "data-dashboard-publish-impact-from-data-view" => "nil",
             "data-dashboard-publish-impact-to-data-view" => "nil"
           }

    assert summary["publish_impact"]["header"]["badge"] == %{
             "attrs" => %{
               "class" => "badge badge-xs badge-success",
               "data-dashboard-publish-impact-label" => "runtime defaults unchanged"
             },
             "text" => "runtime defaults unchanged"
           }

    assert summary["publish_impact"]["message"] == %{
             "attrs" => %{
               "class" => "text-xs text-base-content/70",
               "data-dashboard-publish-impact-message" => ""
             },
             "text" => "Publishing keeps operators on nil / nil / nil."
           }

    assert summary["runtime_defaults"]["root"]["attrs"][
             "data-dashboard-runtime-defaults-differ"
           ] == "false"

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-version-overview-component")
             |> LazyHTML.attribute("id")
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
    controls = activity_controls_presentation(html)

    selected_activity =
      LiveVue.Test.get_vue(html,
        id: "dashboard-selected-activity-event-component"
      ).props["presentation"]

    filter_badge =
      Enum.find(controls["header"]["items"], &(&1["key"] == "active-filter-badge"))

    filters = controls["controls"]["filters"]
    activity_row = activity_row_presentation(html, "dashboard-lifecycle-event-health")

    assert ["health_snapshots"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-filter")

    assert ["health_snapshots"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-mode")

    assert "health_snapshots" =
             filter_badge["attrs"]["data-dashboard-activity-filter-badge"]

    assert [
             "",
             "version_changes",
             "comparison_reviews",
             "open_comparison_reviews",
             "health_snapshots",
             "publish_readiness"
           ] =
             Enum.map(filters, & &1["attrs"]["data-dashboard-activity-filter-option"])

    assert ["false", "false", "false", "false", "true", "false"] =
             Enum.map(filters, & &1["attrs"]["data-dashboard-activity-filter-selected"])

    assert activity_row["root"]["id"] ==
             "dashboard-activity-dashboard-lifecycle-event-health"

    assert activity_row["root"]["attrs"]["data-dashboard-activity-selected"] == "true"

    assert "dashboard-lifecycle-event-health" =
             selected_activity["root"]["attrs"]["data-dashboard-selected-activity-event"]

    assert "true" =
             selected_activity["root"]["attrs"][
               "data-dashboard-selected-activity-event-visible"
             ]

    assert "health_snapshot_captured" =
             selected_activity["root"]["attrs"][
               "data-dashboard-selected-activity-event-type"
             ]

    assert "Health snapshot captured" =
             selected_activity["header"]["title"]["text"]

    health_snapshot = activity_row["health_snapshot"]

    assert health_snapshot["attrs"]["data-name"] == "HealthSnapshotActivity"

    assert health_snapshot["presentation"]["root"]["attrs"][
             "data-dashboard-health-snapshot-id"
           ] == "health-snapshot-1"

    refute Map.has_key?(health_snapshot, "ssr")

    assert activity_row["actions"]["select"]["attrs"]["phx-click"] ==
             "select_activity_event"

    copy_host = activity_row["actions"]["copy_host"]
    copy = activity_row["actions"]["copy_props"]

    assert copy_host["attrs"]["data-name"] == "ClipboardButton"
    refute Map.has_key?(copy_host, "ssr")

    assert copy["button_id"] ==
             "dashboard-activity-link-copy-dashboard-lifecycle-event-health"

    assert copy["data_attrs"] == %{
             "data-dashboard-activity-link-copy" => "dashboard-lifecycle-event-health"
           }

    activity_link = copy["clipboard_text"]

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

    activity_row = activity_row_presentation(html, "dashboard-lifecycle-event-published")

    selected_activity =
      LiveVue.Test.get_vue(html,
        id: "dashboard-selected-activity-event-component"
      ).props["presentation"]

    assert activity_row["root"]["attrs"]["data-dashboard-activity-runtime-impact-state"] ==
             "refresh_allowed"

    assert activity_row["root"]["attrs"][
             "data-dashboard-activity-runtime-impact-invalidation"
           ] == "invalidation-published"

    assert "Runtime refresh allowed: refresh_plan" =
             activity_row["fields"]["rows"]
             |> Enum.find(&(&1["value"]["attrs"]["data-activity-field"] == "Runtime"))
             |> get_in(["value", "text"])

    assert "refresh_allowed" =
             selected_activity["root"]["attrs"][
               "data-dashboard-selected-activity-runtime-impact-state"
             ]

    assert "Runtime refresh allowed: refresh_plan" =
             selected_activity["fields"]
             |> Enum.find(&(&1["label"] == "Runtime"))
             |> Map.fetch!("value")
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

  defp activity_controls_presentation(rendered) do
    vue = LiveVue.Test.get_vue(rendered, id: "dashboard-activity-controls-component")

    assert vue.component == "DashboardActivityControls"
    assert vue.class == "contents"
    assert vue.ssr == false

    vue.props["presentation"]
  end

  defp activity_row_presentation(rendered, event_id) do
    vue =
      LiveVue.Test.get_vue(rendered,
        id: "dashboard-activity-row-#{event_id}-component"
      )

    assert vue.component == "ActivityTimelineRow"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue.props["presentation"]
  end

  defp version_history_summary_presentation(rendered) do
    vue =
      LiveVue.Test.get_vue(rendered,
        id: "dashboard-version-history-summary-component"
      )

    assert vue.component == "VersionHistorySummary"
    assert vue.id == "dashboard-version-history-summary-component"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue.props["presentation"]
  end

end
