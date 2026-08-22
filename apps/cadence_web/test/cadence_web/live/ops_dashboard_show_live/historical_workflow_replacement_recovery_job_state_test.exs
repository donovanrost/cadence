defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementRecoveryJobStateTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementRecovery

  @now ~U[2026-07-01 12:00:00Z]

  test "build marks long-running replacement jobs as stale operator work" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage started next complete",
          request_group_job_items:
            "3:HK.current run-003-corrected running job-3 event=event-3 started=2026-07-01T11:40:00Z"
        },
        @now
      )

    assert recovery.active_job_count == "1"
    assert recovery.active_run_ids == "run-003-corrected"
    assert recovery.stale_job_count == "1"
    assert recovery.stale_run_ids == "run-003-corrected"

    assert recovery.stale_summary ==
             "run-003-corrected running job-3 2026-07-01T11:40:00Z inspect_stale_replacement_job"

    assert [%{job_age_state: "stale", job_action: "inspect_stale_replacement_job"}] =
             recovery.entries
  end

  test "build derives stale replacement closure readiness before completion" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_failed: "1",
          request_group_resolved_failed: "1",
          request_group_complete_eligible: "1",
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage started next complete",
          request_group_job_items:
            "3:HK.current run-003-corrected running job-3 event=event-3 started=2026-07-01T11:40:00Z"
        },
        %{},
        @now
      )

    assert recovery.closure_readiness == %{
             status: "inspect_job_state",
             action: "inspect_stale_replacement_jobs",
             actions: "inspect_stale_replacement_jobs",
             unresolved: "0",
             pending_replacements: "1",
             completed_replacements: "0",
             active_jobs: "1",
             blocked_jobs: "0",
             failed_jobs: "0",
             failed_runs: "",
             missing_jobs: "0",
             missing_runs: "",
             stale_jobs: "1",
             stale_runs: "run-003-corrected",
             complete_eligible: "1",
             summary:
               "status inspect_job_state; action inspect_stale_replacement_jobs; unresolved 0; replacements pending 1 completed 0; jobs active 1 blocked 0 failed 0 missing 0 stale 1; complete_eligible 1"
           }
  end

  test "build keeps fresh running replacement jobs active but not stale" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage started next complete",
          request_group_job_items:
            "3:HK.current run-003-corrected running job-3 event=event-3 started=2026-07-01T11:55:30Z"
        },
        @now
      )

    assert recovery.active_job_count == "1"
    assert recovery.stale_job_count == "0"
    assert recovery.stale_run_ids == ""

    assert recovery.active_summary ==
             "run-003-corrected running job-3 monitor_running_replacement_job"
  end

  test "build blocks replacement tasks that should have missing job evidence" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage started next complete"
        },
        @now
      )

    assert recovery.blocked_job_count == "1"
    assert recovery.missing_job_count == "1"
    assert recovery.missing_run_ids == "run-003-corrected"

    assert recovery.missing_summary ==
             "run-003-corrected started next complete inspect_missing_replacement_job"

    assert recovery.job_summary ==
             "run-003-corrected missing job-missing inspect_missing_replacement_job"

    assert recovery.closure_readiness.status == "inspect_job_state"
    assert recovery.closure_readiness.action == "inspect_missing_replacement_jobs"
    assert recovery.closure_readiness.actions == "inspect_missing_replacement_jobs"
    assert recovery.closure_readiness.blocked_jobs == "1"
    assert recovery.closure_readiness.failed_jobs == "0"
    assert recovery.closure_readiness.failed_runs == ""
    assert recovery.closure_readiness.missing_jobs == "1"
    assert recovery.closure_readiness.missing_runs == "run-003-corrected"
  end

  test "build preserves failed replacement attribution for scoped retry actions" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage started next complete",
          request_group_job_items:
            "3:HK.current run-003-corrected failed job-3 event=event-3 started=2026-07-01T11:40:00Z"
        },
        @now
      )

    assert recovery.blocked_job_count == "1"
    assert recovery.failed_job_count == "1"
    assert recovery.failed_run_ids == "run-003-corrected"
    assert recovery.job_summary == "run-003-corrected failed job-3 inspect_failed_replacement_job"
    assert recovery.closure_readiness.status == "inspect_job_state"
    assert recovery.closure_readiness.action == "inspect_failed_replacement_jobs"
    assert recovery.closure_readiness.actions == "inspect_failed_replacement_jobs"
    assert recovery.closure_readiness.failed_jobs == "1"
    assert recovery.closure_readiness.failed_runs == "run-003-corrected"
    assert recovery.closure_readiness.missing_jobs == "0"
    assert recovery.closure_readiness.missing_runs == ""
  end

  test "build promotes failed replacement retry when scoped retry is eligible" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_failed: "1",
          request_group_resolved_failed: "1",
          request_group_retryable_failed: "0",
          request_group_nonretryable_failed: "0",
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage started next complete",
          request_group_job_items:
            "3:HK.current run-003-corrected failed job-3 event=event-3 started=2026-07-01T11:40:00Z"
        },
        %{
          group_retryable_failures: true,
          group_retry_action: %{
            id: "retry-group-failed",
            eligible?: true,
            eligible_count: 1,
            reason: "retryable_replacement_failure",
            preview: "Retry failed replacement job."
          }
        },
        @now
      )

    assert recovery.closure_readiness.status == "inspect_job_state"
    assert recovery.closure_readiness.action == "retry_failed_replacement_jobs"
    assert recovery.closure_readiness.actions == "retry_failed_replacement_jobs"
    assert recovery.closure_readiness.failed_jobs == "1"
    assert recovery.closure_readiness.failed_runs == "run-003-corrected"
  end

  test "build exposes every blocked replacement closure action in priority order" do
    recovery =
      HistoricalWorkflowReplacementRecovery.build(
        %{
          request_group_failed: "3",
          request_group_resolved_failed: "3",
          request_group_retryable_failed: "0",
          request_group_nonretryable_failed: "0",
          request_group_complete_eligible: "1",
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage completed next done; " <>
              "HK.power run-006 replacement run-006-corrected stage completed next done; " <>
              "HK.temp run-007 replacement run-007-corrected stage started next complete",
          request_group_job_items:
            "6:HK.power run-006-corrected failed job-6 event=event-6 started=2026-07-01T11:30:00Z; " <>
              "7:HK.temp run-007-corrected running job-7 event=event-7 started=2026-07-01T11:35:00Z"
        },
        %{
          group_retryable_failures: true,
          group_retry_action: %{
            id: "retry-group-failed",
            eligible?: true,
            eligible_count: 1,
            reason: "retryable_replacement_failure",
            preview: "Retry failed replacement job."
          }
        },
        @now
      )

    assert recovery.closure_readiness.status == "inspect_job_state"
    assert recovery.closure_readiness.action == "inspect_missing_replacement_jobs"

    assert recovery.closure_readiness.actions ==
             "inspect_missing_replacement_jobs,retry_failed_replacement_jobs,inspect_stale_replacement_jobs"

    assert recovery.closure_readiness.blocked_jobs == "2"
    assert recovery.closure_readiness.failed_jobs == "1"
    assert recovery.closure_readiness.failed_runs == "run-006-corrected"
    assert recovery.closure_readiness.missing_jobs == "1"
    assert recovery.closure_readiness.missing_runs == "run-003-corrected"
    assert recovery.closure_readiness.stale_jobs == "1"
    assert recovery.closure_readiness.stale_runs == "run-007-corrected"
    assert recovery.closure_readiness.active_jobs == "1"
  end
end
