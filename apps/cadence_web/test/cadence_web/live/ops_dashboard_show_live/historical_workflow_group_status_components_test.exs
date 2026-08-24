defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStatusComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupRecoveryFormPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStatusComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementRecovery
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementStatusComponents

  test "group_status renders recovery handoffs and replacement advancement contract" do
    workflow_context = group_context()
    workflow_controls = workflow_controls()

    html =
      render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
        workflow_context: workflow_context,
        workflow_controls: workflow_controls,
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&panel=data_link"
      )

    presentation = group_status_presentation(html)
    replacement_status = replacement_status_presentation(html)
    remaining_work = replacement_status["remaining_work"]
    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-replacement-status-component")
             |> LazyHTML.attribute("id")

    assert presentation["root"]["attrs"]["data-historical-workflow-group-id"] ==
             "request-group-1"

    assert presentation["root"]["attrs"]["data-historical-workflow-group-handoff-summary"] ==
             "group request-group-1; failed; progress 2/4; jobs queued 1, failed 1; failed 2; retryable 2; correction 0; resolved 0; failed items job-1,job-2"

    assert presentation["root"] == %{
             "id" => "dashboard-historical-workflow-group-summary",
             "class" => "rounded border border-primary/30 bg-primary/5 p-2 text-xs",
             "attrs" => expected_root_attrs()
           }

    review_href = presentation["review_origin"]["review_link"]["href"]

    assert review_href_query(review_href) == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_filter" => "open_comparison_reviews",
             "activity_event" => "review-request-1"
           }

    assert presentation["recovery"]["attrs"][
             "data-historical-workflow-group-recovery-failed-item-handoffs"
           ] == "2"

    handoff_links = presentation["recovery"]["failed_item_handoffs"]["links"]["entries"]

    assert Enum.map(
             handoff_links,
             & &1["attrs"]["data-historical-workflow-group-recovery-failed-item"]
           ) == ["failed-event-2", "failed-event-3"]

    assert Enum.map(
             handoff_links,
             & &1["attrs"]["data-historical-workflow-group-recovery-failed-item-label"]
           ) == ["HK voltage bus", "HK.current"]

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

    advancement_form = presentation["recovery"]["execution_plan"]["advancement_form"]

    assert advancement_form["button"]["attrs"]["data-workflow-action-stage"] == "approved"

    assert advancement_form["hidden_fields"]
           |> Enum.find(
             &(&1["attrs"]["name"] ==
                 "historical_workflow_group[group_transition_scope]")
           )
           |> get_in(["attrs", "value"]) == "replacement_corrections"

    assert presentation
           |> Map.take(["job_progress", "execution_audit", "review_origin", "recovery"])
           |> Map.new(fn {section, value} -> {section, value["visible"]} end) == %{
             "job_progress" => true,
             "execution_audit" => true,
             "review_origin" => true,
             "recovery" => true
           }

    assert presentation["review_origin"]["review_link"] == %{
             "href" => review_href,
             "class" =>
               "inline-flex items-center gap-1 font-mono text-primary hover:text-primary-focus",
             "text" => "Open review",
             "icon" => %{"name" => "hero-arrow-top-right-on-square", "class" => "h-3 w-3"},
             "attrs" => %{
               "data-historical-workflow-review-origin-link" => "review-request-1",
               "data-historical-workflow-review-origin-href" => review_href,
               "data-phx-link" => "patch",
               "data-phx-link-state" => "push"
             }
           }

    assert Enum.map(
             presentation["review_origin"]["placements"]["links"],
             fn link ->
               {
                 link["text"],
                 review_href_query(link["href"]),
                 Map.take(link["attrs"], ["data-phx-link", "data-phx-link-state"])
               }
             end
           ) == [
             {
               "placement-1",
               %{
                 "scope_kind" => "mission",
                 "scope_id" => "mission-1",
                 "panel" => "versions",
                 "activity_filter" => "open_comparison_reviews",
                 "activity_event" => "review-request-1",
                 "selected_placement" => "placement-1"
               },
               %{"data-phx-link" => "patch", "data-phx-link-state" => "push"}
             },
             {
               "placement-2",
               %{
                 "scope_kind" => "mission",
                 "scope_id" => "mission-1",
                 "panel" => "versions",
                 "activity_filter" => "open_comparison_reviews",
                 "activity_event" => "review-request-1",
                 "selected_placement" => "placement-2"
               },
               %{"data-phx-link" => "patch", "data-phx-link-state" => "push"}
             }
           ]

    assert Enum.map(handoff_links, fn link ->
             {
               link["attrs"]["data-historical-workflow-group-recovery-failed-item"],
               review_href_query(link["href"]),
               Map.take(link["attrs"], ["data-phx-link", "data-phx-link-state"])
             }
           end) == [
             {
               "failed-event-2",
               %{
                 "scope_kind" => "mission",
                 "scope_id" => "mission-1",
                 "panel" => "data_link",
                 "selected_target" => "telemetry_backfill_lifecycle_event",
                 "selected_id" => "failed-event-2"
               },
               %{"data-phx-link" => "patch", "data-phx-link-state" => "push"}
             },
             {
               "failed-event-3",
               %{
                 "scope_kind" => "mission",
                 "scope_id" => "mission-1",
                 "panel" => "data_link",
                 "selected_target" => "telemetry_backfill_lifecycle_event",
                 "selected_id" => "failed-event-3"
               },
               %{"data-phx-link" => "patch", "data-phx-link-state" => "push"}
             }
           ]

    assert presentation["recovery"]["execution_plan"]["retry_button"] == %{
             "visible" => true,
             "id" => "dashboard-historical-workflow-group-retry-failed",
             "type" => "button",
             "class" => "btn btn-xs btn-error btn-outline mt-2 w-full justify-start",
             "text" => "Retry failed items",
             "icon" => %{"name" => "hero-arrow-path", "class" => "size-3"},
             "attrs" => %{
               "phx-click" => "retry_historical_workflow_group_failed_jobs",
               "phx-value-request-group-id" => "request-group-1",
               "phx-value-event-id" => "source-event-1",
               "data-workflow-action-id" => "retry-group-failed",
               "data-workflow-action-eligible" => "true",
               "data-workflow-action-eligible-count" => "2",
               "data-workflow-action-reason" => "retryable_group_failures",
               "data-workflow-action-preview" => "Retry every retryable failed job.",
               "data-workflow-action-expected-effect" =>
                 "Retry will requeue 2 failed items and select the retried lifecycle event.",
               "data-confirm" => "Retry every retryable failed job in this request group?"
             }
           }

    assert Map.take(advancement_form, ["visible", "id", "class", "attrs", "header", "preview"]) ==
             %{
               "visible" => true,
               "id" => "dashboard-historical-workflow-group-recovery-advance-corrected-form",
               "class" => "mt-2 space-y-2 rounded border border-primary/30 bg-primary/5 p-2",
               "attrs" => %{
                 "phx-submit" => "record_historical_workflow_group_stage",
                 "data-historical-workflow-group-recovery-advance-request-group" =>
                   "request-group-1",
                 "data-historical-workflow-group-recovery-advance-stage" => "approved",
                 "data-historical-workflow-group-recovery-advance-eligible" => "true",
                 "data-historical-workflow-group-recovery-advance-count" => "1",
                 "data-historical-workflow-group-recovery-advance-reason" =>
                   "eligible_group_items",
                 "data-historical-workflow-group-recovery-advance-preview" =>
                   "Advance 1 corrected replacement request to approved.",
                 "data-historical-workflow-group-recovery-advance-correction-tasks" =>
                   "HK.current run-003 replacement run-003-corrected stage requested next approve"
               },
               "header" => %{
                 "class" => "flex items-center justify-between gap-2",
                 "label" => text_presentation("hud-label", "Replacement Advancement"),
                 "count" => text_presentation("font-mono text-base-content/70", "1")
               },
               "preview" =>
                 text_presentation(
                   "text-base-content/75",
                   "Advance 1 corrected replacement request to approved."
                 )
             }

    assert advancement_form["hidden_fields"] ==
             expected_advancement_hidden_fields()

    assert advancement_form["button"] == expected_advancement_button()

    replacement_recovery =
      HistoricalWorkflowReplacementRecovery.build(workflow_context, workflow_controls)

    expected_replacement_status =
      HistoricalWorkflowReplacementStatusComponents.presentation(
        workflow_context,
        replacement_recovery,
        replacement_recovery.closure_readiness,
        HistoricalWorkflowGroupRecoveryFormPresentation.build(
          workflow_context,
          replacement_recovery
        )
      )
      |> Jason.encode!()
      |> Jason.decode!()

    assert replacement_status == expected_replacement_status
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
                 {
                   "HK.current run-003 replacement run-003-corrected stage requested next approve",
                   "HK.current run-003",
                   "run-003-corrected",
                   "requested",
                   "approve",
                   "pending"
                 },
                 {
                   "3:HK.current run-003-corrected queued job-3 event=event-3",
                   "event-3",
                   "job-3",
                   "queued",
                   nil,
                   nil,
                   "active",
                   "wait_for_replacement_job_start"
                 }
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
                 {
                   "HK.voltage run-004 replacement run-004-corrected stage approved next start",
                   "HK.voltage run-004",
                   "run-004-corrected",
                   "approved",
                   "start",
                   "pending"
                 },
                 {
                   "4:HK.voltage run-004-corrected failed job-4 event=event-4",
                   "event-4",
                   "job-4",
                   "failed",
                   nil,
                   nil,
                   "",
                   "inspect_failed_replacement_job"
                 }
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
                 {
                   "HK.gyro run-006 replacement run-006-corrected stage started next complete",
                   "HK.gyro run-006",
                   "run-006-corrected",
                   "started",
                   "complete",
                   "pending"
                 },
                 {
                   "6:HK.gyro run-006-corrected running job-6 event=event-6 started=2023-11-14T22:00:00Z",
                   "event-6",
                   "job-6",
                   "running",
                   "2023-11-14T22:00:00Z",
                   nil,
                   "stale",
                   "inspect_stale_replacement_job"
                 }
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
                 {
                   "HK.temp run-005 replacement run-005-corrected stage completed next done",
                   "HK.temp run-005",
                   "run-005-corrected",
                   "completed",
                   "done",
                   "complete"
                 },
                 {
                   "5:HK.temp run-005-corrected completed job-5 event=event-5 completed=2023-11-14T22:05:00Z",
                   "event-5",
                   "job-5",
                   "completed",
                   nil,
                   "2023-11-14T22:05:00Z",
                   "",
                   "replacement_complete"
                 }
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

    assert [] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-status-component")
             |> LazyHTML.attribute("id")
  end

  test "group_status omits every conditional outer section when its server presentation is absent" do
    workflow_context =
      group_context()
      |> Map.merge(%{
        request_group_state: "idle",
        request_group_progress: "0/0",
        request_group_job_progress: nil,
        request_group_job_items: nil,
        request_group_requested: "0",
        request_group_approved: "0",
        request_group_started: "0",
        request_group_completed: "0",
        request_group_failed: "0",
        request_group_resolved_failed: "0",
        request_group_retryable_failed: "0",
        request_group_nonretryable_failed: "0",
        comparison_review_request_event_id: nil,
        comparison_review_request_kind: nil,
        comparison_review_open_count: "0",
        comparison_review_open_placement_ids: nil,
        request_group_retried_items: nil,
        request_group_corrected_items: nil,
        request_group_correction_tasks: nil,
        request_group_failed_items: nil,
        request_group_failed_item_events: nil
      })

    html =
      render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
        workflow_context: workflow_context,
        workflow_controls: %{
          workflow_controls()
          | group_retryable_failures: false,
            group_retry_action: nil,
            group_stage_actions: []
        },
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    presentation = group_status_presentation(html)

    assert %{
             "job_progress" => false,
             "execution_audit" => false,
             "review_origin" => false,
             "recovery" => false
           } ==
             presentation
             |> Map.take(["job_progress", "execution_audit", "review_origin", "recovery"])
             |> Map.new(fn {section, value} -> {section, value["visible"]} end)

    assert presentation["review_origin"]["placements"]["visible"] == false
    assert presentation["recovery"]["failed_item_handoffs"]["visible"] == false
    assert presentation["recovery"]["execution_plan"]["retry_button"]["visible"] == false
    assert presentation["recovery"]["execution_plan"]["advancement_form"]["visible"] == false
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
    html
    |> group_status_presentation()
    |> get_in(["recovery", "execution_plan", "replacement_status"])
  end

  defp group_status_presentation(html) do
    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-historical-workflow-group-status-component"
      )

    assert vue.component == "HistoricalWorkflowGroupStatus"
    assert vue.id == "dashboard-historical-workflow-group-status-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "presentation")
  end

  defp expected_root_attrs do
    %{
      "data-historical-workflow-group-id" => "request-group-1",
      "data-historical-workflow-group-state" => "failed",
      "data-historical-workflow-group-terminal" => "false",
      "data-historical-workflow-group-size" => "4",
      "data-historical-workflow-group-progress" => "2/4",
      "data-historical-workflow-group-requested" => "4",
      "data-historical-workflow-group-approved" => "4",
      "data-historical-workflow-group-started" => "4",
      "data-historical-workflow-group-completed" => "2",
      "data-historical-workflow-group-failed" => "2",
      "data-historical-workflow-group-resolved-failed" => "0",
      "data-historical-workflow-group-retry-resolved" => "0",
      "data-historical-workflow-group-correction-requested" => "0",
      "data-historical-workflow-group-correction-started" => "0",
      "data-historical-workflow-group-correction-completed" => "0",
      "data-historical-workflow-group-correction-superseded" => "0",
      "data-historical-workflow-group-request-eligible" => "false",
      "data-historical-workflow-group-approve-eligible" => "false",
      "data-historical-workflow-group-reject-eligible" => "false",
      "data-historical-workflow-group-start-eligible" => "false",
      "data-historical-workflow-group-complete-eligible" => "false",
      "data-historical-workflow-group-fail-eligible" => "false",
      "data-historical-workflow-group-retryable-failed" => "2",
      "data-historical-workflow-group-nonretryable-failed" => "0",
      "data-historical-workflow-group-comparison-review-request" => "review-request-1",
      "data-historical-workflow-group-comparison-review-kind" =>
        "comparison_open_findings_review",
      "data-historical-workflow-group-comparison-review-open-count" => "2",
      "data-historical-workflow-group-comparison-review-placements" => "placement-1,placement-2",
      "data-historical-workflow-group-comparison-review-workflow-kind" =>
        "bulk_correction_authority_review",
      "data-historical-workflow-group-comparison-review-workflow-action" =>
        "request_comparison_review",
      "data-historical-workflow-group-comparison-review-workflow-selection-kind" =>
        "open_comparison_findings",
      "data-historical-workflow-group-comparison-review-workflow-selection-count" => "2",
      "data-historical-workflow-group-comparison-review-primary-data-view" => "all_revisions",
      "data-historical-workflow-group-comparison-review-compare-data-view" => "canonical",
      "data-historical-workflow-group-handoff-summary" =>
        "group request-group-1; failed; progress 2/4; jobs queued 1, failed 1; failed 2; retryable 2; correction 0; resolved 0; failed items job-1,job-2"
    }
  end

  defp expected_advancement_hidden_fields do
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
      {"reason", "dashboard_recovery_replacement_approved"},
      {"group_transition_scope", "replacement_corrections"},
      {
        "group_correction_tasks",
        "HK.current run-003 replacement run-003-corrected stage requested next approve"
      },
      {"confirmed", "confirmed"}
    ]
    |> Enum.with_index()
    |> Enum.map(fn {{name, value}, index} ->
      %{
        "key" => "historical-workflow-advancement-hidden-#{index}",
        "attrs" => %{
          "type" => "hidden",
          "name" => "historical_workflow_group[#{name}]",
          "value" => value
        }
      }
    end)
  end

  defp expected_advancement_button do
    %{
      "id" => "dashboard-historical-workflow-group-recovery-advance-corrected",
      "type" => "submit",
      "class" => "btn btn-xs btn-primary btn-outline w-full justify-between gap-2",
      "attrs" => %{
        "name" => "historical_workflow_group[stage]",
        "value" => "approved",
        "data-workflow-action-id" => "group-stage-approved",
        "data-workflow-action-eligible" => "true",
        "data-workflow-action-eligible-count" => "1",
        "data-workflow-action-stage" => "approved",
        "data-workflow-action-reason" => "eligible_group_items",
        "data-workflow-action-preview" => "Advance 1 corrected replacement request to approved.",
        "data-workflow-action-correction-tasks" =>
          "HK.current run-003 replacement run-003-corrected stage requested next approve"
      },
      "label" => %{
        "class" => "flex min-w-0 items-center gap-1",
        "text" => "Advance replacements",
        "icon" => %{"name" => "hero-forward", "class" => "h-3.5 w-3.5"}
      },
      "count" => text_presentation("font-mono", "1")
    }
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
         {raw, source, replacement_run, stage, next_action, status},
         {
           job_item,
           event_id,
           job_id,
           job_status,
           job_started,
           job_completed,
           job_age_state,
           job_action
         }
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
    |> Enum.reject(fn {_key, value} -> value in [nil, false] end)
    |> Map.new()
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
