defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowLatestActionComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowLatestActionComponents

  test "latest_action renders result handoff links and retry disposition details" do
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
          retry_skipped: "1",
          retry_errors: "0",
          retry_scope: "replacement_jobs",
          retry_run_ids: "run-004-corrected",
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
          dashboard_id: "dashboard-1",
          dashboard_version: "7",
          dashboard_time_mode: "replay_run",
          dashboard_replay_run_id: "replay-1",
          dashboard_data_view: "all_revisions",
          dashboard_limit_mode: "observed",
          message: "Historical workflow job retry queued."
        },
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&panel=versions&activity_filter=open_comparison_reviews&activity_event=review-event-1&selected_placement=placement-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-handoff-count")

    assert ["source-event-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-primary-result-event-id")

    assert ["run-nonretryable"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-nonretryable-run-ids")

    assert ["failed-event-skipped"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-retry-skipped-event-ids")

    assert ["replay-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-dashboard-replay-run-id")

    assert ["all_revisions"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-dashboard-data-view")

    assert ["observed"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-dashboard-limit-mode")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
           |> LazyHTML.text()
           |> String.contains?("Historical workflow job retry queued.")

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

        label =
          node
          |> LazyHTML.attribute("data-workflow-latest-action-handoff-label")
          |> List.first()

        text =
          node
          |> LazyHTML.text()
          |> String.trim()

        href =
          node
          |> LazyHTML.attribute("data-workflow-latest-action-handoff-href")
          |> List.first()

        {event_id, role, label, text, review_href_query(href)}
      end)

    assert handoffs == [
             {"source-event-1", "target", "Selected event", "Selected event",
              %{
                "scope_kind" => "mission",
                "scope_id" => "mission-1",
                "panel" => "data_link",
                "selected_target" => "telemetry_backfill_lifecycle_event",
                "selected_id" => "source-event-1"
              }},
             {"retry-event-1", "result", "Result 1", "Result 1",
              %{
                "scope_kind" => "mission",
                "scope_id" => "mission-1",
                "panel" => "data_link",
                "selected_target" => "telemetry_backfill_lifecycle_event",
                "selected_id" => "retry-event-1"
              }}
           ]
  end

  test "latest_action renders no-eligible group policy outcome context" do
    html =
      render_component(&HistoricalWorkflowLatestActionComponents.latest_action/1,
        latest_action_outcome: %{
          class: "border-base-300/70 bg-base-100/60 text-base-content",
          action: "group_stage_transition",
          action_label: "Group stage",
          status: "no_op",
          status_label: "No-op",
          badge_class: "badge-ghost",
          reason: "no_eligible_group_items",
          stage: "approved",
          request_group_id: "request-group-1",
          job_id: nil,
          count: nil,
          retried: nil,
          retry_nonretryable: nil,
          retry_skipped: nil,
          retry_errors: nil,
          retry_scope: nil,
          retry_run_ids: nil,
          retry_disposition: %{},
          retry_error_run_ids: nil,
          retry_error_event_ids: nil,
          retry_error_items: nil,
          queued_jobs: nil,
          failed_jobs: nil,
          result_event_ids: nil,
          target_event_id: nil,
          target_run_id: nil,
          message:
            "No approve items are eligible in request group request-group-1. The workflow panel was refreshed with current eligibility counts."
        },
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["request-group-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-request-group-id")

    assert ["no_eligible_group_items"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-reason")

    text =
      document
      |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
      |> LazyHTML.text()

    assert text =~ "No approve items are eligible in request group request-group-1"
    assert text =~ "Group"
    assert text =~ "request-group-1"

    assert [] =
             document
             |> LazyHTML.query("[data-workflow-latest-action-handoff]")
             |> LazyHTML.attribute("data-workflow-latest-action-handoff")
  end

  test "latest_action renders no card when there is no outcome" do
    html =
      render_component(&HistoricalWorkflowLatestActionComponents.latest_action/1,
        latest_action_outcome: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("id")
  end

  defp review_href_query(href) do
    href
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end
end
