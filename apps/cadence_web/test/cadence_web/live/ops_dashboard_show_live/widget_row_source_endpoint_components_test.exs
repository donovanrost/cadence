defmodule CadenceWeb.OpsDashboardShowLive.WidgetRowSourceEndpointComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetRowComponents

  test "data_table renders source-endpoint command queue row link and frame evidence attrs" do
    html =
      render_component(&WidgetRowComponents.data_table/1,
        data: %{rows: [source_endpoint_command_queue_row()]},
        widget: widget(),
        placement_id: "placement-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["commanding.queue_depth:endpoint-alpha"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-row")

    assert ["endpoint-alpha"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-resource-id")

    assert ["source_endpoint"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-query-scope-kind")

    assert ["commanding.queue_depth"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-frame-observable-id")

    assert ["commanding"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-product-family")

    assert ["command_queue_depth"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-supported-capability")

    assert ["managed_operational_observables"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-data-source-id")

    assert ["default_flight_operational_observables"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-source-binding-id")

    assert ["open_data_link"] =
             document
             |> LazyHTML.query("[data-data-table-row-link-ref]")
             |> LazyHTML.attribute("phx-click")

    assert ["source endpoint"] =
             document
             |> LazyHTML.query("[data-data-table-row-link-ref]")
             |> LazyHTML.attribute("data-data-table-row-link-target")

    assert ["endpoint-alpha"] =
             document
             |> LazyHTML.query("[data-data-table-row-link-ref]")
             |> LazyHTML.attribute("data-data-table-row-link-id")

    assert ["source_endpoint"] =
             document
             |> LazyHTML.query("[data-data-table-row-link-ref]")
             |> LazyHTML.attribute("phx-value-target")

    assert ["endpoint-alpha"] =
             document
             |> LazyHTML.query("[data-data-table-row-link-ref]")
             |> LazyHTML.attribute("phx-value-target-id")

    assert ["open_evidence"] =
             document
             |> LazyHTML.query("[data-data-table-row-evidence]")
             |> LazyHTML.attribute("phx-click")

    assert ["commanding.queue_depth"] =
             document
             |> LazyHTML.query("[data-data-table-row-evidence]")
             |> LazyHTML.attribute("data-data-table-row-evidence-observable")

    assert ["frame"] =
             document
             |> LazyHTML.query("[data-data-table-row-evidence]")
             |> LazyHTML.attribute("phx-value-kind")

    assert ["operational_observables"] =
             document
             |> LazyHTML.query("[data-data-table-row-evidence]")
             |> LazyHTML.attribute("phx-value-logical-source")

    assert ["managed_operational_observables"] =
             document
             |> LazyHTML.query("[data-data-table-row-evidence]")
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["default_flight_operational_observables"] =
             document
             |> LazyHTML.query("[data-data-table-row-evidence]")
             |> LazyHTML.attribute("phx-value-source-binding-id")

    assert ["source_endpoint"] =
             document
             |> LazyHTML.query("[data-data-table-row-evidence]")
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert ["endpoint-alpha"] =
             document
             |> LazyHTML.query("[data-data-table-row-evidence]")
             |> LazyHTML.attribute("phx-value-scope-id")
  end

  defp widget do
    %{options: %{precision: 2}}
  end

  defp source_endpoint_command_queue_row do
    %{
      observable_id: "commanding.queue_depth:endpoint-alpha",
      label: "source endpoint / endpoint-alpha",
      source: :operational_observables,
      status_policy: :metric_value,
      value: 1,
      unit: "commands",
      quality_state: :good,
      normalized_state: :green,
      receipt_time: ~U[2026-06-17 12:05:00Z],
      resource_id: "endpoint-alpha",
      scope_kind: :source_endpoint,
      source_endpoint_id: "endpoint-alpha",
      frame_observable_id: "commanding.queue_depth",
      product_family: "commanding",
      supported_capability: "command_queue_depth",
      source_request_id: "source-request-1",
      logical_source: "operational_observables",
      realm: "flight",
      data_source_id: "managed_operational_observables",
      source_binding_id: "default_flight_operational_observables",
      dataset: "operational_observables",
      query_scope_kind: "source_endpoint",
      query_scope_id: "endpoint-alpha",
      query_scope_ids: ["endpoint-alpha"],
      links: [
        %{
          link_id: "source_endpoint:endpoint-alpha:ops-latest",
          label: "source endpoint",
          target: :source_endpoint,
          target_text: "source endpoint",
          target_id: "endpoint-alpha",
          context: %{
            data: %{
              realm: :flight,
              data_source_id: "managed_operational_observables",
              source_binding_id: "default_flight_operational_observables"
            },
            scope: %{scope_kind: "source_endpoint", scope_id: "endpoint-alpha"}
          }
        }
      ]
    }
  end
end
