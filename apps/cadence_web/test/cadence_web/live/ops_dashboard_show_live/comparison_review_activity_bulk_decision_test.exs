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

    presentation = request_presentation(html, row.event_id)
    bulk_form = presentation["actions"]["bulk_form"]
    [finding] = presentation["findings"]["items"]

    assert "dashboard-lifecycle-event-1" =
             bulk_form["attrs"]["data-dashboard-comparison-review-bulk-decision-form"]

    assert "1" = bulk_form["attrs"]["data-dashboard-comparison-review-bulk-decision-count"]

    assert "placement-1" =
             bulk_form["attrs"]["data-dashboard-comparison-review-bulk-decision-placements"]

    assert "mark_conflict" =
             bulk_form["button"]["attrs"][
               "data-dashboard-comparison-review-bulk-decision-kind"
             ]

    assert "identity-1" =
             finding["attrs"][
               "data-dashboard-comparison-review-finding-observation-identity"
             ]

    assert "transport" =
             finding["attrs"]["data-dashboard-comparison-review-finding-scope-kind"]

    assert "transport-alpha" =
             finding["attrs"]["data-dashboard-comparison-review-finding-scope-id"]

    assert "transport-alpha,transport-beta" =
             finding["attrs"]["data-dashboard-comparison-review-finding-scope-ids"]

    assert "contact-alpha,contact-beta" =
             finding["attrs"]["data-dashboard-comparison-review-finding-contact-ids"]

    assert "endpoint-alpha" =
             finding["attrs"][
               "data-dashboard-comparison-review-finding-source-endpoint-id"
             ]
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

    presentation = request_presentation(html, row.event_id)
    bulk_form = presentation["actions"]["bulk_form"]
    root_attrs = presentation["root"]["attrs"]
    skipped_badge = presentation["actions"]["skipped_badge"]
    findings = presentation["findings"]["items"]

    assert "dashboard-lifecycle-event-1" =
             bulk_form["attrs"]["data-dashboard-comparison-review-bulk-decision-form"]

    assert "1" = bulk_form["attrs"]["data-dashboard-comparison-review-bulk-decision-count"]

    assert "placement-1" =
             bulk_form["attrs"]["data-dashboard-comparison-review-bulk-decision-placements"]

    assert "1" =
             root_attrs["data-dashboard-comparison-review-bulk-decision-skipped-count"]

    assert "placement-2" =
             root_attrs["data-dashboard-comparison-review-bulk-decision-skipped-placements"]

    assert "missing_observation_identity" =
             root_attrs["data-dashboard-comparison-review-bulk-decision-skipped-reasons"]

    assert "1" =
             skipped_badge["attrs"][
               "data-dashboard-comparison-review-bulk-decision-skipped-count"
             ]

    assert ["included", "skipped"] =
             Enum.map(
               findings,
               & &1["attrs"]["data-dashboard-comparison-review-finding-bulk-decision"]
             )

    skipped_finding = Enum.find(findings, &(&1["key"] == "placement-2"))

    assert "missing_observation_identity" =
             skipped_finding["attrs"][
               "data-dashboard-comparison-review-finding-bulk-decision-reason"
             ]

    assert "Skipped: missing observation identity" =
             skipped_finding["attrs"][
               "data-dashboard-comparison-review-finding-bulk-decision-label"
             ]

    assert nil == presentation["actions"]["unavailable_badge"]
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

    presentation = request_presentation(html, row.event_id)
    unavailable_badge = presentation["actions"]["unavailable_badge"]

    assert nil == presentation["actions"]["bulk_form"]

    assert "dashboard-lifecycle-event-1" =
             unavailable_badge["attrs"][
               "data-dashboard-comparison-review-bulk-decision-unavailable"
             ]

    assert "missing_source_context" =
             unavailable_badge["attrs"][
               "data-dashboard-comparison-review-bulk-decision-unavailable-reason"
             ]

    assert "1" =
             unavailable_badge["attrs"][
               "data-dashboard-comparison-review-bulk-decision-unavailable-count"
             ]

    assert "placement-1" =
             unavailable_badge["attrs"][
               "data-dashboard-comparison-review-bulk-decision-unavailable-placements"
             ]
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

    presentation = request_presentation(html, row.event_id)
    unavailable_badge = presentation["actions"]["unavailable_badge"]

    assert nil == presentation["actions"]["bulk_form"]

    assert "no_actionable_findings" =
             unavailable_badge["attrs"][
               "data-dashboard-comparison-review-bulk-decision-unavailable-reason"
             ]

    assert "0" =
             unavailable_badge["attrs"][
               "data-dashboard-comparison-review-bulk-decision-unavailable-count"
             ]

    assert "" =
             unavailable_badge["attrs"][
               "data-dashboard-comparison-review-bulk-decision-unavailable-placements"
             ]
  end

  defp request_presentation(rendered, event_id) do
    vue =
      LiveVue.Test.get_vue(rendered,
        id: "dashboard-comparison-review-request-#{event_id}-component"
      )

    assert Map.take(vue, [:component, :ssr, :class, :handlers]) == %{
             component: "ComparisonReviewActivityDetails",
             ssr: false,
             class: "contents",
             handlers: %{}
           }

    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.props["presentation"]["kind"] == "request"
    vue.props["presentation"]
  end
end
