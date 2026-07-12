defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewActivityBulkDecisionTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest

  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewActivity
  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewActivityRow

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
            "scope_kind" => "transport",
            "scope_id" => "transport-alpha",
            "scope_ids" => ["transport-alpha", "transport-beta"],
            "resource_id" => "transport-alpha",
            "contact_id" => "contact-alpha",
            "contact_ids" => ["contact-alpha", "contact-beta"],
            "transport_id" => "transport-alpha",
            "source_endpoint_id" => "endpoint-alpha",
            "ground_station_id" => "dss-14",
            "scope_link_id" => "link-alpha",
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

    assert ["transport"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-finding-scope-kind")

    assert ["transport-alpha"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-finding-scope-id")

    assert ["transport-alpha,transport-beta"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-finding-scope-ids")

    assert ["contact-alpha,contact-beta"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-finding-contact-ids")

    assert ["endpoint-alpha"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-finding-source-endpoint-id")
  end

  test "request_details scopes bulk decision action to actionable review findings" do
    source_context = %{
      "realm" => "flight",
      "data_source_id" => "managed_questdb_primary",
      "source_binding_id" => "default_flight_telemetry"
    }

    event =
      comparison_review_request_event(
        placement_ids: ["placement-1", "placement-2"],
        findings: [
          %{
            "placement_id" => "placement-1",
            "title" => "Bus voltage",
            "state" => "increased",
            "decision_status" => "unhandled",
            "observation_identity_id" => "identity-1",
            "primary_data_link" => %{"context" => %{"data" => source_context}}
          },
          %{
            "placement_id" => "placement-2",
            "title" => "Missing identity",
            "state" => "missing",
            "decision_status" => "unhandled",
            "primary_data_link" => %{"context" => %{"data" => source_context}}
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

    assert ["1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-bulk-decision-skipped-count")

    assert ["placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-bulk-decision-skipped-placements"
             )

    assert ["missing_observation_identity"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-bulk-decision-skipped-reasons"
             )

    assert ["1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision-skipped]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-bulk-decision-skipped-count")

    assert ["included", "skipped"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-finding-bulk-decision")

    assert ["missing_observation_identity"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-review-finding="placement-2"]))
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-finding-bulk-decision-reason"
             )

    assert ["Skipped: missing observation identity"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-review-finding="placement-2"]))
             |> LazyHTML.attribute("data-dashboard-comparison-review-finding-bulk-decision-label")

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision-unavailable]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-bulk-decision-unavailable")
  end

  test "request_details explains unavailable bulk decisions when source context is missing" do
    event =
      comparison_review_request_event(
        placement_ids: ["placement-1"],
        findings: [
          %{
            "placement_id" => "placement-1",
            "title" => "Bus voltage",
            "state" => "increased",
            "decision_status" => "unhandled",
            "observation_identity_id" => "identity-1"
          }
        ]
      )

    row = ComparisonReviewActivityRow.request(event, [event], nil)

    html =
      render_component(&ComparisonReviewActivity.request_details/1,
        row: row
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision-form]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-bulk-decision-form")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision-unavailable]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-bulk-decision-unavailable")

    assert ["missing_source_context"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision-unavailable]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-bulk-decision-unavailable-reason"
             )

    assert ["1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision-unavailable]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-bulk-decision-unavailable-count"
             )

    assert ["placement-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision-unavailable]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-bulk-decision-unavailable-placements"
             )
  end

  test "request_details explains unavailable bulk decisions when no findings are actionable" do
    source_context = %{
      "realm" => "flight",
      "data_source_id" => "managed_questdb_primary",
      "source_binding_id" => "default_flight_telemetry"
    }

    event =
      comparison_review_request_event(
        placement_ids: ["placement-1"],
        findings: [
          %{
            "placement_id" => "placement-1",
            "title" => "Bus voltage",
            "state" => "increased",
            "decision_status" => "unhandled",
            "primary_data_link" => %{"context" => %{"data" => source_context}}
          }
        ]
      )

    row = ComparisonReviewActivityRow.request(event, [event], nil)

    html =
      render_component(&ComparisonReviewActivity.request_details/1,
        row: row
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision-form]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-bulk-decision-form")

    assert ["no_actionable_findings"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision-unavailable]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-bulk-decision-unavailable-reason"
             )

    assert ["0"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision-unavailable]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-bulk-decision-unavailable-count"
             )

    assert [""] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-bulk-decision-unavailable]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-bulk-decision-unavailable-placements"
             )
  end
end
