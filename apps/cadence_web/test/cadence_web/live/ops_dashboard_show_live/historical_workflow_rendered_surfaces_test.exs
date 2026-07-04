defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRenderedSurfacesTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionExplanationComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStatusComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobStatusComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowLatestActionComponents

  test "latest_action renders outcome metadata and optional rows" do
    html =
      render_component(&HistoricalWorkflowLatestActionComponents.latest_action/1,
        latest_action_outcome: %{
          class: "border-info/30 bg-info/10",
          action: "retry_job",
          action_label: "Retry job",
          status: "ok",
          status_label: "Queued",
          badge_class: "badge-info",
          reason: "retry_job_queued",
          stage: "started",
          job_id: "job-1",
          count: "1",
          retried: "true",
          retry_nonretryable: "1",
          retry_skipped: "3",
          retry_errors: "0",
          retry_scope: "replacement_jobs",
          retry_run_ids: "run-004-corrected,run-005-corrected",
          retry_disposition: %{
            nonretryable_run_ids: "run-nonretryable",
            nonretryable_event_ids: "failed-event-nonretryable",
            nonretryable_items:
              "run=run-nonretryable event=failed-event-nonretryable action=correct_workflow_request reason=correction_required",
            skipped_run_ids: "run-skipped",
            skipped_event_ids: "failed-event-skipped",
            skipped_items:
              "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed"
          },
          retry_error_run_ids: "run-004-corrected",
          retry_error_event_ids: "failed-event-4",
          retry_error_items:
            "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down",
          queued_jobs: "2",
          failed_jobs: "0",
          result_event_ids: "retry-event-1",
          target_event_id: "source-event-1",
          target_run_id: "run-1",
          message: "Historical workflow job retry queued."
        },
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&panel=versions&activity_filter=open_comparison_reviews&activity_event=review-event-1&selected_placement=placement-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["retry_job"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action")

    assert ["retry-event-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-result-event-ids")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-queued-jobs")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-nonretryable")

    assert ["3"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-skipped")

    assert ["0"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-errors")

    assert ["replacement_jobs"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-scope")

    assert ["run-004-corrected,run-005-corrected"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-run-ids")

    assert ["run-nonretryable"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-nonretryable-run-ids")

    assert ["failed-event-nonretryable"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-nonretryable-event-ids")

    assert [
             "run=run-nonretryable event=failed-event-nonretryable action=correct_workflow_request reason=correction_required"
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-nonretryable-items")

    assert ["run-skipped"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-skipped-run-ids")

    assert ["failed-event-skipped"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-skipped-event-ids")

    assert [
             "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed"
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-skipped-items")

    assert ["run-004-corrected"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-error-run-ids")

    assert ["failed-event-4"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-error-event-ids")

    assert [
             "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down"
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-error-items")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
           |> LazyHTML.text()
           |> String.contains?(
             "run=run-nonretryable event=failed-event-nonretryable action=correct_workflow_request reason=correction_required"
           )

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
           |> LazyHTML.text()
           |> String.contains?(
             "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed"
           )

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
           |> LazyHTML.text()
           |> String.contains?(
             "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down"
           )

    assert ["0"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-failed-jobs")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-handoff-count")

    assert ["source-event-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-primary-result-event-id")

    handoffs =
      document
      |> LazyHTML.query("[data-workflow-latest-action-handoff]")
      |> Enum.map(fn node ->
        event_id =
          node
          |> LazyHTML.attribute("data-workflow-latest-action-handoff")
          |> List.first()

        role =
          node
          |> LazyHTML.attribute("data-workflow-latest-action-handoff-role")
          |> List.first()

        href =
          node
          |> LazyHTML.attribute("data-workflow-latest-action-handoff-href")
          |> List.first()

        {event_id, role, review_href_query(href)}
      end)

    assert handoffs == [
             {"source-event-1", "target",
              %{
                "scope_kind" => "mission",
                "scope_id" => "mission-1",
                "panel" => "data_link",
                "selected_target" => "telemetry_backfill_lifecycle_event",
                "selected_id" => "source-event-1"
              }},
             {"retry-event-1", "result",
              %{
                "scope_kind" => "mission",
                "scope_id" => "mission-1",
                "panel" => "data_link",
                "selected_target" => "telemetry_backfill_lifecycle_event",
                "selected_id" => "retry-event-1"
              }}
           ]

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
           |> LazyHTML.text()
           |> String.contains?("Historical workflow job retry queued.")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
           |> LazyHTML.text()
           |> String.contains?("retry_job_queued")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
           |> LazyHTML.text()
           |> String.contains?("Queued")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
           |> LazyHTML.text()
           |> String.contains?("Skipped")
  end

  test "action_explanations renders unavailable workflow actions" do
    html =
      render_component(&HistoricalWorkflowActionExplanationComponents.action_explanations/1,
        blocked_action_explanations: [
          %{
            id: "correction_request",
            kind: "correction",
            label: "Request correction",
            reason: "job_failed",
            explanation: "A correction request needs failed job evidence.",
            state_summary: "job job-1; status failed",
            available_when: "Available after review."
          }
        ]
      )

    document = LazyHTML.from_fragment(html)

    assert ["correction_request"] =
             document
             |> LazyHTML.query("[data-workflow-action-explanation-id]")
             |> LazyHTML.attribute("data-workflow-action-explanation-id")

    assert ["job job-1; status failed"] =
             document
             |> LazyHTML.query("[data-workflow-action-explanation-state]")
             |> LazyHTML.attribute("data-workflow-action-explanation-state")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-action-explanations")
           |> LazyHTML.text()
           |> String.contains?("Available after review.")
  end

  test "group_status renders group progress and retry action metadata" do
    html =
      render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
        workflow_context: group_context(),
        workflow_controls: %{
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
        },
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&panel=data_link"
      )

    document = LazyHTML.from_fragment(html)

    assert ["request-group-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
             |> LazyHTML.attribute("data-historical-workflow-group-id")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
             |> LazyHTML.attribute("data-historical-workflow-group-retryable-failed")

    assert ["review-request-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
             |> LazyHTML.attribute("data-historical-workflow-group-comparison-review-request")

    assert ["comparison_open_findings_review"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
             |> LazyHTML.attribute("data-historical-workflow-group-comparison-review-kind")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
             |> LazyHTML.attribute("data-historical-workflow-group-comparison-review-open-count")

    assert ["placement-1,placement-2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
             |> LazyHTML.attribute("data-historical-workflow-group-comparison-review-placements")

    assert ["bulk_correction_authority_review"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-comparison-review-workflow-kind"
             )

    assert ["request_comparison_review"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-comparison-review-workflow-action"
             )

    assert ["open_comparison_findings"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-comparison-review-workflow-selection-kind"
             )

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-comparison-review-workflow-selection-count"
             )

    assert ["all_revisions"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-review-origin")
             |> LazyHTML.attribute("data-historical-workflow-review-origin-primary-data-view")

    assert ["canonical"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-review-origin")
             |> LazyHTML.attribute("data-historical-workflow-review-origin-compare-data-view")

    assert ["review-request-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-review-origin")
             |> LazyHTML.attribute("data-historical-workflow-review-origin-request")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-review-origin")
             |> LazyHTML.attribute("data-historical-workflow-review-origin-placement-count")

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

    placement_hrefs =
      document
      |> LazyHTML.query("[data-historical-workflow-review-origin-placement]")
      |> Enum.map(fn node ->
        placement =
          node
          |> LazyHTML.attribute("data-historical-workflow-review-origin-placement")
          |> List.first()

        href =
          node
          |> LazyHTML.attribute("data-historical-workflow-review-origin-placement-href")
          |> List.first()

        {placement, review_href_query(href)}
      end)

    assert placement_hrefs == [
             {"placement-1",
              %{
                "scope_kind" => "mission",
                "scope_id" => "mission-1",
                "panel" => "versions",
                "activity_filter" => "open_comparison_reviews",
                "activity_event" => "review-request-1",
                "selected_placement" => "placement-1"
              }},
             {"placement-2",
              %{
                "scope_kind" => "mission",
                "scope_id" => "mission-1",
                "panel" => "versions",
                "activity_filter" => "open_comparison_reviews",
                "activity_event" => "review-request-1",
                "selected_placement" => "placement-2"
              }}
           ]

    assert ["queued 1, failed 1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-job-progress")
             |> LazyHTML.attribute("data-historical-workflow-group-job-progress")

    assert [
             "group request-group-1; failed; progress 2/4; jobs queued 1, failed 1; failed 2; retryable 2; correction 0; resolved 0; failed items job-1,job-2"
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
             |> LazyHTML.attribute("data-historical-workflow-group-handoff-summary")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
           |> LazyHTML.text()
           |> String.contains?("review-request-1")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-group-summary")
           |> LazyHTML.text()
           |> String.contains?("failed items job-1,job-2")

    assert [
             "1:HK.counter run-001 queued job-1; 2:HK.voltage run-002 failed job-2"
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-job-progress")
             |> LazyHTML.attribute("data-historical-workflow-group-job-items")

    assert [
             "1:HK.counter run-001 queued job-1",
             "2:HK.voltage run-002 failed job-2"
           ] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-job-item]")
             |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

    assert ["9"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-execution-audit")
             |> LazyHTML.attribute("data-historical-workflow-group-execution-audit-count")

    assert [
             "requested 4; approved 4; started 4; job_progress queued 1, failed 1; completed 2; failed 2; retried 0; corrected 0; recovery_tasks 1"
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-execution-audit")
             |> LazyHTML.attribute("data-historical-workflow-group-execution-audit-summary")

    assert ["2"] =
             document
             |> LazyHTML.query(~s([data-historical-workflow-group-execution-step="failed"]))
             |> LazyHTML.attribute("data-historical-workflow-group-execution-count")

    assert ["job-1,job-2"] =
             document
             |> LazyHTML.query(~s([data-historical-workflow-group-execution-step="failed"]))
             |> LazyHTML.attribute("data-historical-workflow-group-execution-detail")

    assert ["HK.voltage run-002 retried queued job-2"] =
             document
             |> LazyHTML.query(~s([data-historical-workflow-group-execution-step="retried"]))
             |> LazyHTML.attribute("data-historical-workflow-group-execution-detail")

    assert ["HK.current run-003 replacement run-003-corrected stage requested next approve"] =
             document
             |> LazyHTML.query(
               ~s([data-historical-workflow-group-execution-step="recovery_tasks"])
             )
             |> LazyHTML.attribute("data-historical-workflow-group-execution-detail")

    assert ["request-group-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-id")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-retryable")

    assert ["0"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-correction")

    assert ["HK.voltage run-002 retried queued job-2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-retried-items")

    assert ["HK.current run-003 corrected run-003-corrected requested job-3"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-corrected-items")

    assert ["HK.current run-003 replacement run-003-corrected stage requested next approve"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-correction-tasks")

    assert [
             "label=HK.voltage run=run-002 event=failed-event-2 recovery=retry_job retryable=true; label=HK.current run=run-003 event=failed-event-3 recovery=correct_workflow_request retryable=false"
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-failed-item-events")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-failed-item-handoffs")

    assert ["2"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-group-recovery-failed-item-handoffs"
             )
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-failed-item-handoff-count"
             )

    failed_item_handoffs =
      document
      |> LazyHTML.query("[data-historical-workflow-group-recovery-failed-item]")
      |> Enum.map(fn node ->
        event_id =
          node
          |> LazyHTML.attribute("data-historical-workflow-group-recovery-failed-item")
          |> List.first()

        recovery =
          node
          |> LazyHTML.attribute("data-historical-workflow-group-recovery-failed-item-recovery")
          |> List.first()

        retryable =
          node
          |> LazyHTML.attribute("data-historical-workflow-group-recovery-failed-item-retryable")
          |> List.first()

        href =
          node
          |> LazyHTML.attribute("data-historical-workflow-group-recovery-failed-item-href")
          |> List.first()

        {event_id, recovery, retryable, review_href_query(href)}
      end)

    assert failed_item_handoffs == [
             {"failed-event-2", "retry_job", "true",
              %{
                "scope_kind" => "mission",
                "scope_id" => "mission-1",
                "panel" => "data_link",
                "selected_target" => "telemetry_backfill_lifecycle_event",
                "selected_id" => "failed-event-2"
              }},
             {"failed-event-3", "correct_workflow_request", "false",
              %{
                "scope_kind" => "mission",
                "scope_id" => "mission-1",
                "panel" => "data_link",
                "selected_target" => "telemetry_backfill_lifecycle_event",
                "selected_id" => "failed-event-3"
              }}
           ]

    assert ["review-request-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-review-request")

    assert ["placement-1,placement-2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-review-placements")

    assert ["retry_failed_items"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-next-action")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-unresolved")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-correction-task-count"
             )

    assert ["retry_failed_items"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-guidance")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-guidance-next-action")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-guidance")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-guidance-retry-eligible"
             )

    assert ["retryable_group_failures"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-guidance")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-guidance-retry-reason"
             )

    assert ["Retry every retryable failed job."] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-guidance")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-guidance-retry-preview"
             )

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-guidance")
           |> LazyHTML.text()
           |> String.contains?("Retry every retryable failed job.")

    assert ["request-group-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-execution-plan")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-execution-plan-request-group"
             )

    assert ["retry_failed_items"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-execution-plan")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-execution-plan-next-action"
             )

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-execution-plan")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-execution-plan-retry-eligible"
             )

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-execution-plan")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-execution-plan-retry-count"
             )

    assert [
             "Retry will requeue 2 failed items and select the retried lifecycle event."
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-execution-plan")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-execution-plan-expected-effect"
             )

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-execution-plan")
           |> LazyHTML.text()
           |> String.contains?("Retry will requeue 2 failed items")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-remaining-work-count")

    assert ["operator_action_required"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-status")

    assert ["retry_failed_items"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-action")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-unresolved")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-closure-pending-replacements"
             )

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-active-jobs")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-blocked-jobs")

    assert ["0"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-failed-jobs")

    assert ["0"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-missing-jobs")

    assert [
             "status operator_action_required; action retry_failed_items; unresolved 2; replacements pending 1 completed 0; jobs active 1 blocked 1 failed 0 missing 0 stale 0; complete_eligible 0"
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-summary")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-pending-count"
             )

    assert ["0"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-completed-count"
             )

    assert ["approve"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-next-actions"
             )

    assert ["run-003-corrected"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-pending-runs"
             )

    assert [
             "run-003-corrected requested next approve pending"
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-summary"
             )

    assert ["run-003-corrected"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-recovery-remaining-work-item]")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-replacement-run"
             )

    assert ["requested"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-recovery-remaining-work-item]")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-remaining-work-stage")

    assert ["approve"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-recovery-remaining-work-item]")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-next-action"
             )

    assert ["pending"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-recovery-remaining-work-item]")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-status"
             )

    assert ["approved"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-execution-plan")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-execution-plan-replacement-stage"
             )

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-execution-plan")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-execution-plan-replacement-eligible"
             )

    assert ["request-group-1"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-group-recovery-advance-corrected-form"
             )
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-advance-request-group"
             )

    assert ["approved"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-group-recovery-advance-corrected-form"
             )
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-advance-stage")

    assert ["HK.current run-003 replacement run-003-corrected stage requested next approve"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-group-recovery-advance-corrected-form"
             )
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-advance-correction-tasks"
             )

    assert ["dashboard_recovery_replacement_approved"] =
             document
             |> LazyHTML.query(~s(input[name="historical_workflow_group[reason]"]))
             |> LazyHTML.attribute("value")

    assert ["replacement_corrections"] =
             document
             |> LazyHTML.query(
               ~s(input[name="historical_workflow_group[group_transition_scope]"])
             )
             |> LazyHTML.attribute("value")

    assert ["HK.current run-003 replacement run-003-corrected stage requested next approve"] =
             document
             |> LazyHTML.query(
               ~s(input[name="historical_workflow_group[group_correction_tasks]"])
             )
             |> LazyHTML.attribute("value")

    assert ["approved"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-advance-corrected")
             |> LazyHTML.attribute("value")

    assert ["approved"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-advance-corrected")
             |> LazyHTML.attribute("data-workflow-action-stage")

    assert ["HK.current run-003 replacement run-003-corrected stage requested next approve"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-advance-corrected")
             |> LazyHTML.attribute("data-workflow-action-correction-tasks")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-retry-failed")
             |> LazyHTML.attribute("data-workflow-action-eligible-count")

    assert [
             "Retry will requeue 2 failed items and select the retried lifecycle event."
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-retry-failed")
             |> LazyHTML.attribute("data-workflow-action-expected-effect")

    recovery_review_href =
      document
      |> LazyHTML.query("[data-historical-workflow-group-recovery-review-origin-link]")
      |> LazyHTML.attribute("data-historical-workflow-group-recovery-review-origin-href")
      |> List.first()

    assert review_href_query(recovery_review_href) == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_filter" => "open_comparison_reviews",
             "activity_event" => "review-request-1"
           }

    assert ["HK.voltage run-002 retried queued job-2"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-retried-item]")
             |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

    assert ["HK.current run-003 corrected run-003-corrected requested job-3"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-corrected-item]")
             |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

    assert ["HK.current run-003 replacement run-003-corrected stage requested next approve"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-correction-task]")
             |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-group-recovery")
           |> LazyHTML.text()
           |> String.contains?("job-1,job-2")

    assert ["retry_historical_workflow_group_failed_jobs"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-retry-failed")
             |> LazyHTML.attribute("phx-click")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-retry-failed")
             |> LazyHTML.attribute("data-workflow-action-eligible")
  end

  test "group_status summarizes mixed replacement work across correction tasks" do
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
          )
          |> Map.put(
            :request_group_corrected_items,
            "HK.current run-003 corrected run-003-corrected requested job-3; HK.voltage run-004 corrected run-004-corrected approved job-4; HK.gyro run-006 corrected run-006-corrected started job-6; HK.temp run-005 corrected run-005-corrected completed job-5"
          ),
        workflow_controls: %{
          group_summary: true,
          group_retryable_failures: true,
          group_retry_action: %{
            id: "retry-group-failed",
            eligible?: true,
            reason: "retryable_group_failures",
            preview: "Retry failed corrected replacement jobs."
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
          ]
        },
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&panel=data_link"
      )

    document = LazyHTML.from_fragment(html)

    assert ["4"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-remaining-work-count")

    assert ["3"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-pending-count"
             )

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-completed-count"
             )

    assert ["approve,start,complete"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-next-actions"
             )

    assert ["run-003-corrected,run-004-corrected,run-006-corrected"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-pending-runs"
             )

    assert [
             "run-003-corrected requested next approve pending; run-004-corrected approved next start pending; run-006-corrected started next complete pending; run-005-corrected completed next done complete"
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-summary"
             )

    assert [
             "run-003-corrected queued job-3 wait_for_replacement_job_start; run-004-corrected failed job-4 inspect_failed_replacement_job; run-006-corrected running job-6 inspect_stale_replacement_job; run-005-corrected completed job-5 replacement_complete"
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-job-summary"
             )

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-active-jobs"
             )

    assert ["run-003-corrected,run-006-corrected"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-active-runs"
             )

    assert [
             "run-003-corrected queued job-3 wait_for_replacement_job_start; run-006-corrected running job-6 inspect_stale_replacement_job"
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-active-summary"
             )

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-stale-jobs"
             )

    assert ["run-006-corrected"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-stale-runs"
             )

    assert [
             "run-006-corrected running job-6 2023-11-14T22:00:00Z inspect_stale_replacement_job"
           ] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-stale-summary"
             )

    assert ["1"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-group-recovery-stale-replacement-jobs"
             )
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-stale-replacement-job-count"
             )

    assert ["2"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-group-recovery-active-replacement-jobs"
             )
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-active-replacement-job-count"
             )

    assert ["run-003-corrected,run-006-corrected"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-group-recovery-active-replacement-jobs"
             )
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-active-replacement-runs"
             )

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-blocked-jobs"
             )

    assert ["retry_historical_workflow_group_failed_jobs"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-retry-failed-replacements")
             |> LazyHTML.attribute("phx-click")

    assert ["replacement_jobs"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-retry-failed-replacements")
             |> LazyHTML.attribute("data-workflow-action-scope")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-retry-failed-replacements")
             |> LazyHTML.attribute("data-workflow-action-eligible-count")

    assert ["run-004-corrected"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-retry-failed-replacements")
             |> LazyHTML.attribute("phx-value-retry-run-ids")

    assert ["run-003-corrected", "run-004-corrected", "run-006-corrected", "run-005-corrected"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-recovery-remaining-work-item]")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-replacement-run"
             )

    assert ["requested", "approved", "started", "completed"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-recovery-remaining-work-item]")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-remaining-work-stage")

    assert ["pending", "pending", "pending", "complete"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-recovery-remaining-work-item]")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-status"
             )

    assert ["queued", "failed", "running", "completed"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-recovery-remaining-work-item]")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-job-status"
             )

    assert ["job-3", "job-4", "job-6", "job-5"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-recovery-remaining-work-item]")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-job-id"
             )

    assert ["event-3", "event-4", "event-6", "event-5"] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-recovery-remaining-work-item]")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-event-id"
             )

    assert ["2023-11-14T22:00:00Z"] =
             document
             |> LazyHTML.query(
               ~s([data-historical-workflow-group-recovery-remaining-work-replacement-run="run-006-corrected"])
             )
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-job-started"
             )

    assert ["stale"] =
             document
             |> LazyHTML.query(
               ~s([data-historical-workflow-group-recovery-remaining-work-replacement-run="run-006-corrected"])
             )
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-job-age-state"
             )

    assert ["active"] =
             document
             |> LazyHTML.query(
               ~s([data-historical-workflow-group-recovery-remaining-work-replacement-run="run-003-corrected"])
             )
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-job-age-state"
             )

    assert [
             "wait_for_replacement_job_start",
             "inspect_failed_replacement_job",
             "inspect_stale_replacement_job",
             "replacement_complete"
           ] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-recovery-remaining-work-item]")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-job-action"
             )

    assert [
             "3:HK.current run-003-corrected queued job-3 event=event-3",
             "4:HK.voltage run-004-corrected failed job-4 event=event-4",
             "6:HK.gyro run-006-corrected running job-6 event=event-6 started=2023-11-14T22:00:00Z",
             "5:HK.temp run-005-corrected completed job-5 event=event-5 completed=2023-11-14T22:05:00Z"
           ] =
             document
             |> LazyHTML.query("[data-historical-workflow-group-recovery-remaining-work-item]")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-job-item"
             )

    assert ["inspect_stale_historical_workflow_replacement_job"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-stale-replacement-inspect-run-006-corrected"
             )
             |> LazyHTML.attribute("phx-click")

    assert ["job-6"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-stale-replacement-inspect-run-006-corrected"
             )
             |> LazyHTML.attribute("phx-value-job-id")

    assert ["event-6"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-stale-replacement-inspect-run-006-corrected"
             )
             |> LazyHTML.attribute("phx-value-event-id")

    assert ["requeue_stale_historical_workflow_replacement_job"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-stale-replacement-requeue-run-006-corrected"
             )
             |> LazyHTML.attribute("phx-click")

    assert ["requeue_stale_replacement_job"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-stale-replacement-requeue-run-006-corrected"
             )
             |> LazyHTML.attribute("data-workflow-action-id")

    assert ["job-6"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-stale-replacement-requeue-run-006-corrected"
             )
             |> LazyHTML.attribute("phx-value-job-id")

    assert ["event-6"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-stale-replacement-requeue-run-006-corrected"
             )
             |> LazyHTML.attribute("phx-value-event-id")
  end

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
      render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
        workflow_context:
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
        workflow_controls:
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
          ]),
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )
      |> LazyHTML.from_fragment()

    assert ["replacement_work_pending"] =
             replacement_pending
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-status")

    assert ["advance_corrected_requests"] =
             replacement_pending
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-action")

    monitor_jobs =
      render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
        workflow_context:
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
        workflow_controls: base_controls,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )
      |> LazyHTML.from_fragment()

    assert ["monitor_jobs"] =
             monitor_jobs
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-status")

    assert ["monitor_replacement_jobs"] =
             monitor_jobs
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-action")

    ready_to_complete =
      render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
        workflow_context:
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
        workflow_controls: base_controls,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )
      |> LazyHTML.from_fragment()

    assert ["ready_to_complete"] =
             ready_to_complete
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-status")

    assert ["complete_group"] =
             ready_to_complete
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-action")

    assert ["record_historical_workflow_group_stage"] =
             ready_to_complete
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-complete-form")
             |> LazyHTML.attribute("phx-submit")

    assert ["request-group-1"] =
             ready_to_complete
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-complete-form")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-complete-request-group"
             )

    assert ["completed"] =
             ready_to_complete
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-complete-form")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-complete-stage")

    assert ["true"] =
             ready_to_complete
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-complete-form")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-complete-eligible")

    assert ["1"] =
             ready_to_complete
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-complete-form")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-complete-count")

    assert ["dashboard_recovery_group_completed"] =
             ready_to_complete
             |> LazyHTML.query(~s(input[name="historical_workflow_group[reason]"]))
             |> LazyHTML.attribute("value")

    assert ["completed"] =
             ready_to_complete
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-complete")
             |> LazyHTML.attribute("value")

    assert ["group-stage-completed"] =
             ready_to_complete
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-complete")
             |> LazyHTML.attribute("data-workflow-action-id")

    assert ["1"] =
             ready_to_complete
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-complete")
             |> LazyHTML.attribute("data-workflow-action-eligible-count")
  end

  test "group_status renders missing replacement job evidence as blocked follow-up work" do
    html =
      render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
        workflow_context:
          group_context()
          |> Map.merge(%{
            request_group_job_progress: "completed 2",
            request_group_job_items: "",
            request_group_failed: "1",
            request_group_resolved_failed: "1",
            request_group_retryable_failed: "0",
            request_group_nonretryable_failed: "0",
            request_group_complete_eligible: "1",
            request_group_correction_tasks:
              "HK.power run-006 replacement run-006-corrected stage completed next done"
          }),
        workflow_controls: %{
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
        },
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )
      |> LazyHTML.from_fragment()

    assert ["1"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-missing-jobs"
             )

    assert ["run-006-corrected"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-missing-runs"
             )

    assert [
             "run-006-corrected missing job-missing inspect_missing_replacement_job"
           ] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-job-summary"
             )

    assert ["missing"] =
             html
             |> LazyHTML.query("[data-historical-workflow-group-recovery-remaining-work-item]")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-job-status"
             )

    assert ["inspect_missing_replacement_job"] =
             html
             |> LazyHTML.query("[data-historical-workflow-group-recovery-remaining-work-item]")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-job-action"
             )

    assert ["inspect_missing_historical_workflow_replacement_job"] =
             html
             |> LazyHTML.query(
               "#dashboard-historical-workflow-missing-replacement-inspect-run-006-corrected"
             )
             |> LazyHTML.attribute("phx-click")

    assert ["request-group-1"] =
             html
             |> LazyHTML.query(
               "#dashboard-historical-workflow-missing-replacement-inspect-run-006-corrected"
             )
             |> LazyHTML.attribute("phx-value-request-group-id")

    assert ["run-006-corrected"] =
             html
             |> LazyHTML.query(
               "#dashboard-historical-workflow-missing-replacement-inspect-run-006-corrected"
             )
             |> LazyHTML.attribute("phx-value-replacement-run-id")

    assert ["inspect_missing_replacement_job"] =
             html
             |> LazyHTML.query(
               "#dashboard-historical-workflow-missing-replacement-inspect-run-006-corrected"
             )
             |> LazyHTML.attribute("data-workflow-action-id")

    assert ["replacement_job"] =
             html
             |> LazyHTML.query(
               "#dashboard-historical-workflow-missing-replacement-inspect-run-006-corrected"
             )
             |> LazyHTML.attribute("data-workflow-action-scope")

    assert ["1"] =
             html
             |> LazyHTML.query(
               "#dashboard-historical-workflow-group-recovery-missing-replacement-jobs"
             )
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-missing-replacement-job-count"
             )

    assert [
             "run-006-corrected completed next done inspect_missing_replacement_job"
           ] =
             html
             |> LazyHTML.query(
               "#dashboard-historical-workflow-group-recovery-missing-replacement-jobs"
             )
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-missing-replacement-summary"
             )

    assert ["inspect_job_state"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-status")

    assert ["inspect_missing_replacement_jobs"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-action")

    assert ["0"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-failed-jobs")

    assert [""] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-failed-runs")

    assert ["1"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-missing-jobs")

    assert ["run-006-corrected"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-missing-runs")

    assert [
             "status inspect_job_state; action inspect_missing_replacement_jobs; unresolved 0; replacements pending 0 completed 1; jobs active 0 blocked 1 failed 0 missing 1 stale 0; complete_eligible 1"
           ] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-summary")
  end

  test "group_status promotes failed replacement jobs to scoped retry recovery" do
    html =
      render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
        workflow_context:
          group_context()
          |> Map.merge(%{
            request_group_job_progress: "failed 1, completed 1",
            request_group_job_items: "6:HK.power run-006-corrected failed job-6",
            request_group_failed: "1",
            request_group_resolved_failed: "1",
            request_group_retryable_failed: "0",
            request_group_nonretryable_failed: "0",
            request_group_complete_eligible: "1",
            request_group_correction_tasks:
              "HK.power run-006 replacement run-006-corrected stage completed next done"
          }),
        workflow_controls: %{
          group_summary: true,
          group_retryable_failures: false,
          group_retry_action: %{
            id: "group-retry-failed-items",
            eligible?: true,
            eligible_count: 1,
            reason: "failed_replacement_job",
            preview: "Retry 1 failed replacement job."
          },
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
        },
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )
      |> LazyHTML.from_fragment()

    assert ["inspect_job_state"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-status")

    assert ["retry_failed_replacement_jobs"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-action")

    assert ["1"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-blocked-jobs")

    assert ["1"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-failed-jobs")

    assert ["run-006-corrected"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-failed-runs")

    assert ["0"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-missing-jobs")

    assert [""] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-missing-runs")

    assert [
             "status inspect_job_state; action retry_failed_replacement_jobs; unresolved 0; replacements pending 0 completed 1; jobs active 0 blocked 1 failed 1 missing 0 stale 0; complete_eligible 1"
           ] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-summary")
  end

  test "group_status prioritizes blocked replacement job evidence over active jobs" do
    html =
      render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
        workflow_context:
          group_context()
          |> Map.merge(%{
            request_group_job_progress: "running 1, missing 1, completed 1",
            request_group_job_items: "3:HK.current run-003-corrected running job-3",
            request_group_failed: "2",
            request_group_resolved_failed: "2",
            request_group_retryable_failed: "0",
            request_group_nonretryable_failed: "0",
            request_group_complete_eligible: "1",
            request_group_correction_tasks:
              "HK.current run-003 replacement run-003-corrected stage completed next done; " <>
                "HK.power run-006 replacement run-006-corrected stage completed next done"
          }),
        workflow_controls: %{
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
        },
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )
      |> LazyHTML.from_fragment()

    assert ["1"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-active-jobs")

    assert ["1"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-blocked-jobs")

    assert ["0"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-failed-jobs")

    assert ["1"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-missing-jobs")

    assert ["run-006-corrected"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-missing-runs")

    assert ["inspect_job_state"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-status")

    assert ["inspect_missing_replacement_jobs"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-action")

    assert [
             "status inspect_job_state; action inspect_missing_replacement_jobs; unresolved 0; replacements pending 0 completed 2; jobs active 1 blocked 1 failed 0 missing 1 stale 0; complete_eligible 1"
           ] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-summary")

    assert [] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-complete-form")
             |> LazyHTML.attribute("phx-submit")
  end

  test "group_status treats stale replacement jobs as operator recovery work" do
    stale_started_at =
      DateTime.utc_now()
      |> DateTime.add(-20, :minute)
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

    html =
      render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
        workflow_context:
          group_context()
          |> Map.merge(%{
            request_group_job_progress: "running 1, completed 1",
            request_group_job_items:
              "3:HK.current run-003-corrected running job-3 event=event-3 started=#{stale_started_at}",
            request_group_failed: "1",
            request_group_resolved_failed: "1",
            request_group_retryable_failed: "0",
            request_group_nonretryable_failed: "0",
            request_group_complete_eligible: "1",
            request_group_correction_tasks:
              "HK.current run-003 replacement run-003-corrected stage started next complete"
          }),
        workflow_controls: %{
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
        },
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )
      |> LazyHTML.from_fragment()

    assert ["1"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-stale-jobs")

    assert ["run-003-corrected"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-stale-runs")

    assert ["inspect_job_state"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-status")

    assert ["inspect_stale_replacement_jobs"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-action")

    assert [
             "status inspect_job_state; action inspect_stale_replacement_jobs; unresolved 0; replacements pending 1 completed 0; jobs active 1 blocked 0 failed 0 missing 0 stale 1; complete_eligible 1"
           ] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-summary")

    assert [] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-complete-form")
             |> LazyHTML.attribute("phx-submit")
  end

  test "group_status exposes mixed blocked replacement recovery actions" do
    stale_started_at =
      DateTime.utc_now()
      |> DateTime.add(-20, :minute)
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

    html =
      render_component(&HistoricalWorkflowGroupStatusComponents.group_status/1,
        workflow_context:
          group_context()
          |> Map.merge(%{
            request_group_job_progress: "running 1, failed 1, missing 1",
            request_group_job_items:
              "6:HK.power run-006-corrected failed job-6 event=event-6 started=2026-07-01T11:30:00Z; " <>
                "7:HK.temp run-007-corrected running job-7 event=event-7 started=#{stale_started_at}",
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
        workflow_controls: %{
          group_summary: true,
          group_retryable_failures: true,
          group_retry_action: %{
            id: "group-retry-failed-items",
            eligible?: true,
            eligible_count: 1,
            reason: "retryable_replacement_failure",
            preview: "Retry 1 failed replacement job."
          },
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
        },
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )
      |> LazyHTML.from_fragment()

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

    assert ["2"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-blocked-jobs")

    assert ["1"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-closure-readiness")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-closure-failed-jobs")

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

    assert ["run-006-corrected"] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-retry-failed-replacements")
             |> LazyHTML.attribute("data-workflow-action-retry-run-ids")

    assert ["inspect_missing_replacement_job"] =
             html
             |> LazyHTML.query(
               "#dashboard-historical-workflow-missing-replacement-inspect-run-003-corrected"
             )
             |> LazyHTML.attribute("data-workflow-action-id")

    assert ["inspect_stale_replacement_job"] =
             html
             |> LazyHTML.query(
               "#dashboard-historical-workflow-stale-replacement-inspect-run-007-corrected"
             )
             |> LazyHTML.attribute("data-workflow-action-id")

    assert [] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-complete-form")
             |> LazyHTML.attribute("phx-submit")
  end

  test "job_status renders failed job diagnostics and retry action metadata" do
    html =
      render_component(&HistoricalWorkflowJobStatusComponents.job_status/1,
        workflow_context: %{
          event_id: "source-event-1",
          job_id: "job-1",
          job_status: "failed",
          job_attempts: "1",
          job_failure: "dispatcher unavailable",
          failure_code: "dispatcher_down",
          retryable: "true",
          recovery_action: "retry_job",
          retry_blockers: "",
          comparison_review_request_event_id: "review-request-1",
          comparison_review_request_kind: "comparison_open_findings_review",
          comparison_review_open_count: "2",
          comparison_review_open_placement_ids: "placement-1,placement-2"
        },
        workflow_controls: %{
          job_status: true,
          job_status_class: "border-error/30 bg-error/10",
          job_retryable: true,
          job_retry_action: %{
            id: "retry-job",
            eligible?: true,
            reason: "failed_job_retryable",
            preview: "Retry job job-1.",
            explanation: "This failed workflow job can be retried.",
            state_summary: "job job-1; status failed; retryable true; recovery retry_job"
          },
          correction_request_action: %{
            id: "correction-request",
            eligible?: false,
            reason: "correction_not_required",
            preview: "Correction request is not currently eligible",
            explanation: "This failure does not require a corrected workflow request.",
            state_summary: "job job-1; status failed; retryable true; recovery retry_job",
            available_when:
              "Correction becomes available when the failure recovery action requires a corrected request."
          }
        },
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&panel=data_link"
      )

    document = LazyHTML.from_fragment(html)

    assert ["job-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-status")
             |> LazyHTML.attribute("data-historical-workflow-job-id")

    assert ["review-request-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-status")
             |> LazyHTML.attribute("data-historical-workflow-job-comparison-review-request")

    assert ["retry_job"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-status")
             |> LazyHTML.attribute("data-historical-workflow-job-next-action")

    assert ["retry_job"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
             |> LazyHTML.attribute("data-historical-workflow-job-guidance-next-action")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
             |> LazyHTML.attribute("data-historical-workflow-job-guidance-retry-eligible")

    assert ["failed_job_retryable"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
             |> LazyHTML.attribute("data-historical-workflow-job-guidance-retry-reason")

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
             |> LazyHTML.attribute("data-historical-workflow-job-guidance-correction-eligible")

    assert ["correction_not_required"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
             |> LazyHTML.attribute("data-historical-workflow-job-guidance-correction-reason")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
           |> LazyHTML.text()
           |> String.contains?("Retry job job-1.")

    assert ["review-request-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-review-origin")
             |> LazyHTML.attribute("data-historical-workflow-job-review-origin-request")

    job_review_href =
      document
      |> LazyHTML.query("[data-historical-workflow-job-review-origin-link]")
      |> LazyHTML.attribute("data-historical-workflow-job-review-origin-href")
      |> List.first()

    assert review_href_query(job_review_href) == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_filter" => "open_comparison_reviews",
             "activity_event" => "review-request-1"
           }

    job_placement_hrefs =
      document
      |> LazyHTML.query("[data-historical-workflow-job-review-origin-placement]")
      |> Enum.map(fn node ->
        placement =
          node
          |> LazyHTML.attribute("data-historical-workflow-job-review-origin-placement")
          |> List.first()

        href =
          node
          |> LazyHTML.attribute("data-historical-workflow-job-review-origin-placement-href")
          |> List.first()

        {placement, review_href_query(href)}
      end)

    assert job_placement_hrefs == [
             {"placement-1",
              %{
                "scope_kind" => "mission",
                "scope_id" => "mission-1",
                "panel" => "versions",
                "activity_filter" => "open_comparison_reviews",
                "activity_event" => "review-request-1",
                "selected_placement" => "placement-1"
              }},
             {"placement-2",
              %{
                "scope_kind" => "mission",
                "scope_id" => "mission-1",
                "panel" => "versions",
                "activity_filter" => "open_comparison_reviews",
                "activity_event" => "review-request-1",
                "selected_placement" => "placement-2"
              }}
           ]

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-job-status")
           |> LazyHTML.text()
           |> String.contains?("dispatcher unavailable")

    assert ["retry_historical_workflow_job"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-retry-job")
             |> LazyHTML.attribute("phx-click")

    assert ["job-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-retry-job")
             |> LazyHTML.attribute("phx-value-job-id")
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
        "label=HK.voltage run=run-002 event=failed-event-2 recovery=retry_job retryable=true; label=HK.current run=run-003 event=failed-event-3 recovery=correct_workflow_request retryable=false"
    }
  end

  defp review_href_query(href) do
    href
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end
end
