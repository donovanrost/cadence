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

    document = LazyHTML.from_fragment(html)

    assert html =~ "Phase"
    assert html =~ "Kind"
    assert html =~ "Status"
    assert html =~ "Contact"

    assert ["tlm.contact.phase"] =
             document
             |> LazyHTML.query("[data-status-matrix-row]")
             |> LazyHTML.attribute("data-status-matrix-row")

    assert ["source-request-1"] =
             document
             |> LazyHTML.query("[data-status-matrix-row]")
             |> LazyHTML.attribute("data-status-matrix-source-request-id")

    assert ["link-alpha"] =
             document
             |> LazyHTML.query("[data-status-matrix-row]")
             |> LazyHTML.attribute("data-status-matrix-link-id")

    assert ["transport"] =
             document
             |> LazyHTML.query("[data-status-matrix-row]")
             |> LazyHTML.attribute("data-status-matrix-query-scope-kind")

    assert ["transport-alpha"] =
             document
             |> LazyHTML.query("[data-status-matrix-row]")
             |> LazyHTML.attribute("data-status-matrix-query-scope-id")

    assert ["transport-alpha,transport-beta"] =
             document
             |> LazyHTML.query("[data-status-matrix-row]")
             |> LazyHTML.attribute("data-status-matrix-query-scope-ids")

    assert ["open_evidence"] =
             document
             |> LazyHTML.query("[data-status-matrix-row-evidence]")
             |> LazyHTML.attribute("phx-click")

    assert ["open_data_link"] =
             document
             |> LazyHTML.query("[data-status-matrix-row-link-ref]")
             |> LazyHTML.attribute("phx-click")
  end

  test "data_table renders row context attrs and data management badges" do
    html =
      render_component(&WidgetRowComponents.data_table/1,
        data: %{rows: [data_table_row()]},
        widget: widget(),
        placement_id: "placement-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["tlm.hk.battery_voltage"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-row")

    assert ["flight"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-realm")

    assert ["link-alpha"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-link-id")

    assert ["source_endpoint"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-scope-kind")

    assert ["endpoint-alpha"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-source-endpoint-id")

    assert ["source_endpoint"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-query-scope-kind")

    assert ["endpoint-alpha"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-query-scope-id")

    assert ["endpoint-alpha,endpoint-beta"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-query-scope-ids")

    assert ["corrected"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-management-badges")

    assert ["stale_data"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-management-warning-codes")

    assert ["corrected"] =
             document
             |> LazyHTML.query("[data-data-management-badge]")
             |> LazyHTML.attribute("data-data-management-badge")
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

    document = LazyHTML.from_fragment(html)

    assert ["tlm.hk.battery_voltage"] =
             document
             |> LazyHTML.query("[data-state-timeline-lane]")
             |> LazyHTML.attribute("data-state-timeline-lane")

    assert ["Red"] =
             document
             |> LazyHTML.query("[data-state-timeline-row]")
             |> LazyHTML.attribute("data-state-timeline-state")

    assert html =~ "5m"

    assert ["open_data_link"] =
             document
             |> LazyHTML.query("[data-state-timeline-row-link-ref]")
             |> LazyHTML.attribute("phx-click")
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
