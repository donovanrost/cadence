defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowControlsPresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflowActionOutcomePresentation,
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

  test "build presents latest workflow action outcome state" do
    controls =
      HistoricalWorkflowControlsPresentation.build(
        %{
          event_id: "event-1",
          workflow: "backfill",
          stage: "requested",
          run_id: "run-1",
          realm: "flight",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight"
        },
        %{
          action: "stage_transition",
          status: "blocked",
          kind: "error",
          reason: "confirmation_required",
          stage: "approved",
          job_id: "job-1",
          count: 2,
          retried: 1,
          retry_nonretryable: 1,
          retry_skipped: 3,
          retry_errors: 0,
          retry_scope: "replacement_jobs",
          retry_run_ids: "run-004-corrected,run-005-corrected",
          retry_nonretryable_run_ids: "run-nonretryable",
          retry_nonretryable_event_ids: "failed-event-nonretryable",
          retry_nonretryable_items:
            "run=run-nonretryable event=failed-event-nonretryable action=correct_workflow_request reason=correction_required",
          retry_skipped_run_ids: "run-skipped",
          retry_skipped_event_ids: "failed-event-skipped",
          retry_skipped_items:
            "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed",
          retry_error_run_ids: "run-004-corrected",
          retry_error_event_ids: "failed-event-4",
          retry_error_items:
            "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down",
          queued_jobs: 2,
          failed_jobs: 0,
          result_event_ids: "event-1,event-2",
          target_event_id: "event-1",
          target_run_id: "run-1",
          message: "Confirm the historical data workflow approved transition before recording it."
        }
      )

    assert %HistoricalWorkflowControlsPresentation{} = controls
    assert %HistoricalWorkflowActionOutcomePresentation{} = controls.latest_action_outcome

    assert controls.latest_action_outcome.action == "stage_transition"
    assert controls.latest_action_outcome.action_label == "Stage transition"
    assert controls.latest_action_outcome.status == "blocked"
    assert controls.latest_action_outcome.status_label == "Blocked"
    assert controls.latest_action_outcome.kind == "error"
    assert controls.latest_action_outcome.reason == "confirmation_required"
    assert controls.latest_action_outcome.stage == "approved"
    assert controls.latest_action_outcome.job_id == "job-1"
    assert controls.latest_action_outcome.count == "2"
    assert controls.latest_action_outcome.retried == "1"
    assert controls.latest_action_outcome.retry_nonretryable == "1"
    assert controls.latest_action_outcome.retry_skipped == "3"
    assert controls.latest_action_outcome.retry_errors == "0"
    assert controls.latest_action_outcome.retry_scope == "replacement_jobs"
    assert controls.latest_action_outcome.retry_run_ids == "run-004-corrected,run-005-corrected"

    assert controls.latest_action_outcome.retry_disposition.nonretryable_run_ids ==
             "run-nonretryable"

    assert controls.latest_action_outcome.retry_disposition.nonretryable_event_ids ==
             "failed-event-nonretryable"

    assert controls.latest_action_outcome.retry_disposition.nonretryable_items ==
             "run=run-nonretryable event=failed-event-nonretryable action=correct_workflow_request reason=correction_required"

    assert controls.latest_action_outcome.retry_disposition.skipped_run_ids == "run-skipped"

    assert controls.latest_action_outcome.retry_disposition.skipped_event_ids ==
             "failed-event-skipped"

    assert controls.latest_action_outcome.retry_disposition.skipped_items ==
             "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed"

    assert controls.latest_action_outcome.retry_error_run_ids == "run-004-corrected"
    assert controls.latest_action_outcome.retry_error_event_ids == "failed-event-4"

    assert controls.latest_action_outcome.retry_error_items ==
             "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down"

    assert controls.latest_action_outcome.queued_jobs == "2"
    assert controls.latest_action_outcome.failed_jobs == "0"
    assert controls.latest_action_outcome.result_event_ids == "event-1,event-2"
    assert controls.latest_action_outcome.target_event_id == "event-1"
    assert controls.latest_action_outcome.target_run_id == "run-1"
    assert controls.latest_action_outcome.request_group_id == nil

    assert controls.latest_action_outcome.message ==
             "Confirm the historical data workflow approved transition before recording it."

    assert controls.latest_action_outcome.class ==
             "border-warning/40 bg-warning/10 text-base-content"

    assert controls.latest_action_outcome.badge_class == "badge-warning"
  end

  test "build hides latest workflow action outcome for a different selected event" do
    context = %{
      event_id: "event-2",
      run_id: "run-1",
      workflow: "backfill",
      stage: "requested",
      realm: "flight",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight"
    }

    outcome = %{
      action: "stage_transition",
      status: "ok",
      kind: "info",
      reason: "stage_recorded",
      stage: "approved",
      target_event_id: "event-1",
      target_run_id: "run-1",
      message: "Historical data workflow approved recorded."
    }

    assert %{latest_action_outcome: nil} =
             HistoricalWorkflowControlsPresentation.build(context, outcome)

    assert %{latest_action_outcome: %{message: "Historical data workflow approved recorded."}} =
             HistoricalWorkflowControlsPresentation.build(
               %{context | event_id: "event-1"},
               outcome
             )
  end

  test "build presents degraded latest workflow action outcome state" do
    controls =
      HistoricalWorkflowControlsPresentation.build(
        %{
          event_id: "event-1",
          workflow: "backfill",
          stage: "started",
          run_id: "run-1",
          realm: "flight",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight"
        },
        %{
          action: "group_stage_transition",
          status: "degraded",
          kind: "error",
          reason: "group_started_job_dispatch_degraded",
          stage: "started",
          queued_jobs: 2,
          failed_jobs: 1,
          target_event_id: "event-1",
          message:
            "Historical data workflow group started for 3 items; 2 jobs queued and 1 job dispatch failed."
        }
      )

    assert %HistoricalWorkflowControlsPresentation{} = controls
    assert %HistoricalWorkflowActionOutcomePresentation{} = controls.latest_action_outcome
    assert controls.latest_action_outcome.status_label == "Degraded"
    assert controls.latest_action_outcome.queued_jobs == "2"
    assert controls.latest_action_outcome.failed_jobs == "1"

    assert controls.latest_action_outcome.class ==
             "border-warning/40 bg-warning/10 text-base-content"

    assert controls.latest_action_outcome.badge_class == "badge-warning"
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
