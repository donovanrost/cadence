defmodule CadenceWeb.OpsDashboardShowLive.DataManagementPresentationEventRowsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.DataManagementPresentation

  test "event rows summarize historical workflow stages" do
    assert %{badges: [backfill_badge]} =
             DataManagementPresentation.event_row(%{
               category: :telemetry_backfill,
               kind: :backfill_started
             })

    assert backfill_badge == %{
             kind: :historical_workflow,
             value: "backfill_started",
             label: "Backfill started",
             status: :attention,
             code: "backfill_started"
           }

    assert %{badges: [correction_badge]} =
             DataManagementPresentation.event_row(%{
               category: :telemetry_revision,
               kind: :mark_conflict
             })

    assert correction_badge == %{
             kind: :historical_workflow,
             value: "correction_conflict",
             label: "Correction conflict",
             status: :warning,
             code: "mark_conflict"
           }
  end

  test "event rows attach backfill lifecycle event links to workflow badges" do
    assert %{badges: [badge]} =
             DataManagementPresentation.event_row(%{
               category: :telemetry_backfill,
               kind: :backfill_started,
               source_record_id: "backfill-event-1"
             })

    assert %{
             kind: :historical_workflow,
             value: "backfill_started",
             data_link_target: :telemetry_backfill_lifecycle_event,
             data_link_id: "backfill-event-1"
           } = badge
  end

  test "event rows show degraded started workflow badges when dispatch job failed" do
    assert %{badges: [badge]} =
             DataManagementPresentation.event_row(%{
               category: :telemetry_backfill,
               kind: :backfill_started,
               source_record_id: "backfill-event-1",
               backfill_run_id: "backfill-run-1",
               workflow_job_id: "job-1",
               workflow_job_status: :failed,
               workflow_job_failure: "dispatcher unavailable"
             })

    assert badge == %{
             kind: :historical_workflow,
             value: "backfill_started_dispatch_degraded",
             label: "Backfill dispatch failed",
             status: :warning,
             code: "backfill_started_dispatch_degraded",
             data_link_target: :telemetry_backfill_lifecycle_event,
             data_link_id: "backfill-event-1",
             workflow_run_id: "backfill-run-1",
             workflow_job_id: "job-1",
             workflow_job_status: "failed",
             workflow_job_failure: "dispatcher unavailable",
             summary: "workflow job failed: dispatcher unavailable"
           }
  end

  test "event rows render structured workflow job failures as stable badge text" do
    assert %{badges: [badge]} =
             DataManagementPresentation.event_row(%{
               category: :telemetry_backfill,
               kind: :backfill_started,
               source_record_id: "backfill-event-1",
               backfill_run_id: "backfill-run-1",
               workflow_job_id: "job-1",
               workflow_job_status: :failed,
               workflow_job_failure: %{"tuple" => ["worker_start_failed", "source_window_failed"]}
             })

    assert %{
             workflow_job_failure: "worker_start_failed:source_window_failed",
             summary: "workflow job failed: worker_start_failed:source_window_failed"
           } = badge
  end

  test "event rows attach source watermark event links to freshness badges" do
    assert %{badges: [badge]} =
             DataManagementPresentation.event_row(%{
               category: :source_watermark,
               kind: :advanced,
               severity: :info,
               source_record_id: "watermark-event-1",
               realm: :flight,
               requested_data_view: :canonical,
               data_source_id: "flight-questdb",
               source_binding_id: "flight-telemetry",
               time_mode: :archive,
               time_axis: :occurred_at
             })

    assert %{
             kind: :source_freshness,
             value: "advanced",
             label: "Watermark advanced",
             status: :info,
             code: "advanced",
             data_link_target: :source_watermark_event,
             data_link_id: "watermark-event-1",
             realm: "flight",
             data_view: "canonical",
             data_source_id: "flight-questdb",
             source_binding_id: "flight-telemetry",
             time_mode: "archive",
             time_axis: "occurred_at"
           } = badge
  end

  test "late data event rows include execution projection summary" do
    assert %{badges: [badge]} =
             DataManagementPresentation.event_row(%{
               "category" => "telemetry_backfill",
               "kind" => "late_data_accepted",
               "source_record_id" => "late-data-event-1",
               "selected_sample_count" => 2,
               "projection_effect" => "canonical_history_and_current_projection",
               "write_validity_state" => "canonical",
               "record_current_values" => true,
               "refresh_latest_value" => true
             })

    assert badge == %{
             kind: :historical_workflow,
             value: "late_data_accepted",
             label: "Late data accepted",
             status: :info,
             code: "late_data_accepted",
             data_link_target: :telemetry_backfill_lifecycle_event,
             data_link_id: "late-data-event-1",
             selected_sample_count: 2,
             projection_effect: "canonical_history_and_current_projection",
             write_validity_state: "canonical",
             record_current_values: true,
             refresh_latest_value: true,
             summary:
               "2 selected samples; writes canonical history; refreshes current/latest; effect canonical_history_and_current_projection"
           }
  end

  test "late data event rows summarize event-only policy decisions as audit-only" do
    assert %{badges: [badge]} =
             DataManagementPresentation.event_row(%{
               "category" => "telemetry_backfill",
               "kind" => "late_data_accepted",
               "source_record_id" => "late-data-event-1",
               "execution_mode" => "event_only",
               "projection_effect" => "audit_event_only",
               "write_validity_state" => "canonical",
               "record_current_values" => false,
               "refresh_latest_value" => false
             })

    assert badge.summary ==
             "records canonical audit decision; does not refresh current/latest; effect audit_event_only"
  end

  test "event rows ignore unrelated event families" do
    assert DataManagementPresentation.event_row(%{
             category: :mission_timeline,
             kind: :operator_note
           }) ==
             nil
  end
end
