defmodule CadenceWeb.OpsDashboardShowLive.VersionHistoryComparisonReviewDetailComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{ComparisonReviewQueue, Document}
  alias CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelComponents

  test "versions_panel renders comparison review request activity details" do
    event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-1",
        actor_id: "user-reviewer",
        placement_ids: ["placement-1", "placement-2"]
      )

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [event],
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary([event]),
        dashboard_activity_filter: nil,
        dashboard_activity_event_id: nil,
        dashboard_review_placement_id: "placement-1",
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    activity = activity_timeline_presentation(html)
    controls = activity_controls_presentation(html)

    open_badge =
      Enum.find(controls["header"]["items"], &(&1["key"] == "open-review-badge"))

    activity_row = activity_row_presentation(html, event.dashboard_lifecycle_event_id)

    assert activity_row["root"]["attrs"]["data-lifecycle-event-type"] ==
             "comparison_review_requested"

    assert "1" =
             activity["root"]["attrs"]["data-dashboard-comparison-review-open-count"]

    assert "" = activity["root"]["attrs"]["data-dashboard-activity-filter"]

    assert "placement-1" =
             activity["root"]["attrs"]["data-dashboard-review-selected-placement"]

    assert "dashboard-lifecycle-event-1" =
             activity["root"]["attrs"][
               "data-dashboard-comparison-review-open-requests"
             ]

    assert "placement-1,placement-2" =
             activity["root"]["attrs"][
               "data-dashboard-comparison-review-open-placements"
             ]

    assert %{"text" => "1 open reviews", "visible" => true} = open_badge

    assert activity_row["header"]["title"]["text"] == "Comparison review requested"

    presentation = comparison_presentation(html, "request", event.dashboard_lifecycle_event_id)
    root_attrs = presentation["root"]["attrs"]
    resolve_form = presentation["actions"]["resolve_form"]

    assert "dashboard_comparison_review_request.v1" =
             root_attrs["data-dashboard-comparison-review-schema"]

    assert "open" = root_attrs["data-dashboard-comparison-review-status"]

    assert "dashboard-lifecycle-event-1" =
             resolve_form["attrs"]["data-dashboard-comparison-review-resolve-form"]

    assert "resolve_comparison_review" = resolve_form["attrs"]["phx-submit"]

    assert "dashboard-lifecycle-event-1" =
             hidden_value(resolve_form, "review[source_request_event_id]")

    assert "placement-1" = hidden_value(resolve_form, "review[selected_placement_id]")

    assert "placement-1,placement-2" =
             hidden_value(resolve_form, "review[affected_placement_ids]")

    assert "dashboard-lifecycle-event-1" =
             resolve_form["text_input"]["attrs"][
               "data-dashboard-comparison-review-resolution-reason"
             ]

    assert "comparison_open_findings_review" =
             root_attrs["data-dashboard-comparison-review-kind"]

    assert "2" = root_attrs["data-dashboard-comparison-review-open-count"]

    placement_links = detail_row(presentation, "placements")["links"]

    assert ["placement-1", "placement-2"] =
             Enum.map(
               placement_links,
               & &1["attrs"]["data-dashboard-comparison-review-placement-link"]
             )

    assert ["true", "false"] =
             Enum.map(
               placement_links,
               & &1["attrs"]["data-dashboard-review-placement-selected"]
             )

    assert "2" =
             presentation["findings"]["attrs"]["data-dashboard-comparison-review-findings"]

    assert ["placement-1", "placement-2"] =
             Enum.map(
               presentation["findings"]["items"],
               & &1["attrs"]["data-dashboard-comparison-review-finding"]
             )

    assert ["increased", "missing"] =
             Enum.map(
               presentation["findings"]["items"],
               & &1["attrs"]["data-dashboard-comparison-review-finding-state"]
             )
  end

  test "versions_panel renders comparison review resolution state" do
    request_event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-1",
        actor_id: "user-reviewer",
        placement_ids: ["placement-1"]
      )

    resolution_event =
      comparison_review_resolution_event(
        event_id: "dashboard-lifecycle-event-2",
        source_request_event_id: "dashboard-lifecycle-event-1",
        actor_id: "user-resolver",
        payload: %{
          "workflow_intent" => %{
            "kind" => "bulk_correction_authority_review",
            "action" => "request_comparison_review",
            "selection_count" => 1
          },
          "source_open_count" => 1,
          "source_open_placement_ids" => ["placement-1"]
        }
      )

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [request_event, resolution_event],
        dashboard_comparison_review_queue:
          ComparisonReviewQueue.open_summary([request_event, resolution_event]),
        dashboard_activity_filter: nil,
        dashboard_activity_event_id: nil,
        dashboard_review_placement_id: nil,
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    activity = activity_timeline_presentation(html)
    controls = activity_controls_presentation(html)

    open_badge =
      Enum.find(controls["header"]["items"], &(&1["key"] == "open-review-badge"))

    request_presentation =
      comparison_presentation(html, "request", request_event.dashboard_lifecycle_event_id)

    request_attrs = request_presentation["root"]["attrs"]

    resolution_presentation =
      comparison_presentation(html, "resolution", resolution_event.dashboard_lifecycle_event_id)

    resolution_attrs = resolution_presentation["root"]["attrs"]

    assert "resolved" = request_attrs["data-dashboard-comparison-review-status"]

    assert "0" =
             activity["root"]["attrs"]["data-dashboard-comparison-review-open-count"]

    assert "" =
             activity["root"]["attrs"][
               "data-dashboard-comparison-review-open-requests"
             ]

    assert open_badge["visible"] == false

    assert "dashboard-lifecycle-event-2" =
             request_attrs["data-dashboard-comparison-review-resolution-event"]

    assert "dashboard-lifecycle-event-1" =
             request_presentation["actions"]["resolved_badge"]["attrs"][
               "data-dashboard-comparison-review-resolved"
             ]

    assert nil == request_presentation["actions"]["resolve_form"]

    assert "dashboard-lifecycle-event-1" =
             resolution_attrs["data-dashboard-comparison-review-resolution-source"]

    assert "review_completed" =
             resolution_attrs["data-dashboard-comparison-review-resolution-disposition"]

    assert "placement-1" =
             resolution_attrs["data-dashboard-comparison-review-resolution-selected-placement"]

    assert "bulk_correction_authority_review" =
             resolution_attrs["data-dashboard-comparison-review-resolution-workflow-kind"]

    assert "request_comparison_review" =
             resolution_attrs["data-dashboard-comparison-review-resolution-workflow-action"]

    assert "1" =
             resolution_attrs[
               "data-dashboard-comparison-review-resolution-workflow-selection-count"
             ]

    assert "placement-1" = detail_value(resolution_presentation, "placement")

    assert "bulk_correction_authority_review / 1" =
             detail_value(resolution_presentation, "workflow")

    assert activity_row_presentation(html, resolution_event.dashboard_lifecycle_event_id)[
             "header"
           ]["title"]["text"] == "Comparison review resolved"
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
    activity_timeline_presentation(rendered)["controls"]
  end

  defp activity_timeline_presentation(rendered) do
    vue = LiveVue.Test.get_vue(rendered, id: "dashboard-activity-timeline-component")

    assert vue.component == "ActivityTimeline"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue.props["presentation"]
  end

  defp comparison_presentation(rendered, kind, event_id) do
    child = activity_row_presentation(rendered, event_id)["comparison_review"][kind]

    assert child["id"] == "dashboard-comparison-review-#{kind}-#{event_id}-component"
    assert child["class"] == "contents"
    assert child["attrs"] == %{"data-name" => "ComparisonReviewActivityDetails"}
    assert child["presentation"]["kind"] == kind
    child["presentation"]
  end

  defp activity_row_presentation(rendered, event_id) do
    row =
      rendered
      |> activity_timeline_presentation()
      |> get_in(["list", "rows"])
      |> Enum.find(&(&1["key"] == event_id))

    assert row["key"] == event_id
    assert is_integer(row["order"])
    assert row["presentation"]["root"]["id"] == "dashboard-activity-#{event_id}"
    assert row["presentation"] == Jason.decode!(Jason.encode!(row["presentation"]))
    row["presentation"]
  end

  defp detail_row(presentation, key) do
    Enum.find(presentation["details"]["rows"], &(&1["key"] == key))
  end

  defp detail_value(presentation, key), do: detail_row(presentation, key)["value"]

  defp hidden_value(form, name) do
    form["hidden_fields"]
    |> Enum.find(&(&1["attrs"]["name"] == name))
    |> get_in(["attrs", "value"])
  end
end
