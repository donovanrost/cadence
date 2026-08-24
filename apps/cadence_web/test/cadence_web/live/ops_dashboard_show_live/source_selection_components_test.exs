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

    vue = LiveVue.Test.get_vue(html, id: "dashboard-source-selection-component")

    assert vue.component == "SourceSelection"
    assert vue.id == "dashboard-source-selection-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]
    assert presentation["id"] == "dashboard-source-selection"

    assert presentation["class"] ==
             "shrink-0 flex flex-wrap items-center gap-2 px-2 py-1 border-b border-base-300/60 bg-base-200/30 text-xs"

    assert presentation["label"] == %{"class" => "hud-label", "text" => "Source selection"}

    assert presentation["attrs"]["data-source-selection-requests"] == "1"
    assert presentation["attrs"]["data-source-selection-request-ids"] == "req-telemetry"
    assert presentation["attrs"]["data-source-selection-bindings"] == "secondary-flight"

    assert presentation["attrs"]["data-source-selection-data-sources"] ==
             "secondary-questdb"

    assert presentation["attrs"]["data-source-selection-rejected"] == "1"

    assert presentation["attrs"] == %{
             "data-source-selection-bindings" => "secondary-flight",
             "data-source-selection-data-sources" => "secondary-questdb",
             "data-source-selection-rejected" => "1",
             "data-source-selection-request-ids" => "req-telemetry",
             "data-source-selection-requests" => "1"
           }

    [selection] = presentation["selections"]
    assert selection["overlay"]["id"] == "source-selection-req-telemetry"
    assert selection["overlay"]["trigger_id"] == "source-selection-req-telemetry-trigger"
    assert selection["overlay"]["panel_id"] == "source-selection-req-telemetry-panel"
    assert selection["overlay"]["label"] == "Telemetry source selection"
    assert selection["overlay"]["attrs"]["data-source-selection-detail"] == "req-telemetry"
    assert selection["overlay"]["class"] == "cadence-overlay"
    assert selection["overlay"]["trigger_class"] == "cadence-overlay-trigger"

    assert selection["overlay"]["panel_class"] ==
             "cadence-overlay-panel cadence-popover-panel"

    assert selection["overlay"]["placement"] == "bottom-end"
    assert selection["overlay"]["width"] == "lg"
    assert selection["badge"]["attrs"]["data-source-selection-state"] == "selected"

    assert selection["badge"]["class"] ==
             "badge badge-xs cursor-pointer gap-1 badge-success badge-outline"

    assert selection["badge"]["title"] ==
             "Telemetry | binding: secondary-flight | source: secondary-questdb | state: selected | candidates: 1/2 eligible"

    assert selection["badge"]["label"] == "Telemetry"

    assert selection["badge"]["icon"] == %{
             "class" => "h-3 w-3",
             "name" => "hero-adjustments-horizontal"
           }

    assert selection["badge"]["attrs"] == %{
             "data-source-selection" => "req-telemetry",
             "data-source-selection-binding" => "secondary-flight",
             "data-source-selection-candidates" => "2",
             "data-source-selection-data-source" => "secondary-questdb",
             "data-source-selection-eligible" => "1",
             "data-source-selection-logical-source" => "Telemetry",
             "data-source-selection-rejected" => "1",
             "data-source-selection-state" => "selected"
           }

    assert Enum.map(selection["details"]["facts"], &Map.take(&1, ["label", "value"])) == [
             %{"label" => "Strategy", "value" => "current_binding"},
             %{"label" => "Selected binding", "value" => "secondary-flight"},
             %{"label" => "Selected source", "value" => "secondary-questdb"},
             %{"label" => "Dataset", "value" => "flight"},
             %{"label" => "Requested realm", "value" => "flight"},
             %{"label" => "Candidates", "value" => "1/2 eligible"}
           ]

    [primary, secondary] = selection["candidates"]

    assert Enum.map(selection["candidates"], & &1["key"]) == [
             "source-selection-candidate-0",
             "source-selection-candidate-1"
           ]

    assert primary["attrs"]["data-source-selection-candidate"] == "primary-flight"
    assert primary["attrs"]["data-source-selection-candidate-source"] == "primary-questdb"
    assert primary["attrs"]["data-source-selection-candidate-decision"] == "rejected"
    assert primary["attrs"]["data-source-selection-candidate-reasons"] == "source_unavailable"

    assert primary["attrs"]["data-source-selection-candidate-requested-products"] ==
             "link_rf_metric_history"

    assert primary["attrs"]["data-source-selection-candidate-supported-products"] ==
             "transport_bitrate_history"

    assert primary["attrs"]["data-source-selection-candidate-missing-products"] ==
             "link_rf_metric_history"

    assert primary["product_summary"]["attrs"][
             "data-source-selection-candidate-product-summary"
           ] == "primary-flight"

    assert primary["product_summary"]["text"] =~ "missing products=link_rf_metric_history"

    assert primary["attrs"]["data-source-selection-candidate-window"] ==
             "2026-06-21T20:00:00Z -> 2026-06-21T21:00:00Z"

    assert primary["window"]["text"] =~
             "2026-06-21T20:00:00Z -> 2026-06-21T21:00:00Z"

    assert primary["attrs"]["data-source-selection-candidate-action"] == "source_inventory"

    assert primary["attrs"]["data-source-selection-candidate-action-query"] ==
             "data_source_id=primary-questdb&logical_source=telemetry&realm=flight&source_binding_id=primary-flight"

    assert primary["attrs"] == %{
             "data-source-selection-candidate" => "primary-flight",
             "data-source-selection-candidate-action" => "source_inventory",
             "data-source-selection-candidate-action-query" =>
               "data_source_id=primary-questdb&logical_source=telemetry&realm=flight&source_binding_id=primary-flight",
             "data-source-selection-candidate-decision" => "rejected",
             "data-source-selection-candidate-freshness" => "fresh",
             "data-source-selection-candidate-health" => "unavailable",
             "data-source-selection-candidate-missing-products" => "link_rf_metric_history",
             "data-source-selection-candidate-reasons" => "source_unavailable",
             "data-source-selection-candidate-requested-products" => "link_rf_metric_history",
             "data-source-selection-candidate-source" => "primary-questdb",
             "data-source-selection-candidate-supported-products" => "transport_bitrate_history",
             "data-source-selection-candidate-window" =>
               "2026-06-21T20:00:00Z -> 2026-06-21T21:00:00Z"
           }

    assert primary["action"]["attrs"]["data-source-selection-candidate-open"] ==
             "primary-flight"

    assert primary["action"]["attrs"] == %{
             "data-phx-link" => "redirect",
             "data-phx-link-state" => "push",
             "data-source-selection-candidate-open" => "primary-flight"
           }

    assert primary["action"]["class"] == "btn btn-ghost btn-xs gap-1"
    assert primary["action"]["title"] == "Open source inventory"
    assert primary["action"]["label"] == "Open"

    assert primary["action"]["icon"] == %{
             "class" => "h-3.5 w-3.5",
             "name" => "hero-arrow-top-right-on-square"
           }

    primary_href = primary["action"]["href"]

    assert primary_href =~ "/missions/mission-1/ops/data-sources?"
    assert primary_href =~ "data_source_id=primary-questdb"
    assert primary_href =~ "source_binding_id=primary-flight"

    assert secondary["attrs"]["data-source-selection-candidate"] == "secondary-flight"
    assert secondary["attrs"]["data-source-selection-candidate-decision"] == "selected"
    assert secondary["decision"]["class"] == "badge badge-xs badge-success"

    assert secondary["attrs"] == %{
             "data-source-selection-candidate" => "secondary-flight",
             "data-source-selection-candidate-action" => "source_inventory",
             "data-source-selection-candidate-action-query" =>
               "data_source_id=secondary-questdb&logical_source=telemetry&realm=flight&source_binding_id=secondary-flight",
             "data-source-selection-candidate-decision" => "selected",
             "data-source-selection-candidate-freshness" => "",
             "data-source-selection-candidate-health" => "",
             "data-source-selection-candidate-missing-products" => "",
             "data-source-selection-candidate-reasons" => "",
             "data-source-selection-candidate-requested-products" => "",
             "data-source-selection-candidate-source" => "secondary-questdb",
             "data-source-selection-candidate-supported-products" => "",
             "data-source-selection-candidate-window" => ""
           }
  end

  test "source selection strip renders no island for an empty selection list" do
    html =
      render_component(&SourceSelectionComponents.source_selection_strip/1,
        mission_id: "mission-1",
        selections: []
      )

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-source-selection-component")
             |> LazyHTML.attribute("id")
  end
end
