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

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute("data-historical-workflow-group-recovery-remaining-work-count")

    assert ["run-003-corrected"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-recovery-remaining-work")
             |> LazyHTML.attribute(
               "data-historical-workflow-group-recovery-remaining-work-pending-runs"
             )

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
