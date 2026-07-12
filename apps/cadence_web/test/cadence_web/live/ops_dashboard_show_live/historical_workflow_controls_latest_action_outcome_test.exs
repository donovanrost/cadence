defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowControlsLatestActionOutcomeTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflowActionOutcomePresentation,
    HistoricalWorkflowControlsPresentation
  }

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

  test "latest workflow action outcome exposes stable root attributes" do
    outcome =
      HistoricalWorkflowActionOutcomePresentation.normalize(%{
        action: "retry_group_failed_jobs",
        status: "degraded",
        kind: "error",
        reason: "retry_group_partially_recorded",
        stage: "started",
        request_group_id: "group-1",
        job_id: "job-1",
        count: 3,
        retried: 1,
        retry_nonretryable: 1,
        retry_skipped: 1,
        retry_errors: 0,
        retry_scope: "replacement_jobs",
        retry_run_ids: "run-1-corrected",
        retry_nonretryable_run_ids: "run-nonretryable",
        retry_nonretryable_event_ids: "event-nonretryable",
        retry_nonretryable_items:
          "run=run-nonretryable event=event-nonretryable action=correct_workflow_request reason=correction_required",
        retry_skipped_run_ids: "run-skipped",
        retry_skipped_event_ids: "event-skipped",
        retry_skipped_items:
          "run=run-skipped event=event-skipped job=job-skipped status=running reason=job_not_failed",
        retry_error_run_ids: "run-error",
        retry_error_event_ids: "event-error",
        retry_error_items: "run=run-error event=event-error job=job-error reason=queue_down",
        queued_jobs: 2,
        failed_jobs: 1,
        result_event_ids: "event-1,event-2",
        target_event_id: "event-1",
        target_run_id: "run-1",
        dashboard_id: "dashboard-1",
        dashboard_version: 7,
        dashboard_time_mode: "replay_run",
        dashboard_replay_run_id: "replay-1",
        dashboard_data_view: "all_revisions",
        dashboard_limit_mode: "observed"
      })

    assert HistoricalWorkflowActionOutcomePresentation.stable_attrs(
             outcome,
             "data-workflow-latest-action",
             handoff_count: 2,
             primary_result_event_id: "event-1"
           ) == %{
             "data-workflow-latest-action" => "retry_group_failed_jobs",
             "data-workflow-latest-action-count" => "3",
             "data-workflow-latest-action-dashboard-data-view" => "all_revisions",
             "data-workflow-latest-action-dashboard-id" => "dashboard-1",
             "data-workflow-latest-action-dashboard-limit-mode" => "observed",
             "data-workflow-latest-action-dashboard-replay-run-id" => "replay-1",
             "data-workflow-latest-action-dashboard-time-mode" => "replay_run",
             "data-workflow-latest-action-dashboard-version" => "7",
             "data-workflow-latest-action-failed-jobs" => "1",
             "data-workflow-latest-action-handoff-count" => 2,
             "data-workflow-latest-action-job-id" => "job-1",
             "data-workflow-latest-action-kind" => "error",
             "data-workflow-latest-action-primary-result-event-id" => "event-1",
             "data-workflow-latest-action-queued-jobs" => "2",
             "data-workflow-latest-action-reason" => "retry_group_partially_recorded",
             "data-workflow-latest-action-request-group-id" => "group-1",
             "data-workflow-latest-action-result-event-ids" => "event-1,event-2",
             "data-workflow-latest-action-retried" => "1",
             "data-workflow-latest-action-retry-error-event-ids" => "event-error",
             "data-workflow-latest-action-retry-error-items" =>
               "run=run-error event=event-error job=job-error reason=queue_down",
             "data-workflow-latest-action-retry-error-run-ids" => "run-error",
             "data-workflow-latest-action-retry-errors" => "0",
             "data-workflow-latest-action-retry-nonretryable" => "1",
             "data-workflow-latest-action-retry-nonretryable-event-ids" => "event-nonretryable",
             "data-workflow-latest-action-retry-nonretryable-items" =>
               "run=run-nonretryable event=event-nonretryable action=correct_workflow_request reason=correction_required",
             "data-workflow-latest-action-retry-nonretryable-run-ids" => "run-nonretryable",
             "data-workflow-latest-action-retry-run-ids" => "run-1-corrected",
             "data-workflow-latest-action-retry-scope" => "replacement_jobs",
             "data-workflow-latest-action-retry-skipped" => "1",
             "data-workflow-latest-action-retry-skipped-event-ids" => "event-skipped",
             "data-workflow-latest-action-retry-skipped-items" =>
               "run=run-skipped event=event-skipped job=job-skipped status=running reason=job_not_failed",
             "data-workflow-latest-action-retry-skipped-run-ids" => "run-skipped",
             "data-workflow-latest-action-stage" => "started",
             "data-workflow-latest-action-status" => "degraded",
             "data-workflow-latest-action-target-event-id" => "event-1",
             "data-workflow-latest-action-target-run-id" => "run-1"
           }
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
end
