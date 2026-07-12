defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewFocusTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewFocus

  test "open_summary keeps unresolved request ids and placement ids together" do
    events = [
      comparison_review_request_event(
        event_id: "request-1",
        payload: %{
          "open_placement_ids" => ["placement-1", "placement-2"],
          "open_count" => 2
        }
      ),
      comparison_review_request_event(
        event_id: "request-2",
        payload: %{
          open_findings: %{
            findings: [
              %{placement_id: "placement-3", decision_status: "unhandled"}
            ]
          }
        }
      ),
      comparison_review_resolution_event(
        event_id: "resolution-2",
        source_request_event_id: "request-2"
      )
    ]

    summary = ComparisonReviewFocus.open_summary(events)

    assert summary.count == 1
    assert summary.count_text == "1"
    assert summary.requests == [Enum.at(events, 0)]
    assert summary.request_ids == ["request-1"]
    assert summary.request_ids_attr == "request-1"
    assert summary.placement_ids == ["placement-1", "placement-2"]
    assert summary.placements_attr == "placement-1,placement-2"
    assert summary.scope_kind == nil
    assert summary.scope_kinds == []
    assert summary.scope_kinds_attr == ""
    assert summary.scope_ids == []
    assert summary.scope_ids_attr == ""
    assert summary.contact_ids == []
    assert summary.contact_ids_attr == ""
    assert summary.resource_ids == []
    assert summary.resource_ids_attr == ""
    assert summary.transport_ids == []
    assert summary.transport_ids_attr == ""
    assert summary.source_endpoint_ids == []
    assert summary.source_endpoint_ids_attr == ""
    assert summary.ground_station_ids == []
    assert summary.ground_station_ids_attr == ""
    assert summary.scope_link_ids == []
    assert summary.scope_link_ids_attr == ""
  end

  test "request_summary normalizes request payload details" do
    event =
      comparison_review_request_event(
        event_id: "request-1",
        payload: %{
          schema: "dashboard_comparison_review_request.v1",
          request_kind: "comparison_open_findings_review",
          open_count: "bad-count",
          open_findings: %{
            findings: [
              %{placement_id: "placement-1", title: "Voltage", decision_status: "unhandled"},
              %{"placement_id" => "placement-2", "state" => "missing"}
            ]
          }
        }
      )

    summary = ComparisonReviewFocus.request_summary(event, [])

    assert summary.event_id == "request-1"
    assert summary.schema == "dashboard_comparison_review_request.v1"
    assert summary.kind == "comparison_open_findings_review"
    assert summary.status == "open"
    assert summary.open_count == 2
    assert summary.open_count_text == "2"
    assert summary.placement_ids == ["placement-1", "placement-2"]
    assert summary.placements_attr == "placement-1,placement-2"

    assert Enum.map(summary.findings, &ComparisonReviewFocus.finding_summary/1) == [
             %{
               placement_id: "placement-1",
               title: "Voltage",
               state: "",
               decision_status: "unhandled",
               placement_href: "#widget-placement-1"
             },
             %{
               placement_id: "placement-2",
               title: "placement-2",
               state: "missing",
               decision_status: "",
               placement_href: "#widget-placement-2"
             }
           ]
  end

  test "request_summary links a request to its resolution" do
    request = comparison_review_request_event(event_id: "request-1")

    resolution =
      comparison_review_resolution_event(
        event_id: "resolution-1",
        source_request_event_id: "request-1"
      )

    summary = ComparisonReviewFocus.request_summary(request, [request, resolution])

    assert summary.status == "resolved"
    assert summary.resolved? == true
    assert summary.resolution_event_id == "resolution-1"
  end

  test "resolution_summary normalizes placement context" do
    event =
      comparison_review_resolution_event(
        event_id: "resolution-1",
        source_request_event_id: "request-1",
        payload: %{
          "disposition" => "review_completed",
          "resolution_reason" => "Reviewed by ops",
          "selected_placement_id" => "placement-1",
          "affected_placement_ids" => ["placement-1", nil, ""]
        }
      )

    assert %{
             source_request_event_id: "request-1",
             disposition: "review_completed",
             resolution_reason: "Reviewed by ops",
             selected_placement_id: "placement-1",
             affected_placement_ids: ["placement-1"],
             affected_placements_attr: "placement-1",
             affected_placements_text: "placement-1"
           } = ComparisonReviewFocus.resolution_summary(event)
  end
end
