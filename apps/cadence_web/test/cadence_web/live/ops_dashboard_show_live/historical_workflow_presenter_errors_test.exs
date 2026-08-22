defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowPresenterErrorsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflowActionOutcome,
    HistoricalWorkflowPresenter
  }

  test "describes structured stage transition errors without raw tuples" do
    assert %HistoricalWorkflowActionOutcome{
             reason: "stage_transition_failed",
             error:
               {:historical_workflow_stage_transition_blocked, "event-1",
                "stage_transition_out_of_order"},
             message:
               "Historical data workflow transition was blocked for event event-1: the requested stage is out of order."
           } =
             HistoricalWorkflowPresenter.action_outcome(
               :stage_transition,
               {:error,
                {:historical_workflow_stage_transition_blocked, "event-1",
                 "stage_transition_out_of_order"}},
               %{stage: "completed"}
             )

    refute HistoricalWorkflowPresenter.action_outcome(
             :stage_transition,
             {:error,
              {:historical_workflow_stage_transition_blocked, "event-1",
               "stage_transition_out_of_order"}},
             %{stage: "completed"}
           ).message =~ "{:"
  end

  test "describes structured correction request errors without raw tuples" do
    assert %HistoricalWorkflowActionOutcome{
             reason: "correction_request_failed",
             error:
               {:historical_workflow_correction_request_blocked, "failed-event-1",
                "job_status_missing"},
             message:
               "Corrected historical data workflow request was blocked for source event failed-event-1: workflow job status is missing."
           } =
             HistoricalWorkflowPresenter.action_outcome(
               :correction_request,
               {:error,
                {:historical_workflow_correction_request_blocked, "failed-event-1",
                 "job_status_missing"}}
             )
  end

  test "describes structured retry errors without raw tuples" do
    assert %HistoricalWorkflowActionOutcome{
             reason: "retry_job_failed",
             error: {:historical_workflow_retry_blocked, "failed-event-1", :job_run_mismatch},
             message:
               "Historical data workflow retry was blocked for event failed-event-1: the selected job does not belong to the selected event run."
           } =
             HistoricalWorkflowPresenter.action_outcome(
               :retry_job,
               {:error, {:historical_workflow_retry_blocked, "failed-event-1", :job_run_mismatch}}
             )

    assert %HistoricalWorkflowActionOutcome{
             reason: "retry_group_failed_jobs_failed",
             request_group_id: "request-group-1",
             error:
               {:historical_workflow_group_retry_blocked, "request-group-1",
                "no_retryable_group_failures"},
             message:
               "Historical data workflow group retry was blocked for request group request-group-1: the group has no retryable failed jobs."
           } =
             HistoricalWorkflowPresenter.action_outcome(
               :retry_group_failed_jobs,
               {:error,
                {:historical_workflow_group_retry_blocked, "request-group-1",
                 "no_retryable_group_failures"}}
             )
  end

  test "describes structured stale replacement recovery errors without raw tuples" do
    assert %HistoricalWorkflowActionOutcome{
             reason: "stale_replacement_job_requeue_failed",
             error:
               {:historical_workflow_stale_replacement_inspection_blocked, "event-stale-1",
                :job_not_stale},
             message:
               "Stale replacement job action was blocked for event event-stale-1: the selected replacement job is not stale."
           } =
             HistoricalWorkflowPresenter.action_outcome(
               :stale_replacement_job_requeue,
               {:error,
                {:historical_workflow_stale_replacement_inspection_blocked, "event-stale-1",
                 :job_not_stale}}
             )
  end

  test "describes structured missing replacement inspection errors without raw tuples" do
    assert %HistoricalWorkflowActionOutcome{
             reason: "missing_replacement_job_inspection_failed",
             error:
               {:historical_workflow_missing_replacement_inspection_blocked, "run-missing-1",
                :replacement_event_not_found},
             message:
               "Missing replacement job inspection was blocked for run run-missing-1: replacement event not found."
           } =
             HistoricalWorkflowPresenter.action_outcome(
               :missing_replacement_job_inspection,
               {:error,
                {:historical_workflow_missing_replacement_inspection_blocked, "run-missing-1",
                 :replacement_event_not_found}}
             )
  end
end
