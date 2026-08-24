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

    presentation = request_presentation(html, row.event_id)
    root_attrs = presentation["root"]["attrs"]

    assert "dashboard-lifecycle-event-1" =
             root_attrs["data-dashboard-comparison-review-request"]

    assert "dashboard-lifecycle-event-1" =
             root_attrs["data-dashboard-comparison-review-target-event-id"]

    assert "open" = root_attrs["data-dashboard-comparison-review-status"]

    assert "placement-1,placement-2" =
             root_attrs["data-dashboard-comparison-review-placements"]

    assert ["true", "false"] =
             presentation
             |> detail_row("placements")
             |> Map.fetch!("links")
             |> Enum.map(& &1["attrs"]["data-dashboard-review-placement-selected"])

    resolve_form = presentation["actions"]["resolve_form"]

    assert "dashboard-lifecycle-event-1" =
             resolve_form["attrs"]["data-dashboard-comparison-review-resolve-form"]

    assert "placement-1,placement-2" =
             hidden_value(resolve_form, "review[affected_placement_ids]")
  end

  test "request_details renders resolved review state without a form" do
    request = comparison_review_request_event()
    resolution = comparison_review_resolution_event()
    row = ComparisonReviewActivityRow.request(request, [request, resolution], nil)

    html =
      render_component(&ComparisonReviewActivity.request_details/1,
        row: row
      )

    presentation = request_presentation(html, row.event_id)
    root_attrs = presentation["root"]["attrs"]

    assert "resolved" = root_attrs["data-dashboard-comparison-review-status"]

    assert "dashboard-lifecycle-event-2" =
             root_attrs["data-dashboard-comparison-review-resolution-event"]

    assert "dashboard-lifecycle-event-2" =
             root_attrs["data-dashboard-comparison-review-result-event-id"]

    assert "dashboard-lifecycle-event-1" =
             presentation["actions"]["resolved_badge"]["attrs"][
               "data-dashboard-comparison-review-resolved"
             ]

    assert nil == presentation["actions"]["resolve_form"]
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

    presentation = resolution_presentation(html, row.event_id)
    root_attrs = presentation["root"]["attrs"]

    assert detail_value(presentation, "bulk-action") == "1 actionable / 1 skipped"

    assert "dashboard-lifecycle-event-1" =
             root_attrs["data-dashboard-comparison-review-resolution-source"]

    assert "dashboard-lifecycle-event-2" =
             root_attrs["data-dashboard-comparison-review-resolution-result-event-id"]

    assert "dashboard-lifecycle-event-2" =
             root_attrs["data-dashboard-comparison-review-resolution-target-event-id"]

    assert "review_completed" =
             root_attrs["data-dashboard-comparison-review-resolution-disposition"]

    assert "placement-1" =
             root_attrs["data-dashboard-comparison-review-resolution-selected-placement"]

    assert "placement-1" =
             root_attrs["data-dashboard-comparison-review-resolution-affected-placements"]

    assert "2" = root_attrs["data-dashboard-comparison-review-resolution-source-open-count"]

    assert "transport" =
             root_attrs["data-dashboard-comparison-review-resolution-source-scope-kind"]

    assert "transport-alpha,transport-beta" =
             root_attrs["data-dashboard-comparison-review-resolution-source-scope-ids"]

    assert "contact-alpha,contact-beta" =
             root_attrs["data-dashboard-comparison-review-resolution-source-contact-ids"]

    assert "transport-alpha" =
             root_attrs["data-dashboard-comparison-review-resolution-source-resource-ids"]

    assert "transport-alpha" =
             root_attrs["data-dashboard-comparison-review-resolution-source-transport-ids"]

    assert "endpoint-alpha" =
             root_attrs["data-dashboard-comparison-review-resolution-source-endpoint-ids"]

    assert "dss-14" =
             root_attrs["data-dashboard-comparison-review-resolution-source-ground-station-ids"]

    assert "link-alpha" =
             root_attrs["data-dashboard-comparison-review-resolution-source-scope-link-ids"]

    assert "1" =
             root_attrs["data-dashboard-comparison-review-resolution-source-actionable-count"]

    assert "placement-1" =
             root_attrs[
               "data-dashboard-comparison-review-resolution-source-actionable-placements"
             ]

    assert "1" =
             root_attrs["data-dashboard-comparison-review-resolution-source-skipped-count"]

    assert "placement-2" =
             root_attrs["data-dashboard-comparison-review-resolution-source-skipped-placements"]

    assert "missing_observation_identity" =
             root_attrs["data-dashboard-comparison-review-resolution-source-skipped-reasons"]

    assert detail_row(presentation, "scope")["label"] == "Scope"
    assert detail_value(presentation, "scope-ids") == "transport-alpha,transport-beta"
    assert detail_row(presentation, "contacts")["label"] == "Contacts"
    assert detail_value(presentation, "contacts") == "contact-alpha,contact-beta"
    assert detail_row(presentation, "source-endpoints")["label"] == "Source endpoints"
    assert detail_value(presentation, "source-endpoints") == "endpoint-alpha"
  end

  defp request_presentation(rendered, event_id) do
    presentation(rendered, "request", event_id)
  end

  defp resolution_presentation(rendered, event_id) do
    presentation(rendered, "resolution", event_id)
  end

  defp presentation(rendered, kind, event_id) do
    vue =
      LiveVue.Test.get_vue(rendered,
        id: "dashboard-comparison-review-#{kind}-#{event_id}-component"
      )

    assert Map.take(vue, [:component, :ssr, :class, :handlers]) == %{
             component: "ComparisonReviewActivityDetails",
             ssr: false,
             class: "contents",
             handlers: %{}
           }

    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.props["presentation"]["kind"] == kind
    vue.props["presentation"]
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
