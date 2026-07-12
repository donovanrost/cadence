defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementRecoveryActionsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementRecovery

  @now ~U[2026-07-01 12:00:00Z]

  test "build derives ready-to-complete closure when replacements and jobs are complete" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_failed: "1",
          request_group_resolved_failed: "1",
          request_group_complete_eligible: "1",
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage completed next done",
          request_group_job_items:
            "3:HK.current run-003-corrected completed job-3 event=event-3 completed=2026-07-01T11:59:00Z"
        },
        %{
          group_stage_actions: [
            %{
              id: "group-stage-completed",
              stage: "completed",
              eligible?: true,
              disabled?: false,
              eligible_count: "1",
              reason: "all_group_items_resolved",
              preview: "Record completion for 1 resolved request group."
            }
          ]
        },
        @now
      )

    assert recovery.closure_readiness.status == "ready_to_complete"
    assert recovery.closure_readiness.action == "complete_group"
    assert recovery.closure_readiness.actions == "complete_group"
    assert recovery.closure_readiness.completed_replacements == "1"
    assert recovery.closure_readiness.complete_eligible == "1"

    assert recovery.completion_action == %{
             present: true,
             id: "group-stage-completed",
             stage: "completed",
             eligible: "true",
             eligible_bool: true,
             disabled_bool: false,
             count: "1",
             reason: "all_group_items_resolved",
             preview: "Record completion for 1 resolved request group.",
             submit_reason: "dashboard_recovery_group_completed"
           }
  end

  test "build derives operator action closure from retry controls while failures remain unresolved" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_failed: "2",
          request_group_resolved_failed: "0",
          request_group_retryable_failed: "1",
          request_group_nonretryable_failed: "1"
        },
        %{
          group_retryable_failures: true,
          group_retry_action: %{
            id: "retry-group-failed",
            eligible?: true,
            eligible_count: 1,
            reason: "retryable_group_failures",
            preview: "Retry one failed item.",
            explanation: "Retry failed jobs in this request group.",
            state_summary: "group retry state",
            available_when: "Retry is available now."
          }
        },
        @now
      )

    assert recovery.next_action == "retry_failed_items"
    assert recovery.retry_count == "1"
    assert recovery.guidance == "Retry one failed item."
    assert recovery.retry_action.present
    assert recovery.retry_action.id == "retry-group-failed"
    assert recovery.retry_action.eligible == "true"
    assert recovery.retry_action.eligible_bool == true
    assert recovery.retry_action.count == "1"
    assert recovery.retry_action.reason == "retryable_group_failures"
    assert recovery.retry_action.preview == "Retry one failed item."
    assert recovery.retry_action.explanation == "Retry failed jobs in this request group."
    assert recovery.retry_action.state == "group retry state"
    assert recovery.retry_action.available_when == "Retry is available now."

    assert recovery.expected_effect ==
             "Retry will requeue 1 failed item and select the retried lifecycle event."

    assert recovery.blockers == nil
    assert recovery.closure_readiness.status == "operator_action_required"
    assert recovery.closure_readiness.action == "retry_failed_items"
    assert recovery.closure_readiness.actions == "retry_failed_items"
    assert recovery.closure_readiness.unresolved == "2"
  end

  test "build derives correction guidance when unresolved failures are not retryable" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_failed: "2",
          request_group_resolved_failed: "0",
          request_group_retryable_failed: "0",
          request_group_nonretryable_failed: "2"
        },
        %{},
        @now
      )

    assert recovery.next_action == "create_corrected_requests"
    assert recovery.retry_count == "0"
    assert recovery.correction_task_count == "0"

    assert recovery.guidance ==
             "Create corrected workflow requests for non-retryable failed items."

    assert recovery.expected_effect ==
             "Create corrected requests for 2 non-retryable failures."

    assert recovery.blockers ==
             "Non-retryable failures require corrected workflow requests from their failed-item inspectors."
  end

  test "build derives inspection blockers when no group recovery action is executable" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_failed: "1",
          request_group_resolved_failed: "0",
          request_group_retryable_failed: "0",
          request_group_nonretryable_failed: "0"
        },
        %{
          group_retry_action: %{
            eligible?: false,
            available_when: "Retry is available after failed job evidence is selected."
          }
        },
        @now
      )

    assert recovery.next_action == "inspect_failed_items"

    assert recovery.guidance ==
             "Inspect failed items to decide whether retry or correction is required."

    assert recovery.expected_effect ==
             "Inspect failed item evidence before executing retry or correction."

    assert recovery.blockers == "Retry is available after failed job evidence is selected."
  end

  test "build packages the executable corrected replacement advancement action" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage requested next approve"
        },
        %{
          group_stage_actions: [
            %{
              id: "group-stage-approved",
              stage: "approved",
              eligible?: true,
              eligible_count: 3,
              reason: "eligible_group_items",
              correction_tasks:
                "HK.current run-003 replacement run-003-corrected stage requested next approve"
            }
          ]
        },
        @now
      )

    assert recovery.replacement_action == %{
             present: true,
             id: "group-stage-approved",
             stage: "approved",
             eligible: "true",
             eligible_bool: true,
             disabled_bool: false,
             count: "1",
             reason: "eligible_group_items",
             preview: "Advance 1 corrected replacement request to approved.",
             correction_tasks:
               "HK.current run-003 replacement run-003-corrected stage requested next approve",
             submit_reason: "dashboard_recovery_replacement_approved"
           }
  end

  test "build exposes disabled corrected replacement fallback action when no action is eligible" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage requested next approve; " <>
              "HK.voltage run-004 replacement run-004-corrected stage requested next approve"
        },
        %{
          group_stage_actions: [
            %{
              id: "group-stage-approved",
              stage: "approved",
              eligible?: false,
              eligible_count: "2",
              reason: "blocked_until_reviewed",
              correction_tasks:
                "HK.current run-003 replacement run-003-corrected stage requested next approve; " <>
                  "HK.voltage run-004 replacement run-004-corrected stage requested next approve"
            }
          ]
        },
        @now
      )

    assert recovery.replacement_action.present
    assert recovery.replacement_action.eligible == "false"
    assert recovery.replacement_action.eligible_bool == false
    assert recovery.replacement_action.disabled_bool == true
    assert recovery.replacement_action.count == "2"

    assert recovery.replacement_action.preview ==
             "Advance 2 corrected replacement requests to approved."

    assert recovery.replacement_action.submit_reason == "dashboard_recovery_replacement_approved"
  end

  test "build packages disabled group completion action metadata" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_failed: "1",
          request_group_resolved_failed: "1",
          request_group_complete_eligible: "1"
        },
        %{
          group_stage_actions: [
            %{
              id: "group-stage-completed",
              stage: "completed",
              eligible?: false,
              disabled?: true,
              eligible_count: 0,
              reason: "replacement_work_pending",
              preview: "Complete the group after replacement work closes."
            }
          ]
        },
        @now
      )

    assert recovery.completion_action == %{
             present: true,
             id: "group-stage-completed",
             stage: "completed",
             eligible: "false",
             eligible_bool: false,
             disabled_bool: true,
             count: "0",
             reason: "replacement_work_pending",
             preview: "Complete the group after replacement work closes.",
             submit_reason: "dashboard_recovery_group_completed"
           }
  end
end
