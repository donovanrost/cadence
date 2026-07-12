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

    document = LazyHTML.from_fragment(html)

    assert ["comparison_review_requested"] =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-1")
             |> LazyHTML.attribute("data-lifecycle-event-type")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-count")

    assert [""] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-filter")

    assert ["placement-1"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-review-selected-placement")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-requests")

    assert ["placement-1,placement-2"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-placements")

    assert "1 open reviews" =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-open-badge]")
             |> selected_text()

    assert "Comparison review requested" =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-1 .font-semibold")
             |> selected_text()

    assert ["dashboard_comparison_review_request.v1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-schema")

    assert ["open"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-status")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolve-form]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolve-form")

    assert ["resolve_comparison_review"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolve-form]")
             |> LazyHTML.attribute("phx-submit")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query(~s(input[name="review[source_request_event_id]"]))
             |> LazyHTML.attribute("value")

    assert ["placement-1"] =
             document
             |> LazyHTML.query(~s(input[name="review[selected_placement_id]"]))
             |> LazyHTML.attribute("value")

    assert ["placement-1,placement-2"] =
             document
             |> LazyHTML.query(~s(input[name="review[affected_placement_ids]"]))
             |> LazyHTML.attribute("value")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution-reason]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-reason")

    assert ["comparison_open_findings_review"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-kind")

    assert ["2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-count")

    assert ["placement-1", "placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-placement-link]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-placement-link")

    assert ["true", "false"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-placement-link]")
             |> LazyHTML.attribute("data-dashboard-review-placement-selected")

    assert ["2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-findings]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-findings")

    assert ["placement-1", "placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-finding")

    assert ["increased", "missing"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-finding-state")
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

    document = LazyHTML.from_fragment(html)

    assert ["resolved"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-status")

    assert ["0"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-count")

    assert [""] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-requests")

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-open-badge]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-badge")

    assert ["dashboard-lifecycle-event-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-event")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolved]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolved")

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolve-form]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolve-form")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-source")

    assert ["review_completed"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-disposition")

    assert ["placement-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-selected-placement"
             )

    assert ["bulk_correction_authority_review"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-workflow-kind")

    assert ["request_comparison_review"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-workflow-action")

    assert ["1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-workflow-selection-count"
             )

    assert "placement-1" =
             document
             |> LazyHTML.query(~s([data-activity-field="Resolution placement"]))
             |> selected_text()

    assert "bulk_correction_authority_review / 1" =
             document
             |> LazyHTML.query(~s([data-activity-field="Resolution workflow"]))
             |> selected_text()

    assert "Comparison review resolved" =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-2 .font-semibold")
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

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
