defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelLateDataPolicyTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyActionOutcome

  test "data_link_panel renders late-data policy controls for lifecycle events" do
    html =
      render_component(&DataLinkInspectorPanelComponents.data_link_panel/1,
        data_link_action_outcome:
          LateDataPolicyActionOutcome.new(
            status: :ok,
            kind: :info,
            reason: "late_data_policy_applied",
            decision: "accept",
            execution_mode: "event_only",
            dashboard_time_mode: "replay_run",
            dashboard_replay_run_id: "replay-1",
            dashboard_limit_mode: "compare",
            result_event_id: "late-data-event-1",
            target_event_id: "late-data-event-1",
            target_run_id: "backfill-run-1",
            message: "Late-data policy applied."
          ),
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
            %{label: "Workflow", value: "backfill"},
            %{label: "Workflow stage", value: "completed"},
            %{label: "Workflow run", value: "backfill-run-1"},
            %{label: "Dashboard context time mode", value: "replay_run"},
            %{label: "Dashboard context replay run", value: "replay-1"},
            %{label: "Realm", value: "flight"},
            %{label: "Data source", value: "questdb-flight"},
            %{label: "Source binding", value: "binding-flight"},
            %{label: "Observable", value: "HK.counter"},
            %{label: "Point", value: "HK.counter"},
            %{label: "Source from", value: "2026-06-22T10:00:00Z"},
            %{label: "Source to", value: "2026-06-22T11:00:00Z"},
            %{label: "Receipt from", value: "2026-06-22T12:00:00Z"},
            %{label: "Receipt to", value: "2026-06-22T12:10:00Z"},
            %{label: "Sample count", value: "3"},
            %{label: "Authority", value: "authoritative"},
            %{label: "Reason", value: "operator_backfill"}
          ],
          context_rows: [
            %{label: "Limit mode", value: "compare"}
          ],
          related_links: [],
          actions: []
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )

    document = LazyHTML.from_fragment(html)

    assert ["backfill_completed"] =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation")
             |> LazyHTML.attribute("data-workflow-explanation-event-type")

    assert ["completed"] =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation")
             |> LazyHTML.attribute("data-workflow-explanation-state")

    assert "backfill-run-1" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Run"]))
             |> selected_text()

    assert ["backfill-event-1"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls")
             |> LazyHTML.attribute("data-late-data-policy-source-event")

    assert ["event_only"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls")
             |> LazyHTML.attribute("data-late-data-policy-execution-mode")

    assert ["auditable policy decision; telemetry projections unchanged"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls")
             |> LazyHTML.attribute("data-late-data-policy-accept-effect")

    assert ["advisory history only; current/latest projections unchanged"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls")
             |> LazyHTML.attribute("data-late-data-policy-reject-effect")

    assert ["record_late_data_policy_decision"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-form")
             |> LazyHTML.attribute("phx-submit")

    assert "Event only" =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls .badge-warning")
             |> selected_text()

    assert "auditable policy decision; telemetry projections unchanged" =
             document
             |> LazyHTML.query(~s([data-late-data-policy-effect-summary="accept"]))
             |> selected_text()

    assert "advisory history only; current/latest projections unchanged" =
             document
             |> LazyHTML.query(~s([data-late-data-policy-effect-summary="reject"]))
             |> selected_text()

    assert "Apply late-data policy" =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-submit")
             |> selected_text()

    assert ["backfill-event-1"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-source-event-id")
             |> LazyHTML.attribute("value")

    assert ["backfill_completed"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-source-event-type")
             |> LazyHTML.attribute("value")

    assert ["backfill-run-1"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-run-id")
             |> LazyHTML.attribute("value")

    assert ["compare"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-dashboard-limit-mode")
             |> LazyHTML.attribute("value")

    assert ["replay_run"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-dashboard-time-mode")
             |> LazyHTML.attribute("value")

    assert ["replay-1"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-dashboard-replay-run-id")
             |> LazyHTML.attribute("value")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-data-source-id")
             |> LazyHTML.attribute("value")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-source-binding-id")
             |> LazyHTML.attribute("value")

    assert ["3"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-sample-count")
             |> LazyHTML.attribute("value")

    assert ["ok"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-action-outcome")
             |> LazyHTML.attribute("data-late-data-policy-action-status")

    assert ["compare"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-action-outcome")
             |> LazyHTML.attribute("data-late-data-policy-action-dashboard-limit-mode")

    assert ["replay_run"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-action-outcome")
             |> LazyHTML.attribute("data-late-data-policy-action-dashboard-time-mode")

    assert ["replay-1"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-action-outcome")
             |> LazyHTML.attribute("data-late-data-policy-action-dashboard-replay-run-id")

    assert ["late_data_policy"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-action")

    assert ["accept"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-decision")

    assert ["event_only"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-execution-mode")

    assert ["replay_run"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-dashboard-time-mode")

    assert ["replay-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-dashboard-replay-run-id")

    assert ["compare"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-dashboard-limit-mode")

    assert ["late-data-event-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-result-event-id")

    assert ["late-data-event-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-target-event-id")

    assert ["backfill-run-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-target-run-id")

    assert %{
             "decision" => "accept",
             "execution_mode" => "event_only",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-1",
             "dashboard_limit_mode" => "compare",
             "result_event_id" => "late-data-event-1",
             "target_event_id" => "late-data-event-1",
             "target_run_id" => "backfill-run-1"
           } =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-metadata")
             |> List.first()
             |> Jason.decode!()

    assert ["accept"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-action-outcome")
             |> LazyHTML.attribute("data-late-data-policy-action-decision")

    assert ["late-data-event-1"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-action-outcome")
             |> LazyHTML.attribute("data-late-data-policy-action-result-event-id")
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
