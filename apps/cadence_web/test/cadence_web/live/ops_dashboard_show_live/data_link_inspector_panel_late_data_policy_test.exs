defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelLateDataPolicyTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyActionOutcome
  alias CadenceWeb.OpsDashboardShowLive.ViewTestSupport

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

    presentation = ViewTestSupport.data_link_inspector_presentation(html)
    workflow = presentation["workflow_explanation"]
    policy = presentation["late_data_policy"]
    action = presentation["action_outcome"]

    assert workflow["attrs"]["data-workflow-explanation-event-type"] == "backfill_completed"
    assert workflow["attrs"]["data-workflow-explanation-state"] == "completed"

    assert workflow["rows"]
           |> Enum.find(&(&1["label"]["text"] == "Run"))
           |> get_in(["value", "text"]) == "backfill-run-1"

    assert policy["attrs"]["data-late-data-policy-source-event"] == "backfill-event-1"
    assert policy["attrs"]["data-late-data-policy-execution-mode"] == "event_only"

    assert policy["attrs"]["data-late-data-policy-accept-effect"] ==
             "auditable policy decision; telemetry projections unchanged"

    assert policy["attrs"]["data-late-data-policy-reject-effect"] ==
             "advisory history only; current/latest projections unchanged"

    assert policy["form"]["attrs"]["phx-submit"] == "record_late_data_policy_decision"
    assert policy["header"]["execution_badge"]["text"] == "Event only"

    assert Enum.at(policy["effects"], 0)["summary"]["text"] ==
             "auditable policy decision; telemetry projections unchanged"

    assert Enum.at(policy["effects"], 1)["summary"]["text"] ==
             "advisory history only; current/latest projections unchanged"

    assert policy["form"]["submit"]["text"] == "Apply late-data policy"

    assert late_data_form_value(presentation, "dashboard-late-data-policy-source-event-id") ==
             "backfill-event-1"

    assert late_data_form_value(presentation, "dashboard-late-data-policy-source-event-type") ==
             "backfill_completed"

    assert late_data_form_value(presentation, "dashboard-late-data-policy-run-id") ==
             "backfill-run-1"

    assert late_data_form_value(
             presentation,
             "dashboard-late-data-policy-dashboard-limit-mode"
           ) == "compare"

    assert late_data_form_value(presentation, "dashboard-late-data-policy-dashboard-time-mode") ==
             "replay_run"

    assert late_data_form_value(
             presentation,
             "dashboard-late-data-policy-dashboard-replay-run-id"
           ) == "replay-1"

    assert late_data_form_value(presentation, "dashboard-late-data-policy-data-source-id") ==
             "questdb-flight"

    assert late_data_form_value(presentation, "dashboard-late-data-policy-source-binding-id") ==
             "binding-flight"

    assert late_data_form_value(presentation, "dashboard-late-data-policy-sample-count") == "3"

    policy_outcome_attrs = policy["action_outcome"]["attrs"]
    assert policy_outcome_attrs["data-late-data-policy-action-status"] == "ok"
    assert policy_outcome_attrs["data-late-data-policy-action-dashboard-limit-mode"] == "compare"

    assert policy_outcome_attrs["data-late-data-policy-action-dashboard-time-mode"] ==
             "replay_run"

    assert policy_outcome_attrs["data-late-data-policy-action-dashboard-replay-run-id"] ==
             "replay-1"

    action_attrs = action["attrs"]
    assert action_attrs["data-data-link-action-outcome-action"] == "late_data_policy"
    assert action_attrs["data-data-link-action-outcome-decision"] == "accept"
    assert action_attrs["data-data-link-action-outcome-execution-mode"] == "event_only"
    assert action_attrs["data-data-link-action-outcome-dashboard-time-mode"] == "replay_run"

    assert action_attrs["data-data-link-action-outcome-dashboard-replay-run-id"] ==
             "replay-1"

    assert action_attrs["data-data-link-action-outcome-dashboard-limit-mode"] == "compare"
    assert action_attrs["data-data-link-action-outcome-result-event-id"] == "late-data-event-1"
    assert action_attrs["data-data-link-action-outcome-target-event-id"] == "late-data-event-1"
    assert action_attrs["data-data-link-action-outcome-target-run-id"] == "backfill-run-1"

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
             action_attrs["data-data-link-action-outcome-metadata"]
             |> Jason.decode!()

    assert policy_outcome_attrs["data-late-data-policy-action-decision"] == "accept"

    assert policy_outcome_attrs["data-late-data-policy-action-result-event-id"] ==
             "late-data-event-1"
  end

  defp late_data_form_value(presentation, id) do
    presentation
    |> ViewTestSupport.data_link_inspector_form_field("late_data_policy", id)
    |> Map.fetch!("value")
  end
end
