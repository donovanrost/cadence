defmodule CadenceWeb.OpsDashboardShowLive.SourceSelectionComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.SourceSelectionComponents

  test "source selection strip exposes selected and skipped source candidates" do
    html =
      render_component(&SourceSelectionComponents.source_selection_strip/1,
        mission_id: "mission-1",
        selections: [
          %{
            request_id: "req-telemetry",
            logical_source_text: "Telemetry",
            strategy_text: "current_binding",
            selected_binding_id: "secondary-flight",
            selected_data_source_id: "secondary-questdb",
            selected_dataset: "flight",
            requested_realm: "flight",
            candidate_count: 2,
            eligible_candidate_count: 1,
            rejected_candidate_count: 1,
            state: :selected,
            state_text: "selected",
            candidates: [
              %{
                binding_id: "primary-flight",
                data_source_id: "primary-questdb",
                decision: :rejected,
                decision_text: "rejected",
                reasons_text: "source_unavailable",
                requested_products_text: "link_rf_metric_history",
                supported_products_text: "transport_bitrate_history",
                missing_products_text: "link_rf_metric_history",
                started_at_text: "2026-06-21T20:00:00Z",
                ended_at_text: "2026-06-21T21:00:00Z",
                source_health_text: "unavailable",
                source_health_freshness_text: "fresh",
                inventory_query: %{
                  "data_source_id" => "primary-questdb",
                  "logical_source" => "telemetry",
                  "realm" => "flight",
                  "source_binding_id" => "primary-flight"
                },
                inventory_action_label: "Open source inventory"
              },
              %{
                binding_id: "secondary-flight",
                data_source_id: "secondary-questdb",
                decision: :selected,
                decision_text: "selected",
                reasons_text: "",
                source_health_text: "",
                source_health_freshness_text: "",
                inventory_query: %{
                  "data_source_id" => "secondary-questdb",
                  "logical_source" => "telemetry",
                  "realm" => "flight",
                  "source_binding_id" => "secondary-flight"
                },
                inventory_action_label: "Open source inventory"
              }
            ]
          }
        ]
      )

    document = LazyHTML.from_fragment(html)

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-source-selection")
             |> LazyHTML.attribute("data-source-selection-requests")

    assert ["req-telemetry"] =
             document
             |> LazyHTML.query("#dashboard-source-selection")
             |> LazyHTML.attribute("data-source-selection-request-ids")

    assert ["secondary-flight"] =
             document
             |> LazyHTML.query("#dashboard-source-selection")
             |> LazyHTML.attribute("data-source-selection-bindings")

    assert ["secondary-questdb"] =
             document
             |> LazyHTML.query("#dashboard-source-selection")
             |> LazyHTML.attribute("data-source-selection-data-sources")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-source-selection")
             |> LazyHTML.attribute("data-source-selection-rejected")

    assert ["selected"] =
             document
             |> LazyHTML.query(~s([data-source-selection="req-telemetry"]))
             |> LazyHTML.attribute("data-source-selection-state")

    assert ["primary-questdb"] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-source")

    assert ["rejected"] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-decision")

    assert ["source_unavailable"] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-reasons")

    assert ["link_rf_metric_history"] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-requested-products")

    assert ["transport_bitrate_history"] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-supported-products")

    assert ["link_rf_metric_history"] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-missing-products")

    assert document
           |> LazyHTML.query(
             ~s([data-source-selection-candidate-product-summary="primary-flight"])
           )
           |> LazyHTML.text() =~ "missing products=link_rf_metric_history"

    assert ["2026-06-21T20:00:00Z -> 2026-06-21T21:00:00Z"] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-window")

    assert document
           |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
           |> LazyHTML.text() =~ "2026-06-21T20:00:00Z -> 2026-06-21T21:00:00Z"

    assert ["source_inventory"] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-action")

    assert [
             "data_source_id=primary-questdb&logical_source=telemetry&realm=flight&source_binding_id=primary-flight"
           ] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-action-query")

    assert [primary_href] =
             document
             |> LazyHTML.query(~s(a[data-source-selection-candidate-open="primary-flight"]))
             |> LazyHTML.attribute("href")

    assert primary_href =~ "/missions/mission-1/ops/data-sources?"
    assert primary_href =~ "data_source_id=primary-questdb"
    assert primary_href =~ "source_binding_id=primary-flight"

    assert ["selected"] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="secondary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-decision")
  end
end
