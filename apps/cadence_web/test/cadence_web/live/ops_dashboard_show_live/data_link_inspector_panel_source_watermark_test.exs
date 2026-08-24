defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelSourceWatermarkTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  test "data_link_panel renders source watermark event inspector rows" do
    panel =
      ViewTestSupport.data_link_inspector_boundary(
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

    root_attrs = panel["outer_wrapper"]["attrs"]
    presentation = panel["presentation"]

    assert ["source_watermark_event"] = [root_attrs["data-data-link-target"]]

    assert ["watermark-event-1"] = [root_attrs["data-data-link-target-id"]]

    assert ["source_watermark_event:watermark-event-1:events-request-1"] =
             [root_attrs["data-data-link-selected-link"]]

    assert "source watermark event" =
             presentation
             |> ViewTestSupport.data_link_inspector_row("selection", "Target")
             |> get_in(["value", "text"])

    assert "watermark-event-1" =
             presentation
             |> ViewTestSupport.data_link_inspector_row("record", "Source watermark event")
             |> get_in(["value", "text"])

    assert "source_watermark:mission-1:telemetry" =
             presentation
             |> ViewTestSupport.data_link_inspector_row("record", "Source watermark key")
             |> get_in(["value", "text"])

    assert "telemetry_storage_write" =
             presentation
             |> ViewTestSupport.data_link_inspector_row("record", "Reason")
             |> get_in(["value", "text"])

    assert "events-questdb" =
             presentation
             |> ViewTestSupport.data_link_inspector_row("runtime_context", "Data source")
             |> get_in(["value", "text"])
  end
end
