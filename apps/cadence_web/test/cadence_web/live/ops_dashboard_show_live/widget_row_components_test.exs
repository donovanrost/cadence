defmodule CadenceWeb.OpsDashboardShowLive.WidgetRowComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetRowComponents

  test "status_matrix_table renders operational headings, evidence attrs, and row links" do
    html =
      render_component(&WidgetRowComponents.status_matrix_table/1,
        data: %{rows: [status_matrix_row()]},
        widget: widget(),
        placement_id: "placement-1"
      )

    presentation =
      widget_rows_presentation(
        html,
        "widget-rows-status-matrix-placement-1-component",
        "status_matrix"
      )

    row = hd(presentation["rows"])

    [evidence, row_link] = table_row_link_items(row)

    headings = Enum.map(presentation["head"]["cells"], & &1["text"])

    assert "Phase" in headings
    assert "Kind" in headings
    assert "Status" in headings
    assert "Contact" in headings

    assert row["attrs"]["data-status-matrix-row"] == "tlm.contact.phase"

    assert row["attrs"]["data-status-matrix-source-request-id"] == "source-request-1"

    assert row["attrs"]["data-status-matrix-link-id"] == "link-alpha"

    assert row["attrs"]["data-status-matrix-query-scope-kind"] == "transport"

    assert row["attrs"]["data-status-matrix-query-scope-id"] == "transport-alpha"

    assert row["attrs"]["data-status-matrix-query-scope-ids"] ==
             "transport-alpha,transport-beta"

    assert evidence["attrs"]["phx-click"] == "open_evidence"

    assert row_link["attrs"]["phx-click"] == "open_data_link"
  end

  test "data_table renders row context attrs and data management badges" do
    html =
      render_component(&WidgetRowComponents.data_table/1,
        data: %{rows: [data_table_row()]},
        widget: widget(),
        placement_id: "placement-1"
      )

    presentation =
      widget_rows_presentation(
        html,
        "widget-rows-data-table-placement-1-component",
        "data_table"
      )

    row = hd(presentation["rows"])
    quality_cell = Enum.find(row["cells"], &(&1["key"] == "quality"))
    corrected_badge = Enum.find(quality_cell["badges"], &(&1["text"] == "corrected"))

    assert row["attrs"]["data-data-table-row"] == "tlm.hk.battery_voltage"

    assert row["attrs"]["data-data-table-realm"] == "flight"

    assert row["attrs"]["data-data-table-link-id"] == "link-alpha"

    assert row["attrs"]["data-data-table-scope-kind"] == "source_endpoint"

    assert row["attrs"]["data-data-table-source-endpoint-id"] == "endpoint-alpha"

    assert row["attrs"]["data-data-table-query-scope-kind"] == "source_endpoint"

    assert row["attrs"]["data-data-table-query-scope-id"] == "endpoint-alpha"

    assert row["attrs"]["data-data-table-query-scope-ids"] == "endpoint-alpha,endpoint-beta"

    assert row["attrs"]["data-data-management-badges"] == "corrected"

    assert row["attrs"]["data-data-management-warning-codes"] == "stale_data"

    assert corrected_badge["attrs"]["data-data-management-badge"] == "corrected"
  end

  test "state_timeline renders lanes, state labels, duration, and row links" do
    html =
      render_component(&WidgetRowComponents.state_timeline/1,
        data: %{
          rows: [],
          lanes: [
            %{
              lane_key: "tlm.hk.battery_voltage",
              label: "Battery voltage",
              observable_id: "tlm.hk.battery_voltage",
              source: "telemetry",
              resource_id: "battery-voltage",
              scope_kind: "spacecraft",
              rows: [state_timeline_row()]
            }
          ]
        },
        placement_id: "placement-1"
      )

    presentation =
      widget_rows_presentation(
        html,
        "widget-rows-state-timeline-placement-1-component",
        "state_timeline"
      )

    lane = hd(presentation["lanes"])
    row = hd(lane["rows"])
    [evidence, row_link] = row["link_menu"]["items"]

    assert lane["attrs"]["data-state-timeline-lane"] == "tlm.hk.battery_voltage"

    assert row["attrs"]["data-state-timeline-state"] == "Red"

    assert "5m" in row["metadata"]

    assert evidence["attrs"]["phx-click"] == "open_evidence"
    assert row_link["attrs"]["phx-click"] == "open_data_link"
  end

  defp widget_rows_presentation(html, component_id, kind) do
    vue = LiveVue.Test.get_vue(html, id: component_id)
    assert vue.component == "WidgetRows"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.props["presentation"]["kind"] == kind
    assert vue.props["presentation"]["component_id"] == component_id
    vue.props["presentation"]
  end

  defp table_row_link_items(row) do
    row
    |> Map.fetch!("cells")
    |> Enum.find(&(&1["key"] == "actions"))
    |> Map.fetch!("link_menu")
    |> Map.fetch!("items")
  end

  defp widget do
    %{options: %{precision: 2}}
  end

  defp status_matrix_row do
    %{
      observable_id: "tlm.contact.phase",
      label: "Contact phase",
      source: :contact,
      status_policy: :contact_phase,
      contact_kind: :scheduled,
      phase: :active,
      normalized_state: :green,
      contact_id: "contact-1",
      value: :active,
      frame_observable_id: "frame.contact.phase",
      source_request_id: "source-request-1",
      link_id: "link-alpha",
      logical_source: "contact-plan",
      realm: "flight",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight",
      dataset: "contacts",
      query_scope_kind: "transport",
      query_scope_id: "transport-alpha",
      query_scope_ids: ["transport-alpha", "transport-beta"],
      links: [data_link()]
    }
  end

  defp data_table_row do
    %{
      observable_id: "tlm.hk.battery_voltage",
      label: "Battery voltage",
      source: :telemetry,
      value: 12.25,
      unit: "V",
      quality_state: :good,
      normalized_state: :green,
      receipt_time: ~U[2026-06-17 12:00:00Z],
      link_id: "link-alpha",
      scope_kind: :source_endpoint,
      source_endpoint_id: "endpoint-alpha",
      query_scope_kind: "source_endpoint",
      query_scope_id: "endpoint-alpha",
      query_scope_ids: ["endpoint-alpha", "endpoint-beta"],
      realm: :flight,
      data_management: %{badges: [badge()], warning_codes: [:stale_data]},
      links: []
    }
  end

  defp state_timeline_row do
    %{
      row_id: "state-1",
      observable_id: "tlm.hk.battery_voltage",
      label: "Battery voltage",
      normalized_state: :red,
      starts_at: ~U[2026-06-17 12:00:00Z],
      ends_at: ~U[2026-06-17 12:05:00Z],
      sample_id: "sample-1",
      resource_id: "sample-1",
      limit_definition_id: "battery-voltage",
      limit_definition_version: 3,
      links: [data_link()]
    }
  end

  defp badge(value \\ "corrected") do
    %{
      kind: :data_view,
      value: value,
      code: nil,
      label: String.replace(value, "_", " "),
      status: :info
    }
  end

  defp data_link do
    %{
      link_id: "link-1",
      label: "Telemetry sample",
      target_text: "telemetry_sample",
      target_id: "sample-1",
      context: %{
        data: %{
          realm: :flight,
          view: "canonical",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight"
        },
        time: %{
          mode: "archive",
          axis: "receipt_time"
        }
      }
    }
  end
end
