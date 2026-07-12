defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelSourceWatermarkTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents

  test "data_link_panel renders source watermark event inspector rows" do
    html =
      render_component(&DataLinkInspectorPanelComponents.data_link_panel/1,
        inspector: %{
          status: :resolved,
          status_text: "resolved",
          title: "Source watermark event",
          target: :source_watermark_event,
          target_text: "source watermark event",
          target_id: "watermark-event-1",
          link_id: "source_watermark_event:watermark-event-1:events-request-1",
          link_label: "Source watermark event",
          source: :frame,
          source_text: "frame",
          message: nil,
          rows: [
            %{label: "Source watermark event", value: "watermark-event-1"},
            %{label: "Source watermark key", value: "source_watermark:mission-1:telemetry"},
            %{label: "Logical source", value: "telemetry"},
            %{label: "Data source", value: "questdb-flight"},
            %{label: "Source binding", value: "binding-flight"},
            %{label: "Complete through", value: "2026-06-21T12:05:00.000000Z"},
            %{label: "Latest receipt time", value: "2026-06-21T12:05:30.000000Z"},
            %{label: "Reason", value: "telemetry_storage_write"}
          ],
          context_rows: [
            %{label: "Data realm", value: "flight"},
            %{label: "Data source", value: "events-questdb"},
            %{label: "Source binding", value: "events-binding"},
            %{label: "Time mode", value: "archive"},
            %{label: "Logical source", value: "events"}
          ],
          related_links: [],
          actions: []
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link&selected_target=source_watermark_event"
      )

    document = LazyHTML.from_fragment(html)

    assert ["source_watermark_event"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-target")

    assert ["watermark-event-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-target-id")

    assert ["source_watermark_event:watermark-event-1:events-request-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-link")

    assert "source watermark event" =
             document
             |> LazyHTML.query(~s([data-data-link-selection-field="Target"]))
             |> selected_text()

    assert "watermark-event-1" =
             document
             |> LazyHTML.query(~s([data-data-link-field="Source watermark event"]))
             |> selected_text()

    assert "source_watermark:mission-1:telemetry" =
             document
             |> LazyHTML.query(~s([data-data-link-field="Source watermark key"]))
             |> selected_text()

    assert "telemetry_storage_write" =
             document
             |> LazyHTML.query(~s([data-data-link-field="Reason"]))
             |> selected_text()

    assert "events-questdb" =
             document
             |> LazyHTML.query(~s([data-data-link-context="Data source"]))
             |> selected_text()
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
