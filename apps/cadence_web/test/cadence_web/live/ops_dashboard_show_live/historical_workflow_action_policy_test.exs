defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionPolicyTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflowActionPolicy,
    HistoricalWorkflowActionPolicyAction
  }

  describe "build/1" do
    test "marks individual stage actions with eligibility reasons and previews" do
      [requested, approved, started] =
        HistoricalWorkflowActionPolicy.stage_actions(
          %{
            workflow: "backfill",
            stage: "requested",
            run_id: "run-1"
          },
          [
            %{stage: "requested", label: "Request"},
            %{stage: "approved", label: "Approve"},
            %{stage: "started", label: "Start"}
          ]
        )

      assert requested.id == "stage_requested"
      assert %HistoricalWorkflowActionPolicyAction{} = requested
      assert %HistoricalWorkflowActionPolicyAction{} = approved
      assert %HistoricalWorkflowActionPolicyAction{} = started
      refute requested.eligible?
      assert requested.disabled?
      assert requested.reason == "already_in_stage"
      assert requested.preview == "request transition is not currently eligible"
      assert requested.explanation == "Request is already the current workflow stage."
      assert requested.state_summary == "current stage requested"

      assert requested.available_when ==
               "Choose a transition that advances or changes the current stage."

      assert approved.eligible?
      refute approved.disabled?
      assert approved.reason == "stage_transition_available"
      assert approved.preview == "Record approve transition for run run-1"
      assert approved.explanation == "This workflow transition can be recorded now."
      assert approved.state_summary == "current stage requested"
      assert is_nil(approved.available_when)

      refute started.eligible?
      assert started.reason == "stage_transition_out_of_order"
      assert started.explanation == "Start does not follow the current workflow stage."
      assert started.state_summary == "current stage requested"

      assert started.available_when ==
               "Record the prerequisite workflow stage before this transition."
    end

    test "blocks individual start action when a job already exists" do
      [started] =
        HistoricalWorkflowActionPolicy.stage_actions(
          %{
            workflow: "backfill",
            stage: "approved",
            run_id: "run-1",
            job_id: "job-1",
            job_status: "queued"
          },
          [%{stage: "started", label: "Start"}]
        )

      assert %HistoricalWorkflowActionPolicyAction{} = started
      refute started.eligible?
      assert started.disabled?
      assert started.reason == "job_already_exists"
      assert started.explanation == "A workflow job is already recorded for this run."
      assert started.state_summary == "job job-1; status queued"

      assert started.available_when ==
               "Resolve or inspect the existing workflow job before starting another one."
    end

    test "marks group stage actions with eligible counts and previews" do
      [approved, completed] =
        HistoricalWorkflowActionPolicy.group_stage_actions(
          %{
            request_group_id: "group-1",
            request_group_approve_eligible: "2",
            request_group_complete_eligible: 0
          },
          [
            %{stage: "approved", label: "Approve"},
            %{stage: "completed", label: "Complete"}
          ]
        )

      assert approved.id == "group_stage_approved"
      assert %HistoricalWorkflowActionPolicyAction{} = approved
      assert %HistoricalWorkflowActionPolicyAction{} = completed
      assert approved.eligible?
      assert approved.eligible_count == 2
      assert approved.reason == "eligible_group_items"

      assert approved.preview ==
               "Record approve transition for 2 eligible items in request group group-1"

      assert approved.state_summary == "group group-1; progress unknown; eligible 2 for approved"

      refute completed.eligible?
      assert completed.disabled?
      assert completed.reason == "no_eligible_group_items"
      assert completed.preview == "No request-group items are eligible for complete"
      assert completed.explanation == "No request-group items are eligible for complete."

      assert completed.state_summary ==
               "group group-1; progress unknown; eligible 0 for completed"

      assert completed.available_when == "At least one item must become eligible for complete."
    end

    test "marks retry action eligible for a failed retryable job" do
      actions =
        HistoricalWorkflowActionPolicy.build(%{
          request_group_id: "group-1",
          request_group_retryable_failed: "2",
          event_id: "event-1",
          job_id: "job-1",
          job_status: "failed",
          retryable: "true",
          recovery_action: "retry_job"
        })

      assert %HistoricalWorkflowActionPolicyAction{} = actions.retry_job
      assert %HistoricalWorkflowActionPolicyAction{} = actions.retry_group_failed_jobs
      assert %HistoricalWorkflowActionPolicyAction{} = actions.correction_request
      assert actions.retry_job.eligible?
      refute actions.retry_job.disabled?
      assert actions.retry_job.reason == "failed_job_retryable"
      assert actions.retry_job.preview == "Retry failed job job-1 from event event-1"

      assert actions.retry_job.state_summary ==
               "job job-1; status failed; retryable true; recovery retry_job"

      assert actions.retry_group_failed_jobs.eligible?
      assert actions.retry_group_failed_jobs.eligible_count == 2
      assert actions.retry_group_failed_jobs.reason == "retryable_group_failures"

      assert actions.retry_group_failed_jobs.state_summary ==
               "group group-1; progress unknown; retryable failed 2; nonretryable failed unknown"

      refute actions.correction_request.eligible?
      assert actions.correction_request.reason == "correction_not_required"
    end

    test "makes correction-required failures exclusive with retry" do
      actions =
        HistoricalWorkflowActionPolicy.build(%{
          request_group_id: "group-1",
          request_group_retryable_failed: "0",
          event_id: "event-1",
          job_id: "job-1",
          job_status: "failed",
          retryable: "true",
          recovery_action: "correct_workflow_request"
        })

      refute actions.retry_job.eligible?
      assert actions.retry_job.disabled?
      assert actions.retry_job.reason == "correction_required"

      assert actions.retry_job.state_summary ==
               "job job-1; status failed; retryable true; recovery correct_workflow_request"

      assert actions.retry_job.explanation ==
               "This failure requires a corrected workflow request."

      assert actions.retry_job.available_when ==
               "Create a corrected workflow request instead of retrying this job."

      assert actions.correction_request.eligible?
      assert actions.correction_request.reason == "correction_request_required"

      assert actions.correction_request.state_summary ==
               "job job-1; status failed; retryable true; recovery correct_workflow_request"
    end

    test "captures ineligible retry and correction reasons" do
      actions =
        HistoricalWorkflowActionPolicy.build(%{
          request_group_id: "group-1",
          request_group_retryable_failed: "0",
          event_id: "event-1",
          job_id: "job-1",
          job_status: "completed",
          retryable: "false",
          recovery_action: "retry_job"
        })

      refute actions.retry_job.eligible?
      assert actions.retry_job.disabled?
      assert actions.retry_job.reason == "job_not_failed"
      assert actions.retry_job.explanation == "The workflow job is not failed."

      assert actions.retry_job.state_summary ==
               "job job-1; status completed; retryable false; recovery retry_job"

      assert actions.retry_job.available_when == "Retry becomes available after a job fails."

      refute actions.retry_group_failed_jobs.eligible?
      assert actions.retry_group_failed_jobs.reason == "no_retryable_group_failures"

      assert actions.retry_group_failed_jobs.explanation ==
               "This request group has no retryable failed workflow jobs."

      assert actions.retry_group_failed_jobs.state_summary ==
               "group group-1; progress unknown; retryable failed 0; nonretryable failed unknown"

      refute actions.correction_request.eligible?
      assert actions.correction_request.reason == "job_not_failed"
      assert actions.correction_request.explanation == "The workflow job is not failed."

      assert actions.correction_request.state_summary ==
               "job job-1; status completed; retryable false; recovery retry_job"
    end
  end
end
