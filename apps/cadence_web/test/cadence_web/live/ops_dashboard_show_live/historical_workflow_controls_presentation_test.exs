defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowControlsPresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflowActionPolicyAction,
    HistoricalWorkflowBlockedActionExplanation,
    HistoricalWorkflowControlsPresentation
  }

  test "build presents workflow stage form defaults and actions" do
    controls =
      HistoricalWorkflowControlsPresentation.build(%{
        workflow: "backfill",
        stage: "requested",
        run_id: "run-1",
        realm: "flight",
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        observable_id: "HK.counter",
        point_id: "HK.counter",
        dashboard_id: "dashboard-1",
        dashboard_version: "7",
        dashboard_time_mode: "replay_run",
        dashboard_replay_run_id: "replay-1",
        dashboard_data_view: "all_revisions",
        dashboard_limit_mode: "observed",
        source_from: "2026-06-22T10:00:00Z",
        source_to: "2026-06-22T11:00:00Z"
      })

    assert %HistoricalWorkflowControlsPresentation{} = controls
    assert controls.controls_available

    assert controls.form_params == %{
             "workflow" => "backfill",
             "run_id" => "run-1",
             "realm" => "flight",
             "data_source_id" => "questdb-flight",
             "source_binding_id" => "binding-flight",
             "observable_id" => "HK.counter",
             "point_id" => "HK.counter",
             "dashboard_id" => "dashboard-1",
             "dashboard_version" => "7",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-1",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed",
             "comparison_review_request_event_id" => "",
             "comparison_review_request_kind" => "",
             "comparison_review_open_count" => "",
             "comparison_review_open_placement_ids" => "",
             "comparison_review_workflow_kind" => "",
             "comparison_review_workflow_action" => "",
             "comparison_review_workflow_selection_kind" => "",
             "comparison_review_workflow_selection_count" => "",
             "comparison_review_primary_data_view" => "",
             "comparison_review_compare_data_view" => "",
             "comparison_review_scope_kind" => "",
             "comparison_review_scope_ids" => "",
             "comparison_review_contact_ids" => "",
             "comparison_review_resource_ids" => "",
             "comparison_review_transport_ids" => "",
             "comparison_review_source_endpoint_ids" => "",
             "comparison_review_ground_station_ids" => "",
             "comparison_review_scope_link_ids" => "",
             "request_group_id" => "",
             "request_mode" => "",
             "source_from" => "2026-06-22T10:00:00Z",
             "source_to" => "2026-06-22T11:00:00Z",
             "stage" => "",
             "reason" => "",
             "confirmed" => ""
           }

    assert [
             %{stage: "requested", disabled?: true, reason: "already_in_stage"},
             %{stage: "approved", disabled?: false, reason: "stage_transition_available"} | _
           ] =
             controls.stage_actions

    start_action = Enum.find(controls.stage_actions, &(&1.stage == "started"))
    assert %HistoricalWorkflowActionPolicyAction{} = start_action
    assert start_action.disabled?
    assert start_action.reason == "stage_transition_out_of_order"
    assert start_action.preview == "start transition is not currently eligible"

    requested_explanation =
      Enum.find(controls.blocked_action_explanations, &(&1.id == "stage_requested"))

    assert %HistoricalWorkflowBlockedActionExplanation{} = requested_explanation
    assert requested_explanation.kind == "stage"
    assert requested_explanation.label == "Request"
    assert requested_explanation.reason == "already_in_stage"
    assert requested_explanation.explanation == "Request is already the current workflow stage."
    assert requested_explanation.state_summary == "current stage requested"

    assert requested_explanation.available_when ==
             "Choose a transition that advances or changes the current stage."

    started_explanation =
      Enum.find(controls.blocked_action_explanations, &(&1.id == "stage_started"))

    assert %HistoricalWorkflowBlockedActionExplanation{} = started_explanation
    assert started_explanation.kind == "stage"
    assert started_explanation.label == "Start"
    assert started_explanation.reason == "stage_transition_out_of_order"
    assert started_explanation.explanation == "Start does not follow the current workflow stage."
    assert started_explanation.state_summary == "current stage requested"

    assert started_explanation.available_when ==
             "Record the prerequisite workflow stage before this transition."
  end

  test "build disables start action when a workflow job already exists" do
    controls =
      HistoricalWorkflowControlsPresentation.build(%{
        workflow: "backfill",
        stage: "approved",
        run_id: "run-1",
        realm: "flight",
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        job_id: "job-1",
        job_status: "queued"
      })

    assert %HistoricalWorkflowControlsPresentation{} = controls
    assert controls.job_status
    assert controls.job_status_class == "border-base-300/70 bg-base-100/60 text-base-content"
    start_action = Enum.find(controls.stage_actions, &(&1.stage == "started"))
    assert start_action.disabled?
    assert start_action.reason == "job_already_exists"
  end

  test "build presents group summary, group actions, and retryable failed controls" do
    controls =
      HistoricalWorkflowControlsPresentation.build(%{
        workflow: "backfill",
        run_id: "run-1",
        realm: "flight",
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        request_group_id: "group-1",
        request_mode: "bulk_points",
        request_item_count: 3,
        request_group_progress: "1/3",
        request_group_approve_eligible: "2",
        request_group_start_eligible: 2,
        request_group_complete_eligible: "0",
        request_group_fail_eligible: "bad",
        request_group_correction_tasks:
          "HK.current run-3 replacement run-3-corrected stage requested next approve; HK.voltage run-4 replacement run-4-corrected stage requested next approve; HK.temp run-5 replacement run-5-corrected stage approved next start",
        request_group_retryable_failed: "2"
      })

    assert %HistoricalWorkflowControlsPresentation{} = controls
    assert controls.group_summary
    assert controls.group_actions
    assert controls.group_retryable_failures

    approve_action = Enum.find(controls.group_stage_actions, &(&1.stage == "approved"))
    assert %HistoricalWorkflowActionPolicyAction{} = approve_action
    assert approve_action.eligible_count == 2
    assert approve_action.eligible?
    assert approve_action.reason == "eligible_group_items"

    assert approve_action.preview ==
             "Record approve transition for 2 eligible items in request group group-1"

    assert approve_action.correction_tasks ==
             "HK.current run-3 replacement run-3-corrected stage requested next approve; HK.voltage run-4 replacement run-4-corrected stage requested next approve"

    assert approve_action.state_summary ==
             "group group-1; progress 1/3; eligible 2 for approved; correction tasks HK.current run-3 replacement run-3-corrected stage requested next approve; HK.voltage run-4 replacement run-4-corrected stage requested next approve"

    start_action = Enum.find(controls.group_stage_actions, &(&1.stage == "started"))

    assert start_action.eligible_count == 2

    assert start_action.correction_tasks ==
             "HK.temp run-5 replacement run-5-corrected stage approved next start"

    assert start_action.state_summary ==
             "group group-1; progress 1/3; eligible 2 for started; correction task HK.temp run-5 replacement run-5-corrected stage approved next start"

    complete_action = Enum.find(controls.group_stage_actions, &(&1.stage == "completed"))
    assert complete_action.disabled?
    assert complete_action.reason == "no_eligible_group_items"

    assert Enum.find(controls.group_stage_actions, &(&1.stage == "failed")).eligible_count == 0

    completed_explanation =
      Enum.find(controls.blocked_action_explanations, &(&1.id == "group_stage_completed"))

    assert %HistoricalWorkflowBlockedActionExplanation{} = completed_explanation
    assert completed_explanation.kind == "group_stage"
    assert completed_explanation.reason == "no_eligible_group_items"

    assert completed_explanation.state_summary ==
             "group group-1; progress 1/3; eligible 0 for completed"

    assert completed_explanation.explanation ==
             "No request-group items are eligible for complete."
  end

  test "build presents retryable failed job and correction request state" do
    controls =
      HistoricalWorkflowControlsPresentation.build(%{
        workflow: "backfill",
        run_id: "run-1",
        event_id: "event-1",
        job_id: "job-1",
        job_status: "failed",
        retryable: "true",
        recovery_action: "correct_workflow_request",
        realm: "backfill",
        data_source_id: "managed_questdb_backfill",
        source_binding_id: "backfill_telemetry",
        source_realm: "flight",
        source_data_source_id: "questdb-flight",
        source_binding_id_override: "binding-flight",
        source_point_id: "HK.counter",
        dashboard_id: "dashboard-1",
        dashboard_version: "7",
        dashboard_time_mode: "replay_run",
        dashboard_replay_run_id: "replay-1",
        dashboard_data_view: "all_revisions",
        dashboard_limit_mode: "observed",
        source_from_override: "2026-06-22T10:00:00Z",
        source_to_override: "2026-06-22T11:00:00Z"
      })

    assert %HistoricalWorkflowControlsPresentation{} = controls
    assert controls.job_status
    assert controls.job_status_class == "border-error/40 bg-error/10 text-error-content"
    assert controls.correction_requestable
    refute controls.job_retryable
    refute controls.job_retry_action.eligible?
    assert controls.job_retry_action.reason == "correction_required"
    assert controls.correction_request_action.eligible?
    assert controls.correction_request_action.reason == "correction_request_required"

    assert controls.correction_request_action.state_summary ==
             "job job-1; status failed; retryable true; recovery correct_workflow_request"

    retry_explanation =
      Enum.find(controls.blocked_action_explanations, &(&1.id == "retry_job"))

    assert %HistoricalWorkflowBlockedActionExplanation{} = retry_explanation
    assert retry_explanation.reason == "correction_required"

    assert retry_explanation.state_summary ==
             "job job-1; status failed; retryable true; recovery correct_workflow_request"

    assert controls.correction_form_params == %{
             "workflow" => "backfill",
             "run_id" => "run-1-corrected",
             "original_run_id" => "run-1",
             "original_event_id" => "event-1",
             "original_job_id" => "job-1",
             "realm" => "flight",
             "data_source_id" => "questdb-flight",
             "source_binding_id" => "binding-flight",
             "observable_id" => "HK.counter",
             "point_id" => "HK.counter",
             "dashboard_id" => "dashboard-1",
             "dashboard_version" => "7",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-1",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed",
             "comparison_review_request_event_id" => "",
             "comparison_review_request_kind" => "",
             "comparison_review_open_count" => "",
             "comparison_review_open_placement_ids" => "",
             "comparison_review_workflow_kind" => "",
             "comparison_review_workflow_action" => "",
             "comparison_review_workflow_selection_kind" => "",
             "comparison_review_workflow_selection_count" => "",
             "comparison_review_primary_data_view" => "",
             "comparison_review_compare_data_view" => "",
             "comparison_review_scope_kind" => "",
             "comparison_review_scope_ids" => "",
             "comparison_review_contact_ids" => "",
             "comparison_review_resource_ids" => "",
             "comparison_review_transport_ids" => "",
             "comparison_review_source_endpoint_ids" => "",
             "comparison_review_ground_station_ids" => "",
             "comparison_review_scope_link_ids" => "",
             "request_mode" => "",
             "request_group_id" => "",
             "request_item_index" => "",
             "request_item_count" => "",
             "request_item_run_id" => "run-1-corrected",
             "source_from" => "2026-06-22T10:00:00Z",
             "source_to" => "2026-06-22T11:00:00Z",
             "reason" => "corrected_historical_data_workflow_request",
             "confirmed" => ""
           }
  end

  test "controls availability requires workflow source scope" do
    context = %{
      workflow: "backfill",
      run_id: "run-1",
      realm: "flight",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight"
    }

    assert HistoricalWorkflowControlsPresentation.controls_available?(context)

    refute HistoricalWorkflowControlsPresentation.controls_available?(%{
             context
             | source_binding_id: ""
           })

    refute HistoricalWorkflowControlsPresentation.controls_available?(nil)
  end
end
