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
    row =
      ComparisonReviewActivityRow.resolution(
        comparison_review_resolution_event(
          payload: %{
            "workflow_intent" => %{
              "kind" => "bulk_correction_authority_review",
              "action" => "request_comparison_review",
              "selection_count" => 2
            },
            "source_open_count" => 2,
            "source_open_placement_ids" => ["placement-1", "placement-2"],
            "source_scope_kind" => "transport",
            "source_scope_ids" => ["transport-alpha", "transport-beta"],
            "source_contact_ids" => ["contact-alpha", "contact-beta"],
            "source_resource_ids" => ["transport-alpha"],
            "source_transport_ids" => ["transport-alpha"],
            "source_endpoint_ids" => ["endpoint-alpha"],
            "source_ground_station_ids" => ["dss-14"],
            "source_scope_link_ids" => ["link-alpha"],
            "source_bulk_decision_actionable_count" => 1,
            "source_bulk_decision_actionable_placement_ids" => ["placement-1"],
            "source_bulk_decision_skipped_count" => 1,
            "source_bulk_decision_skipped_placement_ids" => ["placement-2"],
            "source_bulk_decision_skipped_reasons" => ["missing_observation_identity"]
          }
        )
      )

    html =
      render_component(&ComparisonReviewActivity.resolution_details/1,
        row: row
      )

    document = LazyHTML.from_fragment(html)

    assert html =~ "1 actionable / 1 skipped"

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

    assert ["2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-source-open-count"
             )

    assert ["transport"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-source-scope-kind"
             )

    assert ["transport-alpha,transport-beta"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-source-scope-ids")

    assert ["contact-alpha,contact-beta"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-source-contact-ids"
             )

    assert ["transport-alpha"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-source-resource-ids"
             )

    assert ["transport-alpha"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-source-transport-ids"
             )

    assert ["endpoint-alpha"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-source-endpoint-ids"
             )

    assert ["dss-14"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-source-ground-station-ids"
             )

    assert ["link-alpha"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-source-scope-link-ids"
             )

    assert ["1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-source-actionable-count"
             )

    assert ["placement-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-source-actionable-placements"
             )

    assert ["1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-source-skipped-count"
             )

    assert ["placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-source-skipped-placements"
             )

    assert ["missing_observation_identity"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-source-skipped-reasons"
             )

    resolution_text =
      document
      |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
      |> LazyHTML.text()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    assert resolution_text =~ "Scope"
    assert resolution_text =~ "transport-alpha,transport-beta"
    assert resolution_text =~ "Contacts"
    assert resolution_text =~ "contact-alpha,contact-beta"
    assert resolution_text =~ "Source endpoints"
    assert resolution_text =~ "endpoint-alpha"
  end
end
