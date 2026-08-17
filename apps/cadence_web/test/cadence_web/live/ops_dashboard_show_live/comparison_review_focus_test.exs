defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewFocusTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewFocus

  test "finding summaries include web placement links" do
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
end
