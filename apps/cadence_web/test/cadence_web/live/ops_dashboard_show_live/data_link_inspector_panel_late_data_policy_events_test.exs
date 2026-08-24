defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelLateDataPolicyEventsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  test "data_link_panel marks late-data policy decisions event-only without source sample identity" do
    panel =
      ViewTestSupport.data_link_inspector_boundary(
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

    policy =
      panel
      |> Map.fetch!("presentation")
      |> Map.fetch!("late_data_policy")

    assert policy["attrs"]["data-late-data-policy-execution-mode"] == "event_only"
    assert policy["header"]["execution_badge"]["text"] == "Event only"
  end

  test "data_link_panel does not render late-data policy controls for policy events" do
    panel =
      ViewTestSupport.data_link_inspector_boundary(
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

    presentation = panel["presentation"]
    workflow = presentation["workflow_explanation"]

    assert workflow["attrs"]["data-workflow-explanation-state"] == "late_data_accepted"

    workflow_rows =
      Map.new(workflow["rows"], fn row ->
        {row["label"]["text"], row["value"]["text"]}
      end)

    assert workflow_rows["Policy source"] == "backfill-event-1"
    assert workflow_rows["Policy"] == "accept"
    assert workflow_rows["Selected samples"] == "2"
    assert workflow_rows["Projection"] == "canonical_history_and_current_projection"
    assert workflow_rows["Write validity"] == "canonical"

    refute presentation["late_data_policy"]
  end
end
