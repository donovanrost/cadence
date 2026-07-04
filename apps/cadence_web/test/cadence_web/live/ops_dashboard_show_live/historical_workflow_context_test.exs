defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowContextTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowContext

  test "build extracts workflow source, request, job, and group fields from atom-key rows" do
    context =
      HistoricalWorkflowContext.build(%{
        rows: [
          %{label: "Backfill lifecycle event", value: "event-1"},
          %{label: "Event type", value: "backfill_requested"},
          %{label: "Workflow", value: "backfill"},
          %{label: "Workflow stage", value: "requested"},
          %{label: "Workflow run", value: "run-1"},
          %{label: "Realm", value: "flight"},
          %{label: "Data source", value: "questdb-flight"},
          %{label: "Source binding", value: "binding-flight"},
          %{label: "Observable", value: "HK.counter"},
          %{label: "Point", value: "HK.counter"},
          %{label: "Source from", value: "2026-06-22T10:00:00Z"},
          %{label: "Source to", value: "2026-06-22T11:00:00Z"},
          %{label: "Dashboard context", value: "dashboard-1"},
          %{label: "Dashboard context version", value: "7"},
          %{label: "Dashboard context time mode", value: "replay_run"},
          %{label: "Dashboard context replay run", value: "replay-1"},
          %{label: "Dashboard context data view", value: "all_revisions"},
          %{label: "Dashboard context limit mode", value: "observed"},
          %{label: "Comparison review request", value: "review-request-1"},
          %{label: "Comparison review kind", value: "comparison_open_findings_review"},
          %{label: "Comparison review open count", value: "2"},
          %{label: "Comparison review placements", value: "placement-1,placement-2"},
          %{label: "Reason", value: "operator_request"},
          %{label: "Request mode", value: "bulk_points"},
          %{label: "Request group", value: "group-1"},
          %{label: "Request item", value: "2/3"},
          %{label: "Workflow job", value: "job-1"},
          %{label: "Workflow job status", value: "failed"},
          %{label: "Workflow retryable", value: "true"},
          %{label: "Request group progress", value: "1/3"},
          %{label: "Request group job progress", value: "queued 2, failed 1"},
          %{
            label: "Request group job items",
            value: "1:HK.counter run-1 queued job-1; 2:HK.voltage run-2 failed job-2"
          },
          %{label: "Request group retried items", value: "HK.voltage run-2 retried queued job-2"},
          %{
            label: "Request group corrected items",
            value: "HK.current run-3 corrected run-3-corrected requested job-3"
          },
          %{
            label: "Request group correction tasks",
            value: "HK.current run-3 replacement run-3-corrected stage requested next approve"
          },
          %{
            label: "Request group failed item events",
            value:
              "label=HK.current run=run-3 event=failed-event-3 recovery=correct_workflow_request retryable=false"
          },
          %{label: "Request group approve eligible", value: "2"},
          %{label: "Request group correction superseded", value: "1"},
          %{label: "Request group retryable failed", value: "1"}
        ]
      })

    assert %HistoricalWorkflowContext{} = context
    assert context.event_id == "event-1"
    assert context.workflow == "backfill"
    assert context.stage == "requested"
    assert context.run_id == "run-1"
    assert context.realm == "flight"
    assert context.data_source_id == "questdb-flight"
    assert context.source_binding_id == "binding-flight"
    assert context.observable_id == "HK.counter"
    assert context.point_id == "HK.counter"
    assert context.source_from == "2026-06-22T10:00:00Z"
    assert context.source_to == "2026-06-22T11:00:00Z"
    assert context.dashboard_id == "dashboard-1"
    assert context.dashboard_version == "7"
    assert context.dashboard_time_mode == "replay_run"
    assert context.dashboard_replay_run_id == "replay-1"
    assert context.dashboard_data_view == "all_revisions"
    assert context.dashboard_limit_mode == "observed"
    assert context.comparison_review_request_event_id == "review-request-1"
    assert context.comparison_review_request_kind == "comparison_open_findings_review"
    assert context.comparison_review_open_count == "2"
    assert context.comparison_review_open_placement_ids == "placement-1,placement-2"
    assert context.reason == "operator_request"
    assert context.request_mode == "bulk_points"
    assert context.request_group_id == "group-1"
    assert context.request_item == "2/3"
    assert context.request_item_count == 3
    assert context.job_id == "job-1"
    assert context.job_status == "failed"
    assert context.retryable == "true"
    assert context.request_group_progress == "1/3"
    assert context.request_group_job_progress == "queued 2, failed 1"

    assert context.request_group_job_items ==
             "1:HK.counter run-1 queued job-1; 2:HK.voltage run-2 failed job-2"

    assert context.request_group_retried_items == "HK.voltage run-2 retried queued job-2"

    assert context.request_group_corrected_items ==
             "HK.current run-3 corrected run-3-corrected requested job-3"

    assert context.request_group_correction_tasks ==
             "HK.current run-3 replacement run-3-corrected stage requested next approve"

    assert context.request_group_failed_item_events ==
             "label=HK.current run=run-3 event=failed-event-3 recovery=correct_workflow_request retryable=false"

    assert context.request_group_approve_eligible == "2"
    assert context.request_group_correction_superseded == "1"
    assert context.request_group_retryable_failed == "1"
  end

  test "build returns a map-compatible struct for downstream presenters" do
    context =
      HistoricalWorkflowContext.build(%{
        rows: [
          %{label: "Backfill lifecycle event", value: "event-1"},
          %{label: "Event type", value: "backfill_requested"},
          %{label: "Request item", value: "4/12"}
        ]
      })

    assert %HistoricalWorkflowContext{} = context
    assert Map.get(context, :event_id) == "event-1"
    assert Map.get(context, :workflow) == "backfill"
    assert Map.get(context, :stage) == "requested"
    assert Map.get(context, :request_item_count) == 12
  end

  test "build derives workflow and stage from backfill event type when rows omit them" do
    context =
      HistoricalWorkflowContext.build(%{
        rows: [
          %{label: "Event type", value: "backfill_failed"},
          %{label: "Backfill run", value: "run-1"}
        ]
      })

    assert %HistoricalWorkflowContext{} = context
    assert context.workflow == "backfill"
    assert context.stage == "failed"
    assert context.run_id == "run-1"
  end

  test "build derives workflow and stage from import event type" do
    context =
      HistoricalWorkflowContext.build(%{
        rows: [
          %{label: "Event type", value: "import_started"}
        ]
      })

    assert %HistoricalWorkflowContext{} = context
    assert context.workflow == "import"
    assert context.stage == "started"
  end

  test "build supports string-key rows and normalizes blank values" do
    context =
      HistoricalWorkflowContext.build(%{
        rows: [
          %{"label" => "Event type", "value" => "backfill_completed"},
          %{"label" => "Workflow", "value" => ""},
          %{"label" => "Workflow stage", "value" => ""},
          %{"label" => "Request item", "value" => "bad-value"},
          %{"label" => "Workflow failure code", "value" => ""}
        ]
      })

    assert %HistoricalWorkflowContext{} = context
    assert context.event_type == "backfill_completed"
    assert context.workflow == "backfill"
    assert context.stage == "completed"
    assert context.request_item_count == 0
    assert context.failure_code == nil
  end

  test "build returns an empty-compatible context when inspector is missing rows" do
    context = HistoricalWorkflowContext.build(%{})

    assert %HistoricalWorkflowContext{} = context
    assert context.event_id == nil
    assert context.workflow == nil
    assert context.stage == nil
    assert context.request_item_count == 0
  end
end
