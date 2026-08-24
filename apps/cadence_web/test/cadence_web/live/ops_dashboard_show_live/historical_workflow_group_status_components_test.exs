defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStatusComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStatusComponents

  test "group_status renders recovery handoffs and replacement advancement contract" do
    html =
      render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
        workflow_context: group_context(),
        workflow_controls: workflow_controls(),
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&panel=data_link"
      )

    document = LazyHTML.from_fragment(html)
    replacement_status = replacement_status_presentation(html)
    remaining_work = replacement_status["remaining_work"]

    assert ["request-group-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
             |> LazyHTML.attribute("data-historical-workflow-group-id")

    assert [
             "group request-group-1; failed; progress 2/4; jobs queued 1, failed 1; failed 2; retryable 2; correction 0; resolved 0; failed items job-1,job-2"
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
             |> LazyHTML.attribute("data-historical-workflow-group-handoff-summary")

    review_href =
      document
      |> LazyHTML.query("[data-historical-workflow-review-origin-link]")
      |> LazyHTML.attribute("data-historical-workflow-review-origin-href")
      |> List.first()

    assert review_href_query(review_href) == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_filter" => "open_comparison_reviews",
             "activity_event" => "review-request-1"
           }

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-failed-item-handoffs")

    assert ["failed-event-2", "failed-event-3"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-recovery-failed-item]")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-failed-item")

    assert ["HK voltage bus", "HK.current"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-recovery-failed-item]")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-failed-item-label")

    assert Map.take(remaining_work, ["visible", "id", "class", "attrs", "header"]) == %{
             "visible" => true,
             "id" => "dashboard-historical-workflow-group-recovery-remaining-work",
             "class" => "mt-2 space-y-2 rounded border border-primary/30 bg-primary/5 p-2",
             "attrs" => %{
               "data-historical-workflow-group-recovery-remaining-work-count" => "1",
               "data-historical-workflow-group-recovery-remaining-work-pending-count" => "1",
               "data-historical-workflow-group-recovery-remaining-work-completed-count" => "0",
               "data-historical-workflow-group-recovery-remaining-work-next-actions" => "approve",
               "data-historical-workflow-group-recovery-remaining-work-pending-runs" =>
                 "run-003-corrected",
               "data-historical-workflow-group-recovery-remaining-work-summary" =>
                 "run-003-corrected requested next approve pending",
               "data-historical-workflow-group-recovery-remaining-work-job-summary" => "",
               "data-historical-workflow-group-recovery-remaining-work-active-jobs" => "0",
               "data-historical-workflow-group-recovery-remaining-work-active-runs" => "",
               "data-historical-workflow-group-recovery-remaining-work-active-summary" => "",
               "data-historical-workflow-group-recovery-remaining-work-stale-jobs" => "0",
               "data-historical-workflow-group-recovery-remaining-work-stale-runs" => "",
               "data-historical-workflow-group-recovery-remaining-work-stale-summary" => "",
               "data-historical-workflow-group-recovery-remaining-work-blocked-jobs" => "0",
               "data-historical-workflow-group-recovery-remaining-work-missing-jobs" => "0",
               "data-historical-workflow-group-recovery-remaining-work-missing-runs" => ""
             },
             "header" => %{
               "class" => "flex items-center justify-between gap-2",
               "label" => text_presentation("hud-label", "Replacement Work"),
               "count" => text_presentation("font-mono text-base-content/70", "1 pending")
             }
           }

    assert remaining_work["items"] == %{
             "class" => "space-y-1",
             "entries" => [
               expected_remaining_work_entry(
                 0,
                 %{
                   "data-historical-workflow-group-recovery-remaining-work-item" =>
                     "HK.current run-003 replacement run-003-corrected stage requested next approve",
                   "data-historical-workflow-group-recovery-remaining-work-source" =>
                     "HK.current run-003",
                   "data-historical-workflow-group-recovery-remaining-work-replacement-run" =>
                     "run-003-corrected",
                   "data-historical-workflow-group-recovery-remaining-work-stage" => "requested",
                   "data-historical-workflow-group-recovery-remaining-work-next-action" =>
                     "approve",
                   "data-historical-workflow-group-recovery-remaining-work-status" => "pending",
                   "data-historical-workflow-group-recovery-remaining-work-job-status" => "",
                   "data-historical-workflow-group-recovery-remaining-work-job-id" => "",
                   "data-historical-workflow-group-recovery-remaining-work-event-id" => "",
                   "data-historical-workflow-group-recovery-remaining-work-job-started" => "",
                   "data-historical-workflow-group-recovery-remaining-work-job-completed" => "",
                   "data-historical-workflow-group-recovery-remaining-work-job-age-state" => "",
                   "data-historical-workflow-group-recovery-remaining-work-job-action" =>
                     "advance_replacement_request",
                   "data-historical-workflow-group-recovery-remaining-work-job-item" => ""
                 },
                 "run-003-corrected",
                 "pending",
                 ["requested", "approve", "HK.current run-003"],
                 false,
                 ["", "", "advance_replacement_request"],
                 []
               )
             ]
           }

    assert ["approved"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-advance-corrected")
             |> LazyHTML.attribute("data-workflow-action-stage")

    assert ["replacement_corrections"] =
             document
             |> LazyHTML.query(
               ~s(input[name="historical_workflow_group[group_transition_scope]"])
             )
             |> LazyHTML.attribute("value")
  end

  test "group_status summarizes replacement work and exposes scoped job recovery actions" do
    correction_tasks =
      [
        "HK.current run-003 replacement run-003-corrected stage requested next approve",
        "HK.voltage run-004 replacement run-004-corrected stage approved next start",
        "HK.gyro run-006 replacement run-006-corrected stage started next complete",
        "HK.temp run-005 replacement run-005-corrected stage completed next done"
      ]
      |> Enum.join("; ")

    html =
      render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
        workflow_context:
          group_context()
          |> Map.put(:request_group_correction_tasks, correction_tasks)
          |> Map.put(:request_group_job_progress, "queued 1, running 1, failed 1, completed 1")
          |> Map.put(
            :request_group_job_items,
            "3:HK.current run-003-corrected queued job-3 event=event-3; 4:HK.voltage run-004-corrected failed job-4 event=event-4; 6:HK.gyro run-006-corrected running job-6 event=event-6 started=2023-11-14T22:00:00Z; 5:HK.temp run-005-corrected completed job-5 event=event-5 completed=2023-11-14T22:05:00Z"
          ),
        workflow_controls:
          workflow_controls()
          |> Map.put(:group_retry_action, %{
            id: "retry-group-failed",
            eligible?: true,
            reason: "retryable_group_failures",
            preview: "Retry failed corrected replacement jobs."
          })
          |> Map.put(:group_stage_actions, [
            %{
              id: "group-stage-approved",
              stage: "approved",
              eligible?: true,
              eligible_count: 1,
              reason: "eligible_group_items",
              preview: "Record approve transition for 1 eligible replacement item.",
              correction_tasks:
                "HK.current run-003 replacement run-003-corrected stage requested next approve"
            },
            %{
              id: "group-stage-started",
              stage: "started",
              eligible?: true,
              eligible_count: 1,
              reason: "eligible_group_items",
              preview: "Record start transition for 1 eligible replacement item.",
              correction_tasks:
                "HK.voltage run-004 replacement run-004-corrected stage approved next start"
            }
          ]),
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&panel=data_link"
      )

    replacement_status = replacement_status_presentation(html)
    remaining_work = replacement_status["remaining_work"]
    entries = remaining_work["items"]["entries"]

    assert Map.take(remaining_work, ["visible", "id", "class", "attrs", "header"]) == %{
             "visible" => true,
             "id" => "dashboard-historical-workflow-group-recovery-remaining-work",
             "class" => "mt-2 space-y-2 rounded border border-primary/30 bg-primary/5 p-2",
             "attrs" => %{
               "data-historical-workflow-group-recovery-remaining-work-count" => "4",
               "data-historical-workflow-group-recovery-remaining-work-pending-count" => "3",
               "data-historical-workflow-group-recovery-remaining-work-completed-count" => "1",
               "data-historical-workflow-group-recovery-remaining-work-next-actions" =>
                 "approve,start,complete",
               "data-historical-workflow-group-recovery-remaining-work-pending-runs" =>
                 "run-003-corrected,run-004-corrected,run-006-corrected",
               "data-historical-workflow-group-recovery-remaining-work-summary" =>
                 "run-003-corrected requested next approve pending; run-004-corrected approved next start pending; run-006-corrected started next complete pending; run-005-corrected completed next done complete",
               "data-historical-workflow-group-recovery-remaining-work-job-summary" =>
                 "run-003-corrected queued job-3 wait_for_replacement_job_start; run-004-corrected failed job-4 inspect_failed_replacement_job; run-006-corrected running job-6 inspect_stale_replacement_job; run-005-corrected completed job-5 replacement_complete",
               "data-historical-workflow-group-recovery-remaining-work-active-jobs" => "2",
               "data-historical-workflow-group-recovery-remaining-work-active-runs" =>
                 "run-003-corrected,run-006-corrected",
               "data-historical-workflow-group-recovery-remaining-work-active-summary" =>
                 "run-003-corrected queued job-3 wait_for_replacement_job_start; run-006-corrected running job-6 inspect_stale_replacement_job",
               "data-historical-workflow-group-recovery-remaining-work-stale-jobs" => "1",
               "data-historical-workflow-group-recovery-remaining-work-stale-runs" =>
                 "run-006-corrected",
               "data-historical-workflow-group-recovery-remaining-work-stale-summary" =>
                 "run-006-corrected running job-6 2023-11-14T22:00:00Z inspect_stale_replacement_job",
               "data-historical-workflow-group-recovery-remaining-work-blocked-jobs" => "1",
               "data-historical-workflow-group-recovery-remaining-work-missing-jobs" => "0",
               "data-historical-workflow-group-recovery-remaining-work-missing-runs" => ""
             },
             "header" => %{
               "class" => "flex items-center justify-between gap-2",
               "label" => text_presentation("hud-label", "Replacement Work"),
               "count" => text_presentation("font-mono text-base-content/70", "3 pending")
             }
           }

    assert entries == [
             expected_remaining_work_entry(
               0,
               replacement_entry_attrs(
                 "HK.current run-003 replacement run-003-corrected stage requested next approve",
                 "HK.current run-003",
                 "run-003-corrected",
                 "requested",
                 "approve",
                 "pending",
                 "3:HK.current run-003-corrected queued job-3 event=event-3",
                 "event-3",
                 "job-3",
                 "queued",
                 "",
                 "",
                 "active",
                 "wait_for_replacement_job_start"
               ),
               "run-003-corrected",
               "pending",
               ["requested", "approve", "HK.current run-003"],
               true,
               ["queued", "job-3", "wait_for_replacement_job_start"],
               []
             ),
             expected_remaining_work_entry(
               1,
               replacement_entry_attrs(
                 "HK.voltage run-004 replacement run-004-corrected stage approved next start",
                 "HK.voltage run-004",
                 "run-004-corrected",
                 "approved",
                 "start",
                 "pending",
                 "4:HK.voltage run-004-corrected failed job-4 event=event-4",
                 "event-4",
                 "job-4",
                 "failed",
                 "",
                 "",
                 "",
                 "inspect_failed_replacement_job"
               ),
               "run-004-corrected",
               "pending",
               ["approved", "start", "HK.voltage run-004"],
               true,
               ["failed", "job-4", "inspect_failed_replacement_job"],
               [
                 action_button(
                   "dashboard-historical-workflow-failed-replacement-retry-run-004-corrected",
                   "btn btn-xs btn-error btn-outline mt-1",
                   "Retry failed job",
                   "hero-arrow-path",
                   %{
                     "phx-click" => "retry_historical_workflow_job",
                     "phx-value-job-id" => "job-4",
                     "phx-value-event-id" => "event-4",
                     "phx-value-replacement-run-id" => "run-004-corrected",
                     "data-workflow-action-id" => "retry_failed_replacement_job",
                     "data-workflow-action-scope" => "replacement_job",
                     "data-workflow-action-replacement-run" => "run-004-corrected",
                     "data-workflow-action-job-id" => "job-4",
                     "data-workflow-action-event-id" => "event-4",
                     "data-workflow-action-reason" => "retryable_group_failures",
                     "data-workflow-action-preview" => "Retry failed corrected replacement jobs."
                   }
                 )
               ]
             ),
             expected_remaining_work_entry(
               2,
               replacement_entry_attrs(
                 "HK.gyro run-006 replacement run-006-corrected stage started next complete",
                 "HK.gyro run-006",
                 "run-006-corrected",
                 "started",
                 "complete",
                 "pending",
                 "6:HK.gyro run-006-corrected running job-6 event=event-6 started=2023-11-14T22:00:00Z",
                 "event-6",
                 "job-6",
                 "running",
                 "2023-11-14T22:00:00Z",
                 "",
                 "stale",
                 "inspect_stale_replacement_job"
               ),
               "run-006-corrected",
               "pending",
               ["started", "complete", "HK.gyro run-006"],
               true,
               ["running", "job-6", "inspect_stale_replacement_job"],
               [
                 action_button(
                   "dashboard-historical-workflow-stale-replacement-inspect-run-006-corrected",
                   "btn btn-xs btn-warning btn-outline mt-1",
                   "Inspect stale job",
                   "hero-magnifying-glass",
                   stale_action_attrs(
                     "inspect_stale_historical_workflow_replacement_job",
                     "inspect_stale_replacement_job"
                   )
                 ),
                 action_button(
                   "dashboard-historical-workflow-stale-replacement-requeue-run-006-corrected",
                   "btn btn-xs btn-warning mt-1",
                   "Requeue stale job",
                   "hero-arrow-path",
                   stale_action_attrs(
                     "requeue_stale_historical_workflow_replacement_job",
                     "requeue_stale_replacement_job"
                   )
                 )
               ]
             ),
             expected_remaining_work_entry(
               3,
               replacement_entry_attrs(
                 "HK.temp run-005 replacement run-005-corrected stage completed next done",
                 "HK.temp run-005",
                 "run-005-corrected",
                 "completed",
                 "done",
                 "complete",
                 "5:HK.temp run-005-corrected completed job-5 event=event-5 completed=2023-11-14T22:05:00Z",
                 "event-5",
                 "job-5",
                 "completed",
                 "",
                 "2023-11-14T22:05:00Z",
                 "",
                 "replacement_complete"
               ),
               "run-005-corrected",
               "complete",
               ["completed", "done", "HK.temp run-005"],
               true,
               ["completed", "job-5", "replacement_complete"],
               []
             )
           ]

    assert remaining_work["job_summaries"] == [
             job_summary(
               true,
               "dashboard-historical-workflow-group-recovery-active-replacement-jobs",
               "rounded border border-info/40 bg-info/10 p-2",
               "data-historical-workflow-group-recovery-active-replacement",
               "2",
               "run-003-corrected,run-006-corrected",
               "run-003-corrected queued job-3 wait_for_replacement_job_start; run-006-corrected running job-6 inspect_stale_replacement_job",
               "Active Replacement Jobs"
             ),
             job_summary(
               true,
               "dashboard-historical-workflow-group-recovery-stale-replacement-jobs",
               "rounded border border-warning/40 bg-warning/10 p-2",
               "data-historical-workflow-group-recovery-stale-replacement",
               "1",
               "run-006-corrected",
               "run-006-corrected running job-6 2023-11-14T22:00:00Z inspect_stale_replacement_job",
               "Stale Replacement Jobs"
             ),
             job_summary(
               false,
               "dashboard-historical-workflow-group-recovery-missing-replacement-jobs",
               "rounded border border-warning/40 bg-warning/10 p-2",
               "data-historical-workflow-group-recovery-missing-replacement",
               "0",
               "",
               "",
               "Missing Replacement Jobs"
             )
           ]

    assert Enum.map(
             entries,
             & &1["attrs"][
               "data-historical-workflow-group-recovery-remaining-work-job-status"
             ]
           ) == ["queued", "failed", "running", "completed"]

    assert Enum.at(entries, 1)["actions"] == [
             action_button(
               "dashboard-historical-workflow-failed-replacement-retry-run-004-corrected",
               "btn btn-xs btn-error btn-outline mt-1",
               "Retry failed job",
               "hero-arrow-path",
               %{
                 "phx-click" => "retry_historical_workflow_job",
                 "phx-value-job-id" => "job-4",
                 "phx-value-event-id" => "event-4",
                 "phx-value-replacement-run-id" => "run-004-corrected",
                 "data-workflow-action-id" => "retry_failed_replacement_job",
                 "data-workflow-action-scope" => "replacement_job",
                 "data-workflow-action-replacement-run" => "run-004-corrected",
                 "data-workflow-action-job-id" => "job-4",
                 "data-workflow-action-event-id" => "event-4",
                 "data-workflow-action-reason" => "retryable_group_failures",
                 "data-workflow-action-preview" => "Retry failed corrected replacement jobs."
               }
             )
           ]

    assert entries |> Enum.at(2) |> Map.fetch!("actions") |> Enum.at(0) ==
             action_button(
               "dashboard-historical-workflow-stale-replacement-inspect-run-006-corrected",
               "btn btn-xs btn-warning btn-outline mt-1",
               "Inspect stale job",
               "hero-magnifying-glass",
               stale_action_attrs(
                 "inspect_stale_historical_workflow_replacement_job",
                 "inspect_stale_replacement_job"
               )
             )

    assert entries |> Enum.at(2) |> Map.fetch!("actions") |> Enum.at(1) ==
             action_button(
               "dashboard-historical-workflow-stale-replacement-requeue-run-006-corrected",
               "btn btn-xs btn-warning mt-1",
               "Requeue stale job",
               "hero-arrow-path",
               stale_action_attrs(
                 "requeue_stale_historical_workflow_replacement_job",
                 "requeue_stale_replacement_job"
               )
             )

    assert remaining_work["retry_button"] == %{
             "visible" => true,
             "id" => "dashboard-historical-workflow-group-retry-failed-replacements",
             "type" => "button",
             "class" => "btn btn-xs btn-error btn-outline w-full justify-between gap-2",
             "attrs" => %{
               "phx-click" => "retry_historical_workflow_group_failed_jobs",
               "phx-value-request-group-id" => "request-group-1",
               "phx-value-event-id" => "source-event-1",
               "phx-value-retry-run-ids" => "run-004-corrected",
               "data-workflow-action-id" => "retry-group-failed",
               "data-workflow-action-scope" => "replacement_jobs",
               "data-workflow-action-eligible" => "true",
               "data-workflow-action-eligible-count" => "1",
               "data-workflow-action-retry-run-ids" => "run-004-corrected",
               "data-workflow-action-reason" => "retryable_group_failures",
               "data-workflow-action-preview" => "Retry failed corrected replacement jobs.",
               "data-confirm" => "Retry failed corrected replacement jobs in this request group?"
             },
             "label" => %{
               "class" => "flex min-w-0 items-center gap-1",
               "text" => "Retry failed replacements",
               "icon" => %{"name" => "hero-arrow-path", "class" => "size-3"}
             },
             "count" => text_presentation("font-mono", "1")
           }
  end

  test "group_status renders no group card when group summary is disabled" do
    html =
      render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
        workflow_context: group_context(),
        workflow_controls: %{workflow_controls() | group_summary: false},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
             |> LazyHTML.attribute("id")
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

  defp expected_remaining_work_entry(
         index,
         attrs,
         replacement_run,
         status,
         work_values,
         job_visible,
         job_values,
         actions
       ) do
    %{
      "key" => "historical-workflow-replacement-work-#{index}",
      "class" => "rounded border border-base-300/60 bg-base-100/70 px-2 py-1",
      "attrs" => attrs,
      "header" => %{
        "class" => "flex items-center justify-between gap-2",
        "replacement_run" => text_presentation("min-w-0 truncate font-mono", replacement_run),
        "status" => text_presentation("badge badge-xs badge-outline", status)
      },
      "work_details" => %{
        "class" => "mt-1 flex flex-wrap gap-2 text-[0.68rem] text-base-content/65",
        "values" => [
          text_presentation("font-mono", Enum.at(work_values, 0)),
          text_presentation("font-mono", Enum.at(work_values, 1)),
          text_presentation("min-w-0 break-all", Enum.at(work_values, 2))
        ]
      },
      "job_details" =>
        %{
          "visible" => true,
          "class" => "mt-1 flex flex-wrap gap-2 text-[0.68rem] text-base-content/65",
          "values" => Enum.map(job_values, &text_presentation("font-mono", &1))
        }
        |> then(fn job_details ->
          if job_visible, do: job_details, else: %{"visible" => false}
        end),
      "actions" => actions
    }
  end

  defp replacement_entry_attrs(
         raw,
         source,
         replacement_run,
         stage,
         next_action,
         status,
         job_item,
         event_id,
         job_id,
         job_status,
         job_started,
         job_completed,
         job_age_state,
         job_action
       ) do
    %{
      "data-historical-workflow-group-recovery-remaining-work-item" => raw,
      "data-historical-workflow-group-recovery-remaining-work-source" => source,
      "data-historical-workflow-group-recovery-remaining-work-replacement-run" => replacement_run,
      "data-historical-workflow-group-recovery-remaining-work-stage" => stage,
      "data-historical-workflow-group-recovery-remaining-work-next-action" => next_action,
      "data-historical-workflow-group-recovery-remaining-work-status" => status,
      "data-historical-workflow-group-recovery-remaining-work-job-status" => job_status,
      "data-historical-workflow-group-recovery-remaining-work-job-id" => job_id,
      "data-historical-workflow-group-recovery-remaining-work-event-id" => event_id,
      "data-historical-workflow-group-recovery-remaining-work-job-started" => job_started,
      "data-historical-workflow-group-recovery-remaining-work-job-completed" => job_completed,
      "data-historical-workflow-group-recovery-remaining-work-job-age-state" => job_age_state,
      "data-historical-workflow-group-recovery-remaining-work-job-action" => job_action,
      "data-historical-workflow-group-recovery-remaining-work-job-item" => job_item
    }
  end

  defp action_button(id, class, text, icon, attrs) do
    %{
      "id" => id,
      "type" => "button",
      "class" => class,
      "text" => text,
      "icon" => %{"name" => icon, "class" => "size-3"},
      "attrs" => attrs
    }
  end

  defp stale_action_attrs(click, action_id) do
    %{
      "phx-click" => click,
      "phx-value-job-id" => "job-6",
      "phx-value-event-id" => "event-6",
      "phx-value-replacement-run-id" => "run-006-corrected",
      "data-workflow-action-id" => action_id,
      "data-workflow-action-scope" => "replacement_job",
      "data-workflow-action-replacement-run" => "run-006-corrected",
      "data-workflow-action-job-id" => "job-6",
      "data-workflow-action-event-id" => "event-6",
      "data-workflow-action-job-started" => "2023-11-14T22:00:00Z"
    }
  end

  defp job_summary(visible, id, class, attr_prefix, count, runs, summary, label) do
    if visible do
      %{
        "visible" => true,
        "key" => id,
        "id" => id,
        "class" => class,
        "attrs" => %{
          "#{attr_prefix}-job-count" => count,
          "#{attr_prefix}-runs" => runs,
          "#{attr_prefix}-summary" => summary
        },
        "header" => %{
          "class" => "flex items-center justify-between gap-2",
          "label" => text_presentation("hud-label", label),
          "count" => text_presentation("font-mono text-base-content/70", count)
        },
        "summary" =>
          text_presentation(
            "mt-1 font-mono text-[0.68rem] text-base-content/70 break-all",
            summary
          )
      }
    else
      %{"visible" => false, "key" => id}
    end
  end

  defp text_presentation(class, text), do: %{"class" => class, "text" => text}

  defp review_href_query(href) do
    href
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end
end
