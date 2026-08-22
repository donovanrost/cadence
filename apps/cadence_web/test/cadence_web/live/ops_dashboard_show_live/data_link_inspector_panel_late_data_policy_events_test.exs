defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelLateDataPolicyEventsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents

  test "data_link_panel marks late-data policy decisions event-only without source sample identity" do
    html =
      render_component(&DataLinkInspectorPanelComponents.data_link_panel/1,
        inspector: %{
          status: :resolved,
          status_text: "resolved",
          title: "Telemetry backfill lifecycle event",
          target: :telemetry_backfill_lifecycle_event,
          target_text: "telemetry backfill lifecycle event",
          target_id: "backfill-event-1",
          link_label: "Telemetry backfill lifecycle event",
          source: :frame,
          source_text: "frame",
          message: nil,
          rows: [
            %{label: "Backfill lifecycle event", value: "backfill-event-1"},
            %{label: "Backfill run", value: "backfill-run-1"},
            %{label: "Event type", value: "backfill_completed"},
            %{label: "Realm", value: "flight"},
            %{label: "Data source", value: "questdb-flight"},
            %{label: "Source binding", value: "binding-flight"}
          ],
          context_rows: [],
          related_links: [],
          actions: []
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )

    document = LazyHTML.from_fragment(html)

    assert ["event_only"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls")
             |> LazyHTML.attribute("data-late-data-policy-execution-mode")

    assert "Event only" =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls .badge-warning")
             |> selected_text()
  end

  test "data_link_panel does not render late-data policy controls for policy events" do
    html =
      render_component(&DataLinkInspectorPanelComponents.data_link_panel/1,
        inspector: %{
          status: :resolved,
          status_text: "resolved",
          title: "Telemetry backfill lifecycle event",
          target: :telemetry_backfill_lifecycle_event,
          target_text: "telemetry backfill lifecycle event",
          target_id: "late-event-1",
          link_label: "Telemetry backfill lifecycle event",
          source: :frame,
          source_text: "frame",
          message: nil,
          rows: [
            %{label: "Backfill lifecycle event", value: "late-event-1"},
            %{label: "Backfill run", value: "backfill-run-1"},
            %{label: "Event type", value: "late_data_accepted"},
            %{label: "Late data policy decision", value: "accept"},
            %{label: "Late data source event", value: "backfill-event-1"},
            %{label: "Late data selected samples", value: "2"},
            %{label: "Late data write validity", value: "canonical"},
            %{
              label: "Late data projection effect",
              value: "canonical_history_and_current_projection"
            },
            %{label: "Realm", value: "flight"},
            %{label: "Data source", value: "questdb-flight"},
            %{label: "Source binding", value: "binding-flight"}
          ],
          context_rows: [],
          related_links: [],
          actions: []
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )

    document = LazyHTML.from_fragment(html)

    assert ["late_data_accepted"] =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation")
             |> LazyHTML.attribute("data-workflow-explanation-state")

    assert "backfill-event-1" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Policy source"]))
             |> selected_text()

    assert "accept" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Policy"]))
             |> selected_text()

    assert "2" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Selected samples"]))
             |> selected_text()

    assert "canonical_history_and_current_projection" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Projection"]))
             |> selected_text()

    assert "canonical" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Write validity"]))
             |> selected_text()

    assert [] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls")
             |> LazyHTML.attribute("id")
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
