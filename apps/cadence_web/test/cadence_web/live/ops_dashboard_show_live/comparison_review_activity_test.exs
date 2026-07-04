defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewActivityTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import CadenceWeb.DashboardReviewFixtures

  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewActivity
  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewActivityRow

  test "request_details renders review placement links and resolution form" do
    event = comparison_review_request_event()
    row = ComparisonReviewActivityRow.request(event, [event], "placement-1")

    html =
      render_component(&ComparisonReviewActivity.request_details/1,
        row: row
      )

    document = LazyHTML.from_fragment(html)

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-request")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-target-event-id")

    assert ["open"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-status")

    assert ["placement-1,placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-placements")

    assert ["true", "false"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-placement-link]")
             |> LazyHTML.attribute("data-dashboard-review-placement-selected")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolve-form]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolve-form")

    assert ["placement-1,placement-2"] =
             document
             |> LazyHTML.query(~s(input[name="review[affected_placement_ids]"]))
             |> LazyHTML.attribute("value")
  end

  test "request_details renders bulk decision action for actionable review findings" do
    event =
      comparison_review_request_event(
        placement_ids: ["placement-1"],
        findings: [
          %{
            "placement_id" => "placement-1",
            "title" => "Bus voltage",
            "state" => "increased",
            "decision_status" => "unhandled",
            "observation_identity_id" => "identity-1",
            "primary_data_link" => %{
              "context" => %{
                "data" => %{
                  "realm" => "flight",
                  "data_source_id" => "managed_questdb_primary",
                  "source_binding_id" => "default_flight_telemetry"
                }
              }
            }
          }
        ]
      )

    row = ComparisonReviewActivityRow.request(event, [event], nil)

    html =
      render_component(&ComparisonReviewActivity.request_details/1,
        row: row
      )

    document = LazyHTML.from_fragment(html)

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision-form]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-bulk-decision-form")

    assert ["1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision-form]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-bulk-decision-count")

    assert ["placement-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision-form]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-bulk-decision-placements")

    assert ["mark_conflict"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-bulk-decision-kind")

    assert ["identity-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-finding-observation-identity"
             )
  end

  test "request_details renders resolved review state without a form" do
    request = comparison_review_request_event()
    resolution = comparison_review_resolution_event()
    row = ComparisonReviewActivityRow.request(request, [request, resolution], nil)

    html =
      render_component(&ComparisonReviewActivity.request_details/1,
        row: row
      )

    document = LazyHTML.from_fragment(html)

    assert ["resolved"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-status")

    assert ["dashboard-lifecycle-event-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-event")

    assert ["dashboard-lifecycle-event-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-result-event-id")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolved]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolved")

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolve-form]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolve-form")
  end

  test "resolution_details renders resolution context" do
    row = ComparisonReviewActivityRow.resolution(comparison_review_resolution_event())

    html =
      render_component(&ComparisonReviewActivity.resolution_details/1,
        row: row
      )

    document = LazyHTML.from_fragment(html)

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-source")

    assert ["dashboard-lifecycle-event-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-result-event-id")

    assert ["dashboard-lifecycle-event-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-target-event-id")

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

    assert ["placement-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-affected-placements"
             )
  end
end
