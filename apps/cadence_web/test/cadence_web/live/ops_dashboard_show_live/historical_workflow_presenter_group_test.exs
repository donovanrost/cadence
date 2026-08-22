defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowPresenterGroupTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflowActionOutcome,
    HistoricalWorkflowPresenter
  }

  describe "grouped workflow presentation" do
    test "builds structured no-op outcome for ineligible group actions" do
      assert %HistoricalWorkflowActionOutcome{
               action: :group_stage_transition,
               status: :no_op,
               kind: :info,
               reason: "no_eligible_group_items",
               stage: "approved",
               request_group_id: "group-1",
               message:
                 "No approve items are eligible in request group group-1. The workflow panel was refreshed with current eligibility counts."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :group_stage_transition,
                 {:no_eligible, "group-1", "approved"}
               )
    end

    test "describes grouped workflow outcomes" do
      events = [:event_1, :event_2, :event_3]
      job_results = [{:ok, %{job_id: "job-1"}}, {:ok, nil}, {:error, :queue_down}]

      assert HistoricalWorkflowPresenter.group_flash("started", events, job_results) ==
               {:error,
                "Historical data workflow group started for 3 items; 1 job queued and 1 job dispatch failed."}

      assert HistoricalWorkflowPresenter.group_flash("approved", events, []) ==
               {:info, "Historical data workflow group approved recorded for 3 items."}
    end

    test "marks grouped workflow start as degraded when job dispatch fails" do
      assert %HistoricalWorkflowActionOutcome{
               action: :group_stage_transition,
               status: :degraded,
               kind: :error,
               reason: "group_started_job_dispatch_degraded",
               stage: "started",
               count: 3,
               result_event_ids: "event-1,event-2,event-3",
               target_event_id: "event-1",
               message:
                 "Historical data workflow group started for 3 items; 2 jobs queued and 1 job dispatch failed."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :group_stage_transition,
                 {:ok,
                  [
                    %{backfill_lifecycle_event_id: "event-1"},
                    %{backfill_lifecycle_event_id: "event-2"},
                    %{backfill_lifecycle_event_id: "event-3"}
                  ],
                  [{:ok, %{job_id: "job-1"}}, {:error, :queue_down}, {:ok, %{job_id: "job-3"}}]},
                 %{stage: "started"}
               )
    end

    test "describes retry and no-eligible group states" do
      summary = %{
        retried: 2,
        nonretryable: 1,
        skipped: 3,
        failed: 4,
        nonretryable_items: [
          %{
            run_id: "run-nonretryable",
            event_id: "failed-event-nonretryable",
            reason: "correction_required",
            recovery_action: "correct_workflow_request"
          }
        ],
        skipped_items: [
          %{
            run_id: "run-skipped",
            event_id: "failed-event-skipped",
            job_id: "job-skipped",
            job_status: "running",
            reason: "job_not_failed"
          }
        ],
        retry_error_items: [
          %{
            run_id: "run-004-corrected",
            event_id: "failed-event-4",
            job_id: "job-4",
            reason: "queue_down"
          }
        ]
      }

      assert HistoricalWorkflowPresenter.group_retry_flash(summary) ==
               "Retried 2 failed workflow jobs; skipped 1 non-retryable, 3 not-failed or missing, and 4 retry errors."

      assert %HistoricalWorkflowActionOutcome{
               action: :retry_group_failed_jobs,
               status: :degraded,
               kind: :error,
               reason: "retry_group_failed_jobs_degraded",
               retried: 2,
               retry_nonretryable: 1,
               retry_skipped: 3,
               retry_errors: 4,
               retry_scope: "replacement_jobs",
               retry_run_ids: "run-004-corrected",
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
               message:
                 "Retried 2 failed workflow jobs; skipped 1 non-retryable, 3 not-failed or missing, and 4 retry errors."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :retry_group_failed_jobs,
                 {:ok, summary},
                 %{retry_run_ids: ["run-004-corrected"]}
               )

      assert HistoricalWorkflowPresenter.no_eligible_group_flash("group-1", "approved") ==
               "No approve items are eligible in request group group-1. The workflow panel was refreshed with current eligibility counts."
    end
  end

  describe "group_stage_label/1" do
    test "maps workflow stage values to operator actions" do
      assert HistoricalWorkflowPresenter.group_stage_label("approved") == "approve"
      assert HistoricalWorkflowPresenter.group_stage_label("rejected") == "reject"
      assert HistoricalWorkflowPresenter.group_stage_label("started") == "start"
      assert HistoricalWorkflowPresenter.group_stage_label("completed") == "complete"
      assert HistoricalWorkflowPresenter.group_stage_label("failed") == "fail"
      assert HistoricalWorkflowPresenter.group_stage_label("requested") == "request"
      assert HistoricalWorkflowPresenter.group_stage_label("needs_review") == "needs review"
      assert HistoricalWorkflowPresenter.group_stage_label(nil) == "selected"
    end
  end
end
