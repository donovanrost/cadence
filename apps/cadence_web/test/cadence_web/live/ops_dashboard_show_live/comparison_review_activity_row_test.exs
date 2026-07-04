defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewActivityRowTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewActivityRow

  test "request builds an open request row from lifecycle events" do
    event =
      comparison_review_request_event(
        findings: [
          %{
            "placement_id" => "placement-1",
            "title" => "Bus voltage",
            "state" => "increased",
            "decision_status" => "unhandled",
            "primary_observable_ids" => ["HK.counter"]
          },
          %{
            "placement_id" => "placement-2",
            "title" => "Current",
            "state" => "missing",
            "decision_status" => "unhandled",
            "observable_id" => "HK.current"
          }
        ]
      )

    row = ComparisonReviewActivityRow.request(event, [event], "placement-1")

    assert row.render? == true
    assert row.event_id == "dashboard-lifecycle-event-1"
    assert row.status == "open"
    assert row.kind == "comparison_open_findings_review"
    assert row.result_event_id == nil
    assert row.target_event_id == "dashboard-lifecycle-event-1"
    assert row.open_count_text == "2"
    assert row.placements_attr == "placement-1,placement-2"
    assert row.workflow_request_available? == true
    assert row.workflow_request_point_count_text == "2"
    assert row.workflow_request_point_ids_attr == "HK.counter,HK.current"

    assert row.placement_links == [
             %{
               placement_id: "placement-1",
               href: "#widget-placement-1",
               selected?: true,
               selected_text: "true"
             },
             %{
               placement_id: "placement-2",
               href: "#widget-placement-2",
               selected?: false,
               selected_text: "false"
             }
           ]

    assert Enum.map(row.findings, &Map.take(&1, [:placement_id, :title, :decision_status])) == [
             %{placement_id: "placement-1", title: "Bus voltage", decision_status: "unhandled"},
             %{placement_id: "placement-2", title: "Current", decision_status: "unhandled"}
           ]
  end

  test "request links resolved request rows to their resolution" do
    request = comparison_review_request_event()
    resolution = comparison_review_resolution_event()

    row = ComparisonReviewActivityRow.request(request, [request, resolution], nil)

    assert row.render? == true
    assert row.status == "resolved"
    assert row.resolved? == true
    assert row.resolution_event_id == "dashboard-lifecycle-event-2"
    assert row.result_event_id == "dashboard-lifecycle-event-2"
    assert row.target_event_id == "dashboard-lifecycle-event-1"
  end

  test "resolution builds a resolution row from lifecycle events" do
    row = ComparisonReviewActivityRow.resolution(comparison_review_resolution_event())

    assert row == %{
             render?: true,
             event_id: "dashboard-lifecycle-event-2",
             result_event_id: "dashboard-lifecycle-event-2",
             target_event_id: "dashboard-lifecycle-event-2",
             source_request_event_id: "dashboard-lifecycle-event-1",
             disposition: "review_completed",
             resolution_reason: "Reviewed by mission analyst",
             selected_placement_id: "placement-1",
             affected_placements_attr: "placement-1",
             affected_placements_text: "placement-1",
             workflow_intent_kind: "-",
             workflow_intent_action: "-",
             workflow_selection_count_text: "-",
             source_open_count_text: "-",
             source_open_placements_attr: ""
           }
  end

  test "resolution row carries bulk workflow intent audit metadata" do
    resolution =
      comparison_review_resolution_event(
        payload: %{
          "workflow_intent" => %{
            "kind" => "bulk_correction_authority_review",
            "action" => "request_comparison_review",
            "selection_count" => 2
          },
          "source_open_count" => 2,
          "source_open_placement_ids" => ["placement-1", "placement-2"]
        }
      )

    row = ComparisonReviewActivityRow.resolution(resolution)

    assert row.workflow_intent_kind == "bulk_correction_authority_review"
    assert row.workflow_intent_action == "request_comparison_review"
    assert row.workflow_selection_count_text == "2"
    assert row.source_open_count_text == "2"
    assert row.source_open_placements_attr == "placement-1,placement-2"
  end

  test "non comparison-review events produce non-renderable rows" do
    event = lifecycle_event("dashboard-lifecycle-event-3", :published)

    assert ComparisonReviewActivityRow.request(event, [event], nil) == %{render?: false}
    assert ComparisonReviewActivityRow.resolution(event) == %{render?: false}
  end
end
