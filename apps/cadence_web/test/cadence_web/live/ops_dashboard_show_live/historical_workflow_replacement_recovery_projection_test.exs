defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementRecoveryProjectionTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementRecovery

  @now ~U[2026-07-01 12:00:00Z]

  test "build derives replacement entries and aggregate presentation fields" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage requested next approve; " <>
              "HK.voltage run-002 replacement run-002-corrected stage completed next done",
          request_group_job_items:
            "2:HK.voltage run-002-corrected completed job-2 event=event-2 completed=2026-07-01T11:59:00Z"
        },
        @now
      )

    assert recovery.total_count == "2"
    assert recovery.pending_count == "1"
    assert recovery.completed_count == "1"
    assert recovery.next_actions == "approve"
    assert recovery.pending_runs == "run-003-corrected"
    assert recovery.next_action == "advance_corrected_requests"
    assert recovery.retry_count == "0"
    assert recovery.correction_task_count == "2"

    assert recovery.guidance ==
             "Advance corrected replacement requests through their remaining workflow stages."

    assert recovery.expected_effect ==
             "Advance 2 corrected replacement requests through the remaining workflow stages."

    assert recovery.blockers == nil

    assert recovery.work_summary ==
             "run-003-corrected requested next approve pending; run-002-corrected completed next done complete"

    assert recovery.job_summary ==
             "run-002-corrected completed job-2 replacement_complete"

    assert [
             %{
               source: "HK.current run-003",
               replacement_run: "run-003-corrected",
               stage: "requested",
               next_action: "approve",
               status: "pending",
               job_status: "",
               job_action: "advance_replacement_request"
             },
             %{
               replacement_run: "run-002-corrected",
               stage: "completed",
               next_action: "done",
               status: "complete",
               job_status: "completed",
               job_action: "replacement_complete",
               event_id: "event-2",
               job_id: "job-2"
             }
           ] = recovery.entries
  end

  test "build defaults invalid or absent workflow contexts to an empty projection" do
    assert HistoricalWorkflowReplacementRecovery.build(nil, @now) ==
             %HistoricalWorkflowReplacementRecovery{}

    assert HistoricalWorkflowReplacementRecovery.empty() ==
             %HistoricalWorkflowReplacementRecovery{}

    assert HistoricalWorkflowReplacementRecovery.empty().completion_action.present == false
    assert HistoricalWorkflowReplacementRecovery.empty().completion_action.stage == "completed"
    assert HistoricalWorkflowReplacementRecovery.empty().completion_action.count == "0"
    assert HistoricalWorkflowReplacementRecovery.empty().retry_action.present == false
    assert HistoricalWorkflowReplacementRecovery.empty().retry_action.eligible == "false"
    assert HistoricalWorkflowReplacementRecovery.empty().retry_action.count == "0"
  end
end
