defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobStatusComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobStatusComponents

  test "job_status renders guidance, review links, and retry action metadata" do
    html =
      render_component(&HistoricalWorkflowJobStatusComponents.job_status/1,
        workflow_context: workflow_context(),
        workflow_controls: workflow_controls(),
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&panel=data_link"
      )

    document = LazyHTML.from_fragment(html)

    assert ["job-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-status")
             |> LazyHTML.attribute("data-historical-workflow-job-id")

    assert ["retry_job"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-status")
             |> LazyHTML.attribute("data-historical-workflow-job-next-action")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
             |> LazyHTML.attribute("data-historical-workflow-job-guidance-retry-eligible")

    assert ["correction_not_required"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
             |> LazyHTML.attribute("data-historical-workflow-job-guidance-correction-reason")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
           |> LazyHTML.text()
           |> String.contains?("Retry job job-1.")

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

    assert ["placement-1", "placement-2"] =
             document
             |> LazyHTML.query("[data-historical-workflow-job-review-origin-placement]")
             |> LazyHTML.attribute("data-historical-workflow-job-review-origin-placement")

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

  test "job_status renders no job card when job status is disabled" do
    html =
      render_component(&HistoricalWorkflowJobStatusComponents.job_status/1,
        workflow_context: workflow_context(),
        workflow_controls: %{workflow_controls() | job_status: false},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-status")
             |> LazyHTML.attribute("id")
  end

  test "job_status renders stale active-job guidance metadata" do
    html =
      render_component(&HistoricalWorkflowJobStatusComponents.job_status/1,
        workflow_context:
          Map.merge(workflow_context(), %{
            job_status: "running",
            run_id: "run-stale-replacement",
            job_started_at: "2026-06-22T10:01:00Z",
            stale_replacement_job_age_seconds: "1200",
            stale_replacement_stale_after_seconds: "900"
          }),
        workflow_controls: %{
          workflow_controls()
          | job_retryable: false,
            job_retry_action: %{eligible?: false},
            correction_request_action: %{eligible?: false}
        },
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["inspect_stale_job"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-status")
             |> LazyHTML.attribute("data-historical-workflow-job-next-action")

    assert ["stale"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
             |> LazyHTML.attribute("data-historical-workflow-job-guidance-active-state")

    assert ["2026-06-22T10:01:00Z"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
             |> LazyHTML.attribute("data-historical-workflow-job-guidance-started-at")

    assert ["1200"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
             |> LazyHTML.attribute("data-historical-workflow-job-guidance-age-seconds")

    assert ["900"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
             |> LazyHTML.attribute("data-historical-workflow-job-guidance-stale-after-seconds")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
           |> LazyHTML.text()
           |> String.contains?("crossed the stale threshold")

    assert ["job_status"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-stale-job-actions")
             |> LazyHTML.attribute("data-workflow-action-scope")

    assert ["job-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-stale-job-actions")
             |> LazyHTML.attribute("data-workflow-action-job-id")

    assert ["source-event-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-stale-job-actions")
             |> LazyHTML.attribute("data-workflow-action-event-id")

    assert ["inspect_stale_historical_workflow_replacement_job"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-stale-job-inspect")
             |> LazyHTML.attribute("phx-click")

    assert ["inspect_stale_replacement_job"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-stale-job-inspect")
             |> LazyHTML.attribute("data-workflow-action-id")

    assert ["run-stale-replacement"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-stale-job-inspect")
             |> LazyHTML.attribute("phx-value-replacement-run-id")

    assert ["run-stale-replacement"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-stale-job-inspect")
             |> LazyHTML.attribute("data-workflow-action-replacement-run")

    assert ["requeue_stale_historical_workflow_replacement_job"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-stale-job-requeue")
             |> LazyHTML.attribute("phx-click")

    assert ["requeue_stale_replacement_job"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-stale-job-requeue")
             |> LazyHTML.attribute("data-workflow-action-id")

    assert ["run-stale-replacement"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-stale-job-requeue")
             |> LazyHTML.attribute("phx-value-replacement-run-id")

    assert ["run-stale-replacement"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-stale-job-requeue")
             |> LazyHTML.attribute("data-workflow-action-replacement-run")
  end

  test "job_status renders missing replacement job inspection action metadata" do
    html =
      render_component(&HistoricalWorkflowJobStatusComponents.job_status/1,
        workflow_context:
          Map.merge(workflow_context(), %{
            job_status: "missing",
            request_group_id: "group-1",
            missing_replacement_run_id: "run-1-corrected",
            missing_replacement_expected_job_type: "telemetry_historical_data_workflow"
          }),
        workflow_controls: %{
          workflow_controls()
          | job_retryable: false,
            job_retry_action: %{eligible?: false},
            correction_request_action: %{eligible?: false}
        },
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["inspect_missing_job"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-status")
             |> LazyHTML.attribute("data-historical-workflow-job-next-action")

    assert ["missing"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
             |> LazyHTML.attribute("data-historical-workflow-job-guidance-active-state")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-job-guidance")
           |> LazyHTML.text()
           |> String.contains?("replacement workflow job is missing")

    assert ["job_status"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-missing-job-actions")
             |> LazyHTML.attribute("data-workflow-action-scope")

    assert ["group-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-missing-job-actions")
             |> LazyHTML.attribute("data-workflow-action-request-group-id")

    assert ["run-1-corrected"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-missing-job-actions")
             |> LazyHTML.attribute("data-workflow-action-replacement-run")

    assert ["telemetry_historical_data_workflow"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-missing-job-actions")
             |> LazyHTML.attribute("data-workflow-action-expected-job-type")

    assert ["inspect_missing_historical_workflow_replacement_job"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-missing-job-inspect")
             |> LazyHTML.attribute("phx-click")

    assert ["group-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-missing-job-inspect")
             |> LazyHTML.attribute("phx-value-request-group-id")

    assert ["run-1-corrected"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-missing-job-inspect")
             |> LazyHTML.attribute("phx-value-replacement-run-id")

    assert ["inspect_missing_replacement_job"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-missing-job-inspect")
             |> LazyHTML.attribute("data-workflow-action-id")
  end

  defp workflow_context do
    %{
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
    }
  end

  defp workflow_controls do
    %{
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
    }
  end

  defp review_href_query(href) do
    href
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end
end
