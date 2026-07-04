defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobRecoveryPresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobRecoveryPresentation

  test "build derives retry guidance from eligible retry action" do
    presentation =
      HistoricalWorkflowJobRecoveryPresentation.build(
        %{job_status: "failed"},
        %{
          job_retryable: true,
          job_retry_action: %{
            id: "retry-job",
            eligible?: true,
            reason: "failed_job_retryable",
            preview: "Retry job job-1.",
            explanation: "This failed workflow job can be retried.",
            state_summary: "job job-1; status failed; retryable true",
            available_when: "Retry is available now."
          },
          correction_request_action: %{
            eligible?: false,
            reason: "correction_not_required",
            state_summary: "correction not required"
          }
        }
      )

    assert presentation.next_action == "retry_job"
    assert presentation.guidance == "Retry job job-1."
    assert presentation.policy_state == "job job-1; status failed; retryable true"
    assert presentation.available_when == "Retry is available now."
    assert presentation.retry.eligible == "true"
    assert presentation.retry.reason == "failed_job_retryable"
    assert presentation.retry.explanation == "This failed workflow job can be retried."
    assert presentation.retry_button.present
    assert presentation.retry_button.id == "retry-job"
    assert presentation.retry_button.eligible == "true"
    assert presentation.retry_button.reason == "failed_job_retryable"
    assert presentation.retry_button.preview == "Retry job job-1."
    assert presentation.correction.eligible == "false"
    assert presentation.correction.reason == "correction_not_required"
  end

  test "build derives correction guidance when corrected request action is eligible" do
    presentation =
      HistoricalWorkflowJobRecoveryPresentation.build(
        %{job_status: "failed"},
        %{
          job_retry_action: %{
            eligible?: false,
            reason: "correction_required",
            available_when: "Retry is blocked for non-retryable failures."
          },
          correction_requestable: true,
          correction_request_action: %{
            id: "correction-request",
            eligible?: true,
            reason: "correction_request_required",
            preview: "Create a corrected request for job job-1.",
            state_summary: "job job-1; correction required"
          }
        }
      )

    assert presentation.next_action == "create_corrected_request"
    assert presentation.guidance == "Create a corrected request for job job-1."
    assert presentation.policy_state == "job job-1; correction required"
    assert presentation.available_when == "Retry is blocked for non-retryable failures."
    assert presentation.retry.eligible == "false"
    assert presentation.retry.reason == "correction_required"
    assert presentation.correction.eligible == "true"
    assert presentation.correction.reason == "correction_request_required"
    assert presentation.correction_form.present
    assert presentation.correction_form.id == "correction-request"
    assert presentation.correction_form.eligible == "true"
    assert presentation.correction_form.reason == "correction_request_required"
    assert presentation.correction_form.preview == "Create a corrected request for job job-1."
  end

  test "build derives monitor guidance for active jobs" do
    presentation =
      HistoricalWorkflowJobRecoveryPresentation.build(
        %{job_status: "running"},
        %{
          job_retry_action: %{eligible?: false},
          correction_request_action: %{eligible?: false}
        }
      )

    assert presentation.next_action == "monitor_job"

    assert presentation.guidance ==
             "The workflow job is not terminal yet; monitor the worker outcome before recording recovery."
  end

  test "build derives inspection guidance for completed jobs" do
    presentation =
      HistoricalWorkflowJobRecoveryPresentation.build(
        %{job_status: "completed"},
        %{
          job_retry_action: %{eligible?: false},
          correction_request_action: %{eligible?: false}
        }
      )

    assert presentation.next_action == "inspect_results"

    assert presentation.guidance ==
             "The workflow job completed; inspect the resulting lifecycle event and data changes."
  end

  test "build falls back to inspect guidance for missing or invalid inputs" do
    assert HistoricalWorkflowJobRecoveryPresentation.build(nil, nil) ==
             %HistoricalWorkflowJobRecoveryPresentation{}

    presentation =
      HistoricalWorkflowJobRecoveryPresentation.build(
        %{job_status: "failed"},
        %{job_retry_action: %{eligible?: false}, correction_request_action: %{eligible?: false}}
      )

    assert presentation.next_action == "inspect_job"

    assert presentation.guidance ==
             "Inspect the workflow job status and policy details before taking action."

    assert presentation.retry_button.present == false
    assert presentation.retry_button.eligible == "false"
    assert presentation.retry_button.id == nil
    assert presentation.correction_form.present == false
    assert presentation.correction_form.eligible == "false"
    assert presentation.correction_form.id == nil
    assert presentation.retry.eligible == "false"
    assert presentation.correction.eligible == "false"
  end
end
