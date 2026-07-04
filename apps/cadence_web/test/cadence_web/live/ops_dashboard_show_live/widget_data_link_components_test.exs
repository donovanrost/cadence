defmodule CadenceWeb.OpsDashboardShowLive.WidgetDataLinkComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetDataLinkComponents

  test "widget_data_link_menu carries source and time context params" do
    html =
      render_component(&WidgetDataLinkComponents.widget_data_link_menu/1,
        links: [presented_link()],
        placement_id: "placement-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["link-1"] =
             document
             |> LazyHTML.query("[data-widget-data-link-ref]")
             |> LazyHTML.attribute("phx-value-link-id")

    assert ["flight"] =
             document
             |> LazyHTML.query("[data-widget-data-link-ref]")
             |> LazyHTML.attribute("phx-value-realm")

    assert ["canonical"] =
             document
             |> LazyHTML.query("[data-widget-data-link-ref]")
             |> LazyHTML.attribute("phx-value-data-view")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query("[data-widget-data-link-ref]")
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query("[data-widget-data-link-ref]")
             |> LazyHTML.attribute("phx-value-source-binding-id")

    assert ["archive"] =
             document
             |> LazyHTML.query("[data-widget-data-link-ref]")
             |> LazyHTML.attribute("phx-value-time-mode")

    assert ["receipt_time"] =
             document
             |> LazyHTML.query("[data-widget-data-link-ref]")
             |> LazyHTML.attribute("phx-value-time-axis")
  end

  test "status_matrix_row_link_menu exposes row frame evidence and row links" do
    html =
      render_component(&WidgetDataLinkComponents.status_matrix_row_link_menu/1,
        row: %{
          observable_id: "battery.voltage",
          frame_observable_id: "ccsds.frame.apid.100",
          query_scope_kind: "transport",
          query_scope_id: "transport-alpha",
          query_scope_ids: ["transport-alpha", "transport-beta"]
        },
        links: [presented_link()],
        placement_id: "placement-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["ccsds.frame.apid.100"] =
             document
             |> LazyHTML.query("[data-status-matrix-row-evidence]")
             |> LazyHTML.attribute("data-status-matrix-row-evidence-observable")

    assert ["open_evidence"] =
             document
             |> LazyHTML.query("[data-status-matrix-row-evidence]")
             |> LazyHTML.attribute("phx-click")

    assert ["transport"] =
             document
             |> LazyHTML.query("[data-status-matrix-row-evidence]")
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert ["transport-alpha"] =
             document
             |> LazyHTML.query("[data-status-matrix-row-evidence]")
             |> LazyHTML.attribute("phx-value-scope-id")

    assert ["transport-alpha,transport-beta"] =
             document
             |> LazyHTML.query("[data-status-matrix-row-evidence]")
             |> LazyHTML.attribute("phx-value-scope-ids")

    assert ["link-1"] =
             document
             |> LazyHTML.query("[data-status-matrix-row-link-ref]")
             |> LazyHTML.attribute("phx-value-link-id")

    assert ["sample-1"] =
             document
             |> LazyHTML.query("[data-status-matrix-row-link-ref]")
             |> LazyHTML.attribute("data-status-matrix-row-link-id")
  end

  test "data_table_row_link_menu exposes query-scoped row frame evidence" do
    html =
      render_component(&WidgetDataLinkComponents.data_table_row_link_menu/1,
        row: %{
          observable_id: "commanding.queue_depth:endpoint-alpha",
          frame_observable_id: "commanding.queue_depth",
          query_scope_kind: "source_endpoint",
          query_scope_id: "endpoint-alpha",
          query_scope_ids: ["endpoint-alpha", "endpoint-beta"]
        },
        links: [presented_link()],
        placement_id: "placement-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["commanding.queue_depth"] =
             document
             |> LazyHTML.query("[data-data-table-row-evidence]")
             |> LazyHTML.attribute("data-data-table-row-evidence-observable")

    assert ["source_endpoint"] =
             document
             |> LazyHTML.query("[data-data-table-row-evidence]")
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert ["endpoint-alpha"] =
             document
             |> LazyHTML.query("[data-data-table-row-evidence]")
             |> LazyHTML.attribute("phx-value-scope-id")

    assert ["endpoint-alpha,endpoint-beta"] =
             document
             |> LazyHTML.query("[data-data-table-row-evidence]")
             |> LazyHTML.attribute("phx-value-scope-ids")
  end

  defp presented_link do
    %{
      link_id: "link-1",
      label: "Sample",
      target: :telemetry_sample,
      target_text: "telemetry_sample",
      target_id: "sample-1",
      context: %{
        data: %{
          realm: :flight,
          view: "canonical",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight",
          replay_run_id: "replay-run-1"
        },
        time: %{mode: "archive", axis: "receipt_time"}
      }
    }
  end
end
