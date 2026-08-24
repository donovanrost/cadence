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

    presentation = widget_rows_presentation(html)
    row = hd(presentation["rows"])

    [evidence, row_link] =
      row
      |> Map.fetch!("cells")
      |> Enum.find(&(&1["key"] == "actions"))
      |> Map.fetch!("link_menu")
      |> Map.fetch!("items")

    assert row["attrs"]["data-data-table-row"] == "commanding.queue_depth:endpoint-alpha"

    assert row["attrs"]["data-data-table-resource-id"] == "endpoint-alpha"

    assert row["attrs"]["data-data-table-query-scope-kind"] == "source_endpoint"

    assert row["attrs"]["data-data-table-frame-observable-id"] == "commanding.queue_depth"

    assert row["attrs"]["data-data-table-product-family"] == "commanding"

    assert row["attrs"]["data-data-table-supported-capability"] == "command_queue_depth"

    assert row["attrs"]["data-data-table-data-source-id"] ==
             "managed_operational_observables"

    assert row["attrs"]["data-data-table-source-binding-id"] ==
             "default_flight_operational_observables"

    assert row_link["attrs"]["phx-click"] == "open_data_link"

    assert row_link["attrs"]["data-data-table-row-link-target"] == "source endpoint"

    assert row_link["attrs"]["data-data-table-row-link-id"] == "endpoint-alpha"

    assert row_link["attrs"]["phx-value-target"] == "source_endpoint"

    assert row_link["attrs"]["phx-value-target-id"] == "endpoint-alpha"

    assert evidence["attrs"]["phx-click"] == "open_evidence"

    assert evidence["attrs"]["data-data-table-row-evidence-observable"] ==
             "commanding.queue_depth"

    assert evidence["attrs"]["phx-value-kind"] == "frame"

    assert evidence["attrs"]["phx-value-logical-source"] == "operational_observables"

    assert evidence["attrs"]["phx-value-data-source-id"] == "managed_operational_observables"

    assert evidence["attrs"]["phx-value-source-binding-id"] ==
             "default_flight_operational_observables"

    assert evidence["attrs"]["phx-value-scope-kind"] == "source_endpoint"

    assert evidence["attrs"]["phx-value-scope-id"] == "endpoint-alpha"
  end

  defp widget_rows_presentation(html) do
    component_id = "widget-rows-data-table-placement-1-component"
    vue = LiveVue.Test.get_vue(html, id: component_id)
    assert vue.component == "WidgetRows"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.props["presentation"]["kind"] == "data_table"
    assert vue.props["presentation"]["component_id"] == component_id
    vue.props["presentation"]
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
