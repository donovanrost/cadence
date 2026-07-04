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
