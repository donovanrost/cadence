defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelWorkflowDispatchTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionOutcome

  test "data_link_panel presents degraded workflow dispatch with retry controls" do
    html =
      render_component(&DataLinkInspectorPanelComponents.data_link_panel/1,
        inspector: %{
          status: :resolved,
          status_text: "resolved",
          title: "Telemetry backfill lifecycle event",
          target: :telemetry_backfill_lifecycle_event,
          target_text: "telemetry backfill lifecycle event",
          target_id: "backfill-event-1",
          link_id: "telemetry_backfill_lifecycle_event:backfill-event-1:events-request-1",
          link_label: "Telemetry backfill lifecycle event",
          source: :frame,
          source_text: "frame",
          message: nil,
          rows: [
            %{label: "Backfill lifecycle event", value: "backfill-event-1"},
            %{label: "Backfill run", value: "backfill-run-1"},
            %{label: "Event type", value: "backfill_started"},
            %{label: "Workflow", value: "backfill"},
            %{label: "Workflow stage", value: "started"},
            %{label: "Workflow run", value: "backfill-run-1"},
            %{label: "Dashboard context", value: "dashboard-1"},
            %{label: "Dashboard context version", value: "7"},
            %{label: "Dashboard context time mode", value: "replay_run"},
            %{label: "Dashboard context replay run", value: "replay-1"},
            %{label: "Dashboard context data view", value: "all_revisions"},
            %{label: "Dashboard context limit mode", value: "observed"},
            %{label: "Occurred", value: "2026-06-22T12:21:00Z"},
            %{label: "Realm", value: "flight"},
            %{label: "Data source", value: "questdb-flight"},
            %{label: "Source binding", value: "binding-flight"},
            %{label: "Point", value: "HK.counter"},
            %{label: "Source from", value: "2026-06-22T11:00:00Z"},
            %{label: "Source to", value: "2026-06-22T12:00:00Z"},
            %{label: "Reason", value: "operator_started_backfill"},
            %{label: "Workflow job", value: "job-1"},
            %{label: "Workflow job status", value: "failed"},
            %{label: "Workflow job attempts", value: "1"},
            %{label: "Workflow job failure", value: "dispatcher unavailable"},
            %{label: "Workflow retryable", value: "true"}
          ],
          context_rows: [
            %{label: "Data realm", value: "flight"},
            %{label: "Data source", value: "events-questdb"},
            %{label: "Source binding", value: "events-binding"},
            %{label: "Time mode", value: "archive"},
            %{label: "Logical source", value: "events"}
          ],
          related_links: [],
          actions: []
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link&selected_target=telemetry_backfill_lifecycle_event",
        data_link_action_outcome:
          HistoricalWorkflowActionOutcome.new(
            action: :retry_job,
            status: :ok,
            kind: :info,
            reason: :retry_job_queued,
            job_id: "job-1",
            count: 2,
            retried: 1,
            retry_nonretryable: 1,
            retry_skipped: 3,
            retry_errors: 0,
            retry_scope: "replacement_jobs",
            retry_run_ids: "run-004-corrected,run-005-corrected",
            retry_nonretryable_run_ids: "run-nonretryable",
            retry_nonretryable_event_ids: "failed-event-nonretryable",
            retry_nonretryable_items:
              "run=run-nonretryable event=failed-event-nonretryable action=correct_workflow_request reason=correction_required",
            retry_skipped_run_ids: "run-skipped",
            retry_skipped_event_ids: "failed-event-skipped",
            retry_skipped_items:
              "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed",
            retry_error_run_ids: "run-004-corrected",
            retry_error_event_ids: "failed-event-4",
            retry_error_items:
              "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down",
            queued_jobs: 2,
            failed_jobs: 0,
            result_event_ids: "retry-event-1",
            target_event_id: "backfill-event-1",
            target_run_id: "backfill-run-1",
            message: "Historical workflow job retry queued."
          )
      )

    document = LazyHTML.from_fragment(html)

    [metadata_json] =
      document
      |> LazyHTML.query("#dashboard-data-link-action-outcome")
      |> LazyHTML.attribute("data-data-link-action-outcome-metadata")

    metadata =
      metadata_json
      |> Jason.decode!()
      |> Map.take([
        "job_id",
        "count",
        "retried",
        "retry_nonretryable",
        "retry_skipped",
        "retry_errors",
        "retry_scope",
        "retry_run_ids",
        "retry_nonretryable_run_ids",
        "retry_nonretryable_event_ids",
        "retry_nonretryable_items",
        "retry_skipped_run_ids",
        "retry_skipped_event_ids",
        "retry_skipped_items",
        "retry_error_run_ids",
        "retry_error_event_ids",
        "retry_error_items",
        "queued_jobs",
        "failed_jobs"
      ])

    assert metadata == %{
             "count" => "2",
             "failed_jobs" => "0",
             "job_id" => "job-1",
             "queued_jobs" => "2",
             "retried" => "1",
             "retry_error_event_ids" => "failed-event-4",
             "retry_error_items" =>
               "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down",
             "retry_error_run_ids" => "run-004-corrected",
             "retry_errors" => "0",
             "retry_nonretryable" => "1",
             "retry_nonretryable_event_ids" => "failed-event-nonretryable",
             "retry_nonretryable_items" =>
               "run=run-nonretryable event=failed-event-nonretryable action=correct_workflow_request reason=correction_required",
             "retry_nonretryable_run_ids" => "run-nonretryable",
             "retry_run_ids" => "run-004-corrected,run-005-corrected",
             "retry_scope" => "replacement_jobs",
             "retry_skipped" => "3",
             "retry_skipped_event_ids" => "failed-event-skipped",
             "retry_skipped_items" =>
               "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed",
             "retry_skipped_run_ids" => "run-skipped"
           }

    assert ["replacement_jobs"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-action-outcome")
             |> LazyHTML.attribute("data-workflow-action-retry-scope")

    assert ["info"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-action-outcome")
             |> LazyHTML.attribute("data-workflow-action-kind")

    assert ["run-nonretryable"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-action-outcome")
             |> LazyHTML.attribute("data-workflow-action-retry-nonretryable-run-ids")

    assert ["failed-event-skipped"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-action-outcome")
             |> LazyHTML.attribute("data-workflow-action-retry-skipped-event-ids")

    assert ["run-004-corrected"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-action-outcome")
             |> LazyHTML.attribute("data-workflow-action-retry-error-run-ids")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-action-outcome")
             |> LazyHTML.attribute("data-workflow-action-queued-jobs")

    assert ["retry-event-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-action-outcome")
             |> LazyHTML.attribute("data-workflow-action-result-event-ids")

    assert ["dispatch_failed"] =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation")
             |> LazyHTML.attribute("data-workflow-explanation-state")

    assert ["warning"] =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation")
             |> LazyHTML.attribute("data-workflow-explanation-severity")

    assert "This workflow was started, but the backing job failed before completion." =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation-summary")
             |> selected_text()

    assert ["job-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-status")
             |> LazyHTML.attribute("data-historical-workflow-job-id")

    assert ["failed"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-status")
             |> LazyHTML.attribute("data-historical-workflow-job-status")

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

    assert ["backfill-event-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-retry-job")
             |> LazyHTML.attribute("phx-value-event-id")

    assert ["dashboard-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-dashboard-id")
             |> LazyHTML.attribute("value")

    assert ["replay-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-dashboard-replay-run-id")
             |> LazyHTML.attribute("value")

    assert ["observed"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-dashboard-limit-mode")
             |> LazyHTML.attribute("value")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-retry-job")
             |> LazyHTML.attribute("data-workflow-action-eligible")

    assert [
             "job job-1; status failed; retryable true; recovery unknown"
           ] =
             document
             |> LazyHTML.query(~s([data-workflow-action-explanation-id="correction_request"]))
             |> LazyHTML.attribute("data-workflow-action-explanation-state")

    assert document
           |> LazyHTML.query(~s([data-workflow-action-explanation-id="correction_request"]))
           |> LazyHTML.text()
           |> String.contains?("job job-1; status failed; retryable true; recovery unknown")

    assert ["retry_job"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-action")

    assert ["retry-event-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-result-event-ids")

    assert ["backfill-event-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-target-event-id")

    assert ["backfill-run-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-target-run-id")

    assert ["job-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-job-id")

    assert ["retry-event-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-result-event-ids")

    assert ["backfill-event-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-target-event-id")

    assert ["backfill-run-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-target-run-id")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
           |> LazyHTML.text()
           |> String.contains?("retry-event-1")

    assert %{
             "job_id" => "job-1",
             "result_event_ids" => "retry-event-1",
             "target_event_id" => "backfill-event-1",
             "target_run_id" => "backfill-run-1"
           } =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-metadata")
             |> List.first()
             |> Jason.decode!()
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
