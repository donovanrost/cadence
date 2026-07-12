defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupClosureStatusComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStatusComponents

  test "group_status renders closure readiness for pending, monitoring, and complete states" do
    base_controls = %{
      group_summary: true,
      group_retryable_failures: false,
      group_retry_action: nil,
      group_stage_actions: [
        %{
          id: "group-stage-completed",
          stage: "completed",
          eligible?: true,
          disabled?: false,
          eligible_count: 1,
          reason: "eligible_group_items",
          preview: "Record complete transition for 1 eligible replacement item."
        }
      ]
    }

    replacement_pending =
      render_group_status(
        group_context()
        |> Map.merge(%{
          request_group_job_progress: "completed 2",
          request_group_failed: "2",
          request_group_resolved_failed: "2",
          request_group_retryable_failed: "0",
          request_group_nonretryable_failed: "0",
          request_group_complete_eligible: "0",
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage approved next start"
        }),
        Map.put(base_controls, :group_stage_actions, [
          %{
            id: "group-stage-started",
            stage: "started",
            eligible?: true,
            eligible_count: 1,
            reason: "eligible_group_items",
            preview: "Record start transition for 1 eligible replacement item.",
            correction_tasks:
              "HK.current run-003 replacement run-003-corrected stage approved next start"
          }
        ])
      )

    assert closure_attrs(replacement_pending) == %{
             "status" => "replacement_work_pending",
             "action" => "advance_corrected_requests",
             "active" => "0",
             "blocked" => "0",
             "failed" => "0",
             "missing" => "0",
             "stale" => "0"
           }

    monitor_jobs =
      render_group_status(
        group_context()
        |> Map.merge(%{
          request_group_job_progress: "queued 1, completed 1",
          request_group_failed: "2",
          request_group_resolved_failed: "2",
          request_group_retryable_failed: "0",
          request_group_nonretryable_failed: "0",
          request_group_complete_eligible: "0",
          request_group_job_items: "3:HK.current run-003-corrected queued job-3",
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage completed next done"
        }),
        base_controls
      )

    assert closure_attrs(monitor_jobs) == %{
             "status" => "monitor_jobs",
             "action" => "monitor_replacement_jobs",
             "active" => "1",
             "blocked" => "0",
             "failed" => "0",
             "missing" => "0",
             "stale" => "0"
           }

    ready_to_complete =
      render_group_status(
        group_context()
        |> Map.merge(%{
          request_group_job_progress: "completed 2",
          request_group_failed: "2",
          request_group_resolved_failed: "2",
          request_group_retryable_failed: "0",
          request_group_nonretryable_failed: "0",
          request_group_complete_eligible: "1",
          request_group_job_items: "3:HK.current run-003-corrected completed job-3",
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage completed next done"
        }),
        base_controls
      )

    assert closure_attrs(ready_to_complete) == %{
             "status" => "ready_to_complete",
             "action" => "complete_group",
             "active" => "0",
             "blocked" => "0",
             "failed" => "0",
             "missing" => "0",
             "stale" => "0"
           }

    assert ["record_historical_workflow_group_stage"] =
             ready_to_complete
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-complete-form")
             |> LazyHTML.attribute("phx-submit")
  end

  test "group_status prioritizes blocked replacement-job recovery over completion" do
    html =
      render_group_status(
        group_context()
        |> Map.merge(%{
          request_group_job_progress: "running 1, failed 1, missing 1",
          request_group_job_items:
            "6:HK.power run-006-corrected failed job-6 event=event-6 started=2026-07-01T11:30:00Z; " <>
              "7:HK.temp run-007-corrected running job-7 event=event-7 started=2023-11-14T22:00:00Z",
          request_group_failed: "3",
          request_group_resolved_failed: "3",
          request_group_retryable_failed: "0",
          request_group_nonretryable_failed: "0",
          request_group_complete_eligible: "1",
          request_group_correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage completed next done; " <>
              "HK.power run-006 replacement run-006-corrected stage completed next done; " <>
              "HK.temp run-007 replacement run-007-corrected stage started next complete"
        }),
        %{
          workflow_controls()
          | group_retry_action: %{
              id: "group-retry-failed-items",
              eligible?: true,
              eligible_count: 1,
              reason: "retryable_replacement_failure",
              preview: "Retry 1 failed replacement job."
            }
        }
      )

    assert ["inspect_missing_replacement_jobs"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-action")

    assert [
             "inspect_missing_replacement_jobs,retry_failed_replacement_jobs,inspect_stale_replacement_jobs"
           ] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-actions")

    assert ["run-006-corrected"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-failed-runs")

    assert ["run-003-corrected"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-missing-runs")

    assert ["run-007-corrected"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-stale-runs")

    assert [] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-complete-form")
             |> LazyHTML.attribute("phx-submit")
  end

  defp workflow_controls do
    %{
      group_summary: true,
      group_retryable_failures: true,
      group_retry_action: %{
        id: "retry-group-failed",
        eligible?: true,
        eligible_count: 2,
        reason: "retryable_group_failures",
        preview: "Retry every retryable failed job.",
        explanation: "This request group has retryable failed workflow jobs.",
        state_summary:
          "group request-group-1; progress 2/4; retryable failed 2; nonretryable failed 0"
      },
      group_stage_actions: [
        %{
          id: "group-stage-approved",
          stage: "approved",
          eligible?: true,
          eligible_count: 1,
          reason: "eligible_group_items",
          preview: "Record approve transition for 1 eligible replacement item.",
          correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage requested next approve"
        }
      ]
    }
  end

  defp render_group_status(workflow_context, workflow_controls) do
    render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
      workflow_context: workflow_context,
      workflow_controls: workflow_controls,
      dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
    )
    |> LazyHTML.from_fragment()
  end

  defp closure_attrs(document) do
    closure =
      LazyHTML.query(
        document,
        "#dashboard-historical-workflow-group-recovery-closure-readiness"
      )

    %{
      "status" =>
        closure
        |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-status")
        |> List.first(),
      "action" =>
        closure
        |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-action")
        |> List.first(),
      "active" =>
        closure
        |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-active-jobs")
        |> List.first(),
      "blocked" =>
        closure
        |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-blocked-jobs")
        |> List.first(),
      "failed" =>
        closure
        |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-failed-jobs")
        |> List.first(),
      "missing" =>
        closure
        |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-missing-jobs")
        |> List.first(),
      "stale" =>
        closure
        |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-stale-jobs")
        |> List.first()
    }
  end

  defp group_context do
    %{
      event_id: "source-event-1",
      request_group_id: "request-group-1",
      request_group_state: "failed",
      request_group_terminal: "false",
      request_group_size: "4",
      request_group_progress: "2/4",
      request_group_job_progress: "queued 1, failed 1",
      request_group_job_items:
        "1:HK.counter run-001 queued job-1; 2:HK.voltage run-002 failed job-2",
      request_group_requested: "4",
      request_group_approved: "4",
      request_group_started: "4",
      request_group_completed: "2",
      request_group_failed: "2",
      request_group_resolved_failed: "0",
      request_group_retry_resolved: "0",
      request_group_correction_requested: "0",
      request_group_correction_started: "0",
      request_group_correction_completed: "0",
      request_group_correction_superseded: "0",
      request_group_request_eligible: "false",
      request_group_approve_eligible: "false",
      request_group_reject_eligible: "false",
      request_group_start_eligible: "false",
      request_group_complete_eligible: "false",
      request_group_fail_eligible: "false",
      request_group_retryable_failed: "2",
      request_group_nonretryable_failed: "0",
      comparison_review_request_event_id: "review-request-1",
      comparison_review_request_kind: "comparison_open_findings_review",
      comparison_review_open_count: "2",
      comparison_review_open_placement_ids: "placement-1,placement-2",
      comparison_review_workflow_kind: "bulk_correction_authority_review",
      comparison_review_workflow_action: "request_comparison_review",
      comparison_review_workflow_selection_kind: "open_comparison_findings",
      comparison_review_workflow_selection_count: "2",
      comparison_review_primary_data_view: "all_revisions",
      comparison_review_compare_data_view: "canonical",
      request_group_retried_items: "HK.voltage run-002 retried queued job-2",
      request_group_corrected_items:
        "HK.current run-003 corrected run-003-corrected requested job-3",
      request_group_correction_tasks:
        "HK.current run-003 replacement run-003-corrected stage requested next approve",
      request_group_failed_items: "job-1,job-2",
      request_group_failed_item_events:
        "label=HK%20voltage%20bus run=run-002 event=failed-event-2 recovery=retry_job retryable=true; label=HK.current run=run-003 event=failed-event-3 recovery=correct_workflow_request retryable=false"
    }
  end
end
