defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowExplanationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowExplanation

  test "build presents completed workflow explanations" do
    explanation =
      HistoricalWorkflowExplanation.build(%{
        event_id: "event-1",
        event_type: "backfill_completed",
        workflow: "backfill",
        stage: "completed",
        run_id: "run-1",
        realm: "flight",
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        point_id: "HK.counter",
        source_from: "2026-06-22T10:00:00Z",
        source_to: "2026-06-22T11:00:00Z"
      })

    assert explanation.summary == %{
             severity: :success,
             state: "completed",
             badge: "completed",
             reason: "workflow_completed",
             summary: "This workflow completed for the inspected source window."
           }

    assert explanation.container_class == "border-success/40 bg-success/10"
    assert explanation.badge_class == "badge-success"

    assert %{label: "Source", value: "flight / questdb-flight / binding-flight / HK.counter"} in explanation.rows

    assert %{label: "Window", value: "2026-06-22T10:00:00Z -> 2026-06-22T11:00:00Z"} in explanation.rows
  end

  test "build explains failed workflows that require correction" do
    explanation =
      HistoricalWorkflowExplanation.build(%{
        stage: "failed",
        retryable: "false",
        recovery_action: "correct_workflow_request",
        failure_code: "missing_field:point_id",
        request_group_id: "group-1",
        request_group_state: "failed",
        request_group_progress: "0/1",
        job_id: "job-1",
        job_status: "failed"
      })

    assert explanation.summary.state == "failed_correction_required"
    assert explanation.summary.severity == :error
    assert explanation.summary.badge == "correction"
    assert explanation.summary.reason == "failed_correction_required"
    assert explanation.container_class == "border-error/40 bg-error/10"
    assert explanation.badge_class == "badge-error"

    assert %{label: "Recovery", value: "correct_workflow_request"} in explanation.rows
    assert %{label: "Failure", value: "missing_field:point_id"} in explanation.rows
    assert %{label: "Group", value: "group-1 failed"} in explanation.rows
    assert %{label: "Progress", value: "0/1"} in explanation.rows
    assert %{label: "Job", value: "job-1 failed"} in explanation.rows
  end

  test "build presents retryable failed workflows separately" do
    explanation = HistoricalWorkflowExplanation.build(%{stage: "failed", retryable: "true"})

    assert explanation.summary.state == "failed_retryable"
    assert explanation.summary.badge == "failed"
    assert explanation.summary.reason == "failed_retryable"
    assert explanation.summary.summary =~ "retry eligibility"
  end

  test "build presents started workflows with failed dispatch jobs as degraded" do
    explanation =
      HistoricalWorkflowExplanation.build(%{
        stage: "started",
        job_id: "job-1",
        job_status: "failed",
        job_failure: "dispatcher unavailable"
      })

    assert explanation.summary.state == "dispatch_failed"
    assert explanation.summary.severity == :warning
    assert explanation.summary.badge == "degraded"
    assert explanation.summary.reason == "workflow_dispatch_failed"
    assert explanation.summary.summary =~ "backing job failed"
    assert explanation.container_class == "border-warning/40 bg-warning/10"
    assert explanation.badge_class == "badge-warning"
    assert %{label: "Job", value: "job-1 failed"} in explanation.rows
  end

  test "build presents late-data policy events" do
    accepted =
      HistoricalWorkflowExplanation.build(%{
        event_type: "late_data_accepted",
        late_data_source_event_id: "source-event-1",
        late_data_policy_decision: "accept",
        late_data_selected_samples: "2",
        late_data_projection_effect: "canonical_history_and_current_projection",
        late_data_write_validity: "canonical"
      })

    assert accepted.summary.state == "late_data_accepted"
    assert accepted.summary.severity == :success
    assert accepted.summary.badge == "accepted"
    assert accepted.summary.reason == "late_data_accepted"

    assert %{label: "Policy source", value: "source-event-1"} in accepted.rows
    assert %{label: "Policy", value: "accept"} in accepted.rows
    assert %{label: "Selected samples", value: "2"} in accepted.rows

    assert %{label: "Projection", value: "canonical_history_and_current_projection"} in accepted.rows

    assert %{label: "Write validity", value: "canonical"} in accepted.rows

    rejected = HistoricalWorkflowExplanation.build(%{event_type: "late_data_rejected"})

    assert rejected.summary.state == "late_data_rejected"
    assert rejected.summary.severity == :warning
    assert rejected.summary.badge == "rejected"
    assert rejected.summary.reason == "late_data_rejected"
  end

  test "build presents retry and correction relationships" do
    correction =
      HistoricalWorkflowExplanation.build(%{
        correction_source_event_id: "source-event-1"
      })

    assert correction.summary.state == "correction"
    assert correction.summary.severity == :warning
    assert correction.summary.badge == "correction"
    assert correction.summary.reason == "correction_replacement_event"
    assert %{label: "Corrects", value: "source-event-1"} in correction.rows

    retry = HistoricalWorkflowExplanation.build(%{retry_source_event_id: "retry-event-1"})

    assert retry.summary.state == "retry"
    assert retry.summary.severity == :info
    assert retry.summary.badge == "retry"
    assert retry.summary.reason == "retry_replacement_event"
    assert %{label: "Retry source", value: "retry-event-1"} in retry.rows
  end

  test "build uses default summary and omits blank row values" do
    explanation =
      HistoricalWorkflowExplanation.build(%{
        event_type: "backfill_requested",
        workflow: "",
        run_id: nil,
        source_from: "2026-06-22T10:00:00Z",
        source_to: ""
      })

    assert explanation.summary.state == "backfill_requested"
    assert explanation.summary.severity == :info
    assert explanation.summary.badge == "recorded"
    assert explanation.summary.reason == "historical_data_workflow_recorded"
    assert explanation.container_class == "border-info/40 bg-info/10"
    assert explanation.badge_class == "badge-info"

    assert %{label: "Event", value: "backfill_requested"} in explanation.rows
    assert %{label: "Window", value: "2026-06-22T10:00:00Z -> "} in explanation.rows
    refute Enum.any?(explanation.rows, &(&1.label == "Run"))
  end
end
