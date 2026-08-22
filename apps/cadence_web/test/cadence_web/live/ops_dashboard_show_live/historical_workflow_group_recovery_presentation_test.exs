defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupRecoveryPresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupRecoveryPresentation

  test "build derives visible recovery summary, item lists, unresolved count, and audit rows" do
    presentation = HistoricalWorkflowGroupRecoveryPresentation.build(group_context())

    assert presentation.visible
    assert presentation.unresolved == "1"
    assert presentation.correction_task_count == "2"

    assert presentation.handoff_summary ==
             "group request-group-1; failed; progress 2/4; jobs queued 1, failed 1; failed 3; retryable 2; correction 1; resolved 2; failed items job-1,job-2"

    assert presentation.job_items == [
             "1:HK.counter run-001 queued job-1",
             "2:HK.voltage run-002 failed job-2"
           ]

    assert presentation.retried_items == ["HK.voltage run-002 retried queued job-2"]

    assert presentation.corrected_items == [
             "HK.current run-003 corrected run-003-corrected requested job-3"
           ]

    assert presentation.correction_task_items == [
             "HK.current run-003 replacement run-003-corrected stage requested next approve",
             "HK.power run-004 replacement run-004-corrected stage approved next start"
           ]

    assert Enum.map(presentation.execution_audit_entries, & &1.key) == [
             "requested",
             "approved",
             "started",
             "job_progress",
             "completed",
             "failed",
             "retried",
             "corrected",
             "recovered",
             "recovery_tasks"
           ]

    assert presentation.execution_audit_summary ==
             "requested 4; approved 4; started 4; job_progress queued 1, failed 1; completed 2; failed 3; retried 1; corrected 1; recovered 2; recovery_tasks 2"
  end

  test "build hides recovery and suppresses empty audit rows without recovery evidence" do
    presentation =
      HistoricalWorkflowGroupRecoveryPresentation.build(%{
        request_group_id: "request-group-2",
        request_group_state: "completed",
        request_group_failed: "0",
        request_group_resolved_failed: "0",
        request_group_retry_resolved: "0",
        request_group_correction_requested: "0",
        request_group_correction_tasks: " "
      })

    refute presentation.visible
    assert presentation.unresolved == "0"
    assert presentation.correction_task_count == "0"

    assert presentation.handoff_summary ==
             "group request-group-2; completed; failed 0; resolved 0"

    assert presentation.job_items == []
    assert presentation.execution_audit_entries == []
    assert presentation.execution_audit_summary == nil
  end

  test "build defaults invalid workflow contexts to an empty presentation" do
    assert HistoricalWorkflowGroupRecoveryPresentation.build(nil) ==
             %HistoricalWorkflowGroupRecoveryPresentation{}
  end

  defp group_context do
    %{
      request_group_id: "request-group-1",
      request_group_state: "failed",
      request_group_progress: "2/4",
      request_group_job_progress: "queued 1, failed 1",
      request_group_job_items:
        "1:HK.counter run-001 queued job-1; 2:HK.voltage run-002 failed job-2",
      request_group_requested: "4",
      request_group_approved: "4",
      request_group_started: "4",
      request_group_completed: "2",
      request_group_failed: "3",
      request_group_resolved_failed: "2",
      request_group_retryable_failed: "2",
      request_group_nonretryable_failed: "1",
      request_group_retry_resolved: "1",
      request_group_correction_requested: "1",
      request_group_correction_started: "0",
      request_group_correction_completed: "0",
      request_group_correction_superseded: "0",
      request_group_retried_items: "HK.voltage run-002 retried queued job-2",
      request_group_corrected_items:
        "HK.current run-003 corrected run-003-corrected requested job-3",
      request_group_correction_tasks:
        "HK.current run-003 replacement run-003-corrected stage requested next approve; " <>
          "HK.power run-004 replacement run-004-corrected stage approved next start",
      request_group_failed_items: "job-1,job-2"
    }
  end
end
