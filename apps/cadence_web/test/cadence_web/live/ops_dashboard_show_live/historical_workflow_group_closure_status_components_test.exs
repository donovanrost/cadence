defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupClosureStatusComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStatusComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementStatusComponents

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

    ready_closure = closure_readiness_presentation(ready_to_complete)

    assert ready_closure == %{
             "id" => "dashboard-historical-workflow-group-recovery-closure-readiness",
             "class" => "mt-2 space-y-2 rounded border border-info/30 bg-info/5 p-2",
             "attrs" => %{
               "data-historical-workflow-group-recovery-closure-status" => "ready_to_complete",
               "data-historical-workflow-group-recovery-closure-action" => "complete_group",
               "data-historical-workflow-group-recovery-closure-actions" => "complete_group",
               "data-historical-workflow-group-recovery-closure-unresolved" => "0",
               "data-historical-workflow-group-recovery-closure-pending-replacements" => "0",
               "data-historical-workflow-group-recovery-closure-completed-replacements" => "1",
               "data-historical-workflow-group-recovery-closure-active-jobs" => "0",
               "data-historical-workflow-group-recovery-closure-blocked-jobs" => "0",
               "data-historical-workflow-group-recovery-closure-failed-jobs" => "0",
               "data-historical-workflow-group-recovery-closure-failed-runs" => "",
               "data-historical-workflow-group-recovery-closure-missing-jobs" => "0",
               "data-historical-workflow-group-recovery-closure-missing-runs" => "",
               "data-historical-workflow-group-recovery-closure-stale-jobs" => "0",
               "data-historical-workflow-group-recovery-closure-stale-runs" => "",
               "data-historical-workflow-group-recovery-closure-complete-eligible" => "1",
               "data-historical-workflow-group-recovery-closure-summary" =>
                 "status ready_to_complete; action complete_group; unresolved 0; replacements pending 0 completed 1; jobs active 0 blocked 0 failed 0 missing 0 stale 0; complete_eligible 1"
             },
             "header" => %{
               "class" => "flex items-center justify-between gap-2",
               "label" => text_presentation("hud-label", "Closure Readiness"),
               "status" =>
                 text_presentation("font-mono text-base-content/70", "ready_to_complete")
             },
             "details" => %{
               "class" => "grid grid-cols-[8rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs",
               "rows" => [
                 closure_detail("action", "Action", "font-mono break-all", "complete_group"),
                 closure_detail(
                   "action-queue",
                   "Action queue",
                   "font-mono break-all",
                   "complete_group"
                 ),
                 closure_detail("unresolved", "Unresolved", "font-mono", "0"),
                 closure_detail(
                   "replacements",
                   "Replacements",
                   "font-mono",
                   "0 pending / 1 complete"
                 ),
                 closure_detail(
                   "jobs",
                   "Jobs",
                   "font-mono",
                   "0 active / 0 blocked / 0 failed / 0 missing / 0 stale"
                 )
               ]
             },
             "completion_form" => completion_form_presentation()
           }

    assert ready_closure["completion_form"]["attrs"]["phx-submit"] ==
             "record_historical_workflow_group_stage"
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

    closure = closure_readiness_presentation(html)

    assert closure["attrs"] == %{
             "data-historical-workflow-group-recovery-closure-status" => "inspect_job_state",
             "data-historical-workflow-group-recovery-closure-action" =>
               "inspect_missing_replacement_jobs",
             "data-historical-workflow-group-recovery-closure-actions" =>
               "inspect_missing_replacement_jobs,retry_failed_replacement_jobs,inspect_stale_replacement_jobs",
             "data-historical-workflow-group-recovery-closure-unresolved" => "0",
             "data-historical-workflow-group-recovery-closure-pending-replacements" => "1",
             "data-historical-workflow-group-recovery-closure-completed-replacements" => "2",
             "data-historical-workflow-group-recovery-closure-active-jobs" => "1",
             "data-historical-workflow-group-recovery-closure-blocked-jobs" => "2",
             "data-historical-workflow-group-recovery-closure-failed-jobs" => "1",
             "data-historical-workflow-group-recovery-closure-failed-runs" => "run-006-corrected",
             "data-historical-workflow-group-recovery-closure-missing-jobs" => "1",
             "data-historical-workflow-group-recovery-closure-missing-runs" =>
               "run-003-corrected",
             "data-historical-workflow-group-recovery-closure-stale-jobs" => "1",
             "data-historical-workflow-group-recovery-closure-stale-runs" => "run-007-corrected",
             "data-historical-workflow-group-recovery-closure-complete-eligible" => "1",
             "data-historical-workflow-group-recovery-closure-summary" =>
               "status inspect_job_state; action inspect_missing_replacement_jobs; unresolved 0; replacements pending 1 completed 2; jobs active 1 blocked 2 failed 1 missing 1 stale 1; complete_eligible 1"
           }

    assert closure["attrs"]["data-historical-workflow-group-recovery-closure-action"] ==
             "inspect_missing_replacement_jobs"

    assert closure["attrs"]["data-historical-workflow-group-recovery-closure-actions"] ==
             "inspect_missing_replacement_jobs,retry_failed_replacement_jobs,inspect_stale_replacement_jobs"

    assert closure["attrs"]["data-historical-workflow-group-recovery-closure-failed-runs"] ==
             "run-006-corrected"

    assert closure["attrs"]["data-historical-workflow-group-recovery-closure-missing-runs"] ==
             "run-003-corrected"

    assert closure["attrs"]["data-historical-workflow-group-recovery-closure-stale-runs"] ==
             "run-007-corrected"

    assert closure["completion_form"]["visible"] == false
  end

  test "replacement_status preserves raw HEEx scalar and completion form semantics" do
    html =
      render_component(&HistoricalWorkflowReplacementStatusComponents.replacement_status/1,
        workflow_context: %{request_group_id: true, event_id: 7},
        replacement_recovery: semantic_replacement_recovery(),
        closure_readiness: semantic_closure_readiness(),
        group_recovery_forms: semantic_group_recovery_forms()
      )

    presentation = replacement_status_presentation(html)
    remaining_work = presentation["remaining_work"]
    entry = remaining_work["items"]["entries"] |> List.first()
    closure = presentation["closure_readiness"]
    form = closure["completion_form"]

    assert remaining_work["attrs"] == %{
             "data-historical-workflow-group-recovery-remaining-work-completed-count" => "",
             "data-historical-workflow-group-recovery-remaining-work-next-actions" => "",
             "data-historical-workflow-group-recovery-remaining-work-pending-runs" => "7",
             "data-historical-workflow-group-recovery-remaining-work-active-jobs" => "0",
             "data-historical-workflow-group-recovery-remaining-work-active-runs" => "",
             "data-historical-workflow-group-recovery-remaining-work-stale-summary" => "7",
             "data-historical-workflow-group-recovery-remaining-work-blocked-jobs" => "",
             "data-historical-workflow-group-recovery-remaining-work-missing-jobs" => "7"
           }

    assert remaining_work["header"]["count"]["text"] == "false pending"

    assert entry["attrs"] == %{
             "data-historical-workflow-group-recovery-remaining-work-replacement-run" => "",
             "data-historical-workflow-group-recovery-remaining-work-stage" => "",
             "data-historical-workflow-group-recovery-remaining-work-next-action" => "7",
             "data-historical-workflow-group-recovery-remaining-work-event-id" => "",
             "data-historical-workflow-group-recovery-remaining-work-job-status" => "  ",
             "data-historical-workflow-group-recovery-remaining-work-job-started" => "",
             "data-historical-workflow-group-recovery-remaining-work-job-completed" => "7",
             "data-historical-workflow-group-recovery-remaining-work-job-action" =>
               "inspect_missing_replacement_job"
           }

    assert entry["header"] == %{
             "class" => "flex items-center justify-between gap-2",
             "replacement_run" => text_presentation("min-w-0 truncate font-mono", "true"),
             "status" => text_presentation("badge badge-xs badge-outline", "false")
           }

    assert Enum.map(entry["work_details"]["values"], & &1["text"]) == ["", "7", "false"]
    assert entry["job_details"] == %{"visible" => false}

    assert entry["actions"] == [
             %{
               "id" => "dashboard-historical-workflow-missing-replacement-inspect-true",
               "type" => "button",
               "class" => "btn btn-xs btn-warning btn-outline mt-1",
               "text" => "Inspect missing job",
               "icon" => %{"name" => "hero-magnifying-glass", "class" => "size-3"},
               "attrs" => %{
                 "phx-click" => "inspect_missing_historical_workflow_replacement_job",
                 "phx-value-request-group-id" => "",
                 "phx-value-replacement-run-id" => "",
                 "data-workflow-action-id" => "inspect_missing_replacement_job",
                 "data-workflow-action-scope" => "replacement_job",
                 "data-workflow-action-request-group" => "",
                 "data-workflow-action-replacement-run" => "",
                 "data-workflow-action-stage" => "",
                 "data-workflow-action-next-action" => "7"
               }
             }
           ]

    assert Enum.map(remaining_work["job_summaries"], & &1["visible"]) == [
             false,
             true,
             true
           ]

    assert closure["attrs"] == %{
             "data-historical-workflow-group-recovery-closure-status" => "ready_to_complete",
             "data-historical-workflow-group-recovery-closure-actions" => "",
             "data-historical-workflow-group-recovery-closure-unresolved" => "",
             "data-historical-workflow-group-recovery-closure-active-jobs" => "",
             "data-historical-workflow-group-recovery-closure-blocked-jobs" => "7",
             "data-historical-workflow-group-recovery-closure-missing-jobs" => "",
             "data-historical-workflow-group-recovery-closure-missing-runs" => "",
             "data-historical-workflow-group-recovery-closure-stale-jobs" => "7",
             "data-historical-workflow-group-recovery-closure-complete-eligible" => ""
           }

    assert Enum.map(closure["details"]["rows"], & &1["value"]["text"]) == [
             "false",
             "true",
             "",
             " pending / false complete",
             "true active / 7 blocked /  failed /  missing / 7 stale"
           ]

    assert form == %{
             "visible" => true,
             "id" => "semantic-completion-form",
             "class" => "space-y-2 rounded border border-success/30 bg-success/5 p-2",
             "attrs" => %{
               "phx-submit" => "",
               "data-historical-workflow-group-recovery-complete-stage" => "",
               "data-historical-workflow-group-recovery-complete-eligible" => "7",
               "data-historical-workflow-group-recovery-complete-count" => ""
             },
             "hidden_fields" => [
               %{
                 "key" => "historical-workflow-completion-hidden-0",
                 "attrs" => %{"type" => "hidden"}
               },
               %{
                 "key" => "historical-workflow-completion-hidden-1",
                 "attrs" => %{"type" => "hidden", "name" => "", "value" => "7"}
               }
             ],
             "button" => %{
               "id" => "dashboard-historical-workflow-group-recovery-complete",
               "type" => "submit",
               "class" =>
                 "btn btn-xs btn-success btn-outline w-full justify-between gap-2 btn-disabled",
               "attrs" => %{
                 "name" => "historical_workflow_group[stage]",
                 "value" => "",
                 "disabled" => "",
                 "data-workflow-action-stage" => "",
                 "data-workflow-action-eligible" => "7",
                 "data-workflow-action-eligible-count" => ""
               },
               "label" => %{
                 "class" => "flex min-w-0 items-center gap-1",
                 "text" => "Complete group",
                 "icon" => %{"name" => "hero-flag", "class" => "h-3.5 w-3.5"}
               },
               "count" => text_presentation("font-mono", "true")
             }
           }

    refute Map.has_key?(form["attrs"], "method")
    refute Map.has_key?(form["attrs"], "name")

    empty_html =
      render_component(&HistoricalWorkflowReplacementStatusComponents.replacement_status/1,
        workflow_context: %{},
        replacement_recovery: %{entries: []},
        closure_readiness: Map.put(semantic_closure_readiness(), :status, "monitor_group"),
        group_recovery_forms: %{}
      )

    empty_presentation = replacement_status_presentation(empty_html)

    assert empty_presentation["remaining_work"]["visible"] == false

    assert empty_presentation["closure_readiness"]["id"] ==
             "dashboard-historical-workflow-group-recovery-closure-readiness"

    assert empty_presentation["closure_readiness"]["completion_form"] == %{
             "visible" => false
           }
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
  end

  defp closure_attrs(html) do
    closure = closure_readiness_presentation(html)

    %{
      "status" => closure["attrs"]["data-historical-workflow-group-recovery-closure-status"],
      "action" => closure["attrs"]["data-historical-workflow-group-recovery-closure-action"],
      "active" => closure["attrs"]["data-historical-workflow-group-recovery-closure-active-jobs"],
      "blocked" =>
        closure["attrs"]["data-historical-workflow-group-recovery-closure-blocked-jobs"],
      "failed" => closure["attrs"]["data-historical-workflow-group-recovery-closure-failed-jobs"],
      "missing" =>
        closure["attrs"]["data-historical-workflow-group-recovery-closure-missing-jobs"],
      "stale" => closure["attrs"]["data-historical-workflow-group-recovery-closure-stale-jobs"]
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

  defp replacement_status_presentation(html) do
    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-historical-workflow-replacement-status-component"
      )

    assert vue.component == "HistoricalWorkflowReplacementStatus"
    assert vue.id == "dashboard-historical-workflow-replacement-status-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "presentation")
  end

  defp closure_readiness_presentation(html) do
    html
    |> replacement_status_presentation()
    |> Map.fetch!("closure_readiness")
  end

  defp closure_detail(key, label, value_class, value) do
    %{
      "key" => key,
      "label" => text_presentation("text-base-content/60", label),
      "value" => text_presentation(value_class, value)
    }
  end

  defp completion_form_presentation do
    %{
      "visible" => true,
      "id" => "dashboard-historical-workflow-group-recovery-complete-form",
      "class" => "space-y-2 rounded border border-success/30 bg-success/5 p-2",
      "attrs" => %{
        "phx-submit" => "record_historical_workflow_group_stage",
        "data-historical-workflow-group-recovery-complete-request-group" => "request-group-1",
        "data-historical-workflow-group-recovery-complete-stage" => "completed",
        "data-historical-workflow-group-recovery-complete-eligible" => "true",
        "data-historical-workflow-group-recovery-complete-count" => "1",
        "data-historical-workflow-group-recovery-complete-reason" => "eligible_group_items",
        "data-historical-workflow-group-recovery-complete-preview" =>
          "Record complete transition for 1 eligible replacement item."
      },
      "hidden_fields" =>
        [
          {"workflow", ""},
          {"request_group_id", "request-group-1"},
          {"realm", ""},
          {"data_source_id", ""},
          {"source_binding_id", ""},
          {"dashboard_id", ""},
          {"dashboard_version", ""},
          {"dashboard_time_mode", ""},
          {"dashboard_replay_run_id", ""},
          {"dashboard_data_view", ""},
          {"dashboard_limit_mode", ""},
          {"reason", "dashboard_recovery_group_completed"},
          {"confirmed", "confirmed"}
        ]
        |> Enum.with_index()
        |> Enum.map(fn {{name, value}, index} ->
          %{
            "key" => "historical-workflow-completion-hidden-#{index}",
            "attrs" => %{
              "type" => "hidden",
              "name" => "historical_workflow_group[#{name}]",
              "value" => value
            }
          }
        end),
      "button" => %{
        "id" => "dashboard-historical-workflow-group-recovery-complete",
        "type" => "submit",
        "class" => "btn btn-xs btn-success btn-outline w-full justify-between gap-2",
        "attrs" => %{
          "name" => "historical_workflow_group[stage]",
          "value" => "completed",
          "data-workflow-action-id" => "group-stage-completed",
          "data-workflow-action-stage" => "completed",
          "data-workflow-action-eligible" => "true",
          "data-workflow-action-eligible-count" => "1",
          "data-workflow-action-reason" => "eligible_group_items",
          "data-workflow-action-preview" =>
            "Record complete transition for 1 eligible replacement item."
        },
        "label" => %{
          "class" => "flex min-w-0 items-center gap-1",
          "text" => "Complete group",
          "icon" => %{"name" => "hero-flag", "class" => "h-3.5 w-3.5"}
        },
        "count" => text_presentation("font-mono", "1")
      }
    }
  end

  defp semantic_replacement_recovery do
    %{
      entries: [
        %{
          raw: nil,
          source: false,
          replacement_run: true,
          stage: "",
          next_action: 7,
          status: false,
          job_item: nil,
          event_id: true,
          job_id: false,
          job_status: "  ",
          job_started_at: "",
          job_completed_at: 7,
          job_age_state: false,
          job_action: "inspect_missing_replacement_job"
        }
      ],
      total_count: nil,
      pending_count: false,
      completed_count: true,
      next_actions: "",
      pending_runs: 7,
      work_summary: nil,
      job_summary: false,
      active_job_count: "0",
      active_run_ids: true,
      active_summary: nil,
      stale_job_count: false,
      stale_run_ids: nil,
      stale_summary: 7,
      blocked_job_count: true,
      failed_job_count: "0",
      failed_run_ids: false,
      missing_job_count: 7,
      missing_run_ids: nil,
      missing_summary: true,
      retry_action: %{
        present: true,
        id: nil,
        eligible: false,
        reason: nil,
        preview: false
      }
    }
  end

  defp semantic_closure_readiness do
    %{
      status: "ready_to_complete",
      action: false,
      actions: true,
      unresolved: "",
      pending_replacements: nil,
      completed_replacements: false,
      active_jobs: true,
      blocked_jobs: 7,
      failed_jobs: nil,
      failed_runs: false,
      missing_jobs: "",
      missing_runs: true,
      stale_jobs: 7,
      stale_runs: nil,
      complete_eligible: true,
      summary: false
    }
  end

  defp semantic_group_recovery_forms do
    %{
      completion: %{
        present: true,
        id: "semantic-completion-form",
        submit_event: true,
        request_group_id: false,
        stage: "",
        eligible: 7,
        count: true,
        reason: nil,
        preview: false,
        action_id: false,
        disabled_bool: true,
        hidden_fields: [
          %{name: nil, value: false},
          %{name: true, value: 7}
        ]
      }
    }
  end

  defp text_presentation(class, text), do: %{"class" => class, "text" => text}
end
