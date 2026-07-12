defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowPresenterTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflowActionOutcome,
    HistoricalWorkflowPresenter
  }

  describe "flash copy" do
    test "builds structured action outcomes for direct stage transitions" do
      assert %HistoricalWorkflowActionOutcome{
               action: :stage_transition,
               status: :ok,
               kind: :info,
               reason: "stage_recorded_job_queued",
               stage: "started",
               job_id: "job-1",
               dashboard_context: %{
                 dashboard_id: "dashboard-1",
                 dashboard_version: "7",
                 dashboard_time_mode: "replay_run",
                 dashboard_replay_run_id: "replay-1",
                 dashboard_data_view: "all_revisions",
                 dashboard_limit_mode: "observed"
               },
               message: "Historical data workflow started recorded and job job-1 queued."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :stage_transition,
                 {:ok, {:ok, %{job_id: "job-1"}}},
                 %{
                   stage: "started",
                   dashboard_id: "dashboard-1",
                   dashboard_version: 7,
                   dashboard_time_mode: "replay_run",
                   dashboard_replay_run_id: "replay-1",
                   dashboard_data_view: "all_revisions",
                   dashboard_limit_mode: "observed"
                 }
               )

      assert %HistoricalWorkflowActionOutcome{
               action: :stage_transition,
               status: :blocked,
               kind: :error,
               reason: "confirmation_required",
               stage: "approved",
               message:
                 "Confirm the historical data workflow approved transition before recording it."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :stage_transition,
                 :unconfirmed,
                 %{stage: "approved"}
               )
    end

    test "builds structured action outcomes for requests and retries" do
      assert %HistoricalWorkflowActionOutcome{
               action: :request,
               status: :ok,
               kind: :info,
               reason: "request_group_recorded",
               count: 2,
               message: "Historical data workflow request group recorded for 2 points."
             } =
               HistoricalWorkflowPresenter.action_outcome(:request, {:ok, [:event_1, :event_2]})

      assert %HistoricalWorkflowActionOutcome{
               action: :request,
               status: :ok,
               reason: "request_group_recorded",
               count: 2,
               result_event_ids: "event-1,event-2",
               target_event_id: "event-1",
               target_run_id: "run-1"
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :request,
                 {:ok,
                  [
                    %{backfill_lifecycle_event_id: "event-1", backfill_run_id: "run-1"},
                    %{backfill_lifecycle_event_id: "event-2", backfill_run_id: "run-2"}
                  ]},
                 %{target_run_id: "run-1"}
               )

      assert %HistoricalWorkflowActionOutcome{
               action: :correction_request,
               result_event_ids: "correction-event-1",
               target_event_id: "correction-event-1",
               target_run_id: "correction-run-1"
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :correction_request,
                 {:ok,
                  %{
                    backfill_lifecycle_event_id: "correction-event-1",
                    backfill_run_id: "correction-run-1"
                  }},
                 %{target_run_id: "correction-run-1"}
               )

      assert %HistoricalWorkflowActionOutcome{
               action: :retry_job,
               status: :error,
               kind: :error,
               reason: "retry_job_failed",
               error: :job_not_found,
               message: "Failed to retry historical data workflow job: job not found"
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :retry_job,
                 {:error, :job_not_found}
               )

      assert %HistoricalWorkflowActionOutcome{
               action: :stale_replacement_job_requeue,
               status: :ok,
               kind: :info,
               reason: "stale_replacement_job_requeue_recorded",
               job_id: "job-stale-1",
               result_event_ids: "event-stale-requeue-1",
               target_event_id: "event-stale-requeue-1",
               target_run_id: "run-stale-1",
               message: "Requeued stale replacement job job-stale-1 and recorded audit event."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :stale_replacement_job_requeue,
                 {:ok, %{job_id: "job-stale-1"},
                  %{
                    backfill_lifecycle_event_id: "event-stale-requeue-1",
                    backfill_run_id: "run-stale-1"
                  }},
                 %{target_event_id: "event-stale-requeue-1", target_run_id: "run-stale-1"}
               )
    end

    test "builds missing replacement inspection action outcomes" do
      assert %HistoricalWorkflowActionOutcome{
               action: :missing_replacement_job_inspection,
               status: :ok,
               kind: :info,
               reason: "missing_replacement_job_inspection_recorded",
               result_event_ids: "event-missing-inspection-1",
               target_event_id: "event-missing-inspection-1",
               target_run_id: "run-missing-1",
               message: "Recorded missing replacement job inspection."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :missing_replacement_job_inspection,
                 {:ok,
                  %{
                    backfill_lifecycle_event_id: "event-missing-inspection-1",
                    backfill_run_id: "run-missing-1"
                  }},
                 %{
                   target_event_id: "event-missing-inspection-1",
                   target_run_id: "run-missing-1"
                 }
               )
    end

    test "normalizes action outcomes for rendered metadata" do
      assert %{
               action: "stage_transition",
               status: "ok",
               kind: "info",
               reason: "stage_recorded_job_queued",
               stage: "started",
               count: "3",
               job_id: "job-1",
               result_event_ids: "event-1,event-2",
               message: "queued"
             } =
               HistoricalWorkflowPresenter.action_attrs(%{
                 action: :stage_transition,
                 status: :ok,
                 kind: :info,
                 reason: "stage_recorded_job_queued",
                 stage: "started",
                 count: 3,
                 job_id: "job-1",
                 retry_scope: :replacement_jobs,
                 retry_run_ids: ["run-004-corrected", "run-005-corrected"],
                 result_event_ids: "event-1,event-2",
                 request_group_id: nil,
                 message: "queued"
               })

      assert %{
               retry_scope: "replacement_jobs",
               retry_run_ids: "run-004-corrected,run-005-corrected",
               retry_error_run_ids: "run-004-corrected",
               retry_error_event_ids: "failed-event-4",
               retry_error_items:
                 "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down"
             } =
               HistoricalWorkflowPresenter.action_attrs(%{
                 action: :retry_group_failed_jobs,
                 retry_scope: :replacement_jobs,
                 retry_run_ids: "run-004-corrected, run-005-corrected",
                 retry_error_run_ids: "run-004-corrected",
                 retry_error_event_ids: "failed-event-4",
                 retry_error_items:
                   "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down"
               })

      refute Map.has_key?(
               HistoricalWorkflowPresenter.action_attrs(%{
                 action: :request,
                 status: :ok,
                 kind: :info,
                 reason: "request_recorded",
                 stage: "",
                 message: "recorded"
               }),
               :stage
             )
    end

    test "normalizes action outcome target scope for inline workflow presentation" do
      assert %{
               action: "stage_transition",
               target_event_id: "event-1",
               target_run_id: "run-1",
               message: "recorded"
             } =
               HistoricalWorkflowPresenter.action_attrs(%{
                 action: :stage_transition,
                 status: :ok,
                 kind: :info,
                 reason: "stage_recorded",
                 target_event_id: "event-1",
                 target_run_id: "run-1",
                 message: "recorded"
               })
    end

    test "describes single and grouped workflow requests" do
      assert HistoricalWorkflowPresenter.request_flash([:event]) ==
               "Historical data workflow request recorded."

      assert HistoricalWorkflowPresenter.request_flash([:event_1, :event_2]) ==
               "Historical data workflow request group recorded for 2 points."
    end

    test "describes direct workflow stage outcomes" do
      assert HistoricalWorkflowPresenter.workflow_flash("started", {:ok, %{job_id: "job-1"}}) ==
               {:info, "Historical data workflow started recorded and job job-1 queued."}

      assert HistoricalWorkflowPresenter.workflow_flash("approved", {:ok, nil}) ==
               {:info, "Historical data workflow approved recorded."}

      assert HistoricalWorkflowPresenter.workflow_flash("started", {:error, :queue_down}) ==
               {:error,
                "Historical data workflow started recorded, but job dispatch failed: queue down"}
    end
  end
end
