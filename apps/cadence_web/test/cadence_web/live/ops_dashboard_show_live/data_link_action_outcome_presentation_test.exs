defmodule CadenceWeb.OpsDashboardShowLive.DataLinkActionOutcomePresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewActionOutcome
  alias CadenceWeb.OpsDashboardShowLive.DataLinkActionOutcomePresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionOutcome
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyActionOutcome
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionActionOutcome

  test "normalizes historical workflow outcomes" do
    presentation =
      DataLinkActionOutcomePresentation.build(
        HistoricalWorkflowActionOutcome.new(
          action: :stage_transition,
          status: :ok,
          kind: :info,
          reason: :stage_recorded,
          stage: "approved",
          request_group_id: "group-1",
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
          result_event_ids: "event-1,event-2",
          target_event_id: "event-1",
          target_run_id: "run-1",
          message: "Workflow stage recorded."
        )
      )

    assert presentation.action == "stage_transition"
    assert presentation.status == "ok"
    assert presentation.kind == "info"
    assert presentation.reason == "stage_recorded"
    assert presentation.message == "Workflow stage recorded."

    assert presentation.metadata == %{
             "count" => "2",
             "failed_jobs" => "0",
             "job_id" => "job-1",
             "queued_jobs" => "2",
             "request_group_id" => "group-1",
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
             "retry_skipped_run_ids" => "run-skipped",
             "stage" => "approved",
             "result_event_ids" => "event-1,event-2",
             "target_event_id" => "event-1",
             "target_run_id" => "run-1"
           }

    assert Jason.decode!(presentation.metadata_json) == presentation.metadata
  end

  test "normalizes late-data policy outcomes" do
    presentation =
      DataLinkActionOutcomePresentation.for_action(
        LateDataPolicyActionOutcome.new(
          status: :blocked,
          kind: :error,
          reason: "confirmation_required",
          decision: "accept",
          execution_mode: "sample_execution",
          dashboard_limit_mode: "recomputed",
          result_event_id: "late-event-1",
          target_event_id: "late-event-1",
          target_run_id: "run-1",
          message: "Confirm the late-data policy decision before applying it."
        ),
        :late_data_policy
      )

    assert presentation.action == "late_data_policy"
    assert presentation.status == "blocked"

    assert presentation.metadata == %{
             "decision" => "accept",
             "execution_mode" => "sample_execution",
             "dashboard_limit_mode" => "recomputed",
             "result_event_id" => "late-event-1",
             "target_event_id" => "late-event-1",
             "target_run_id" => "run-1"
           }
  end

  test "normalizes revision decision outcomes" do
    presentation =
      DataLinkActionOutcomePresentation.for_action(
        RevisionDecisionActionOutcome.new(
          status: :error,
          kind: :error,
          reason: "revision_decision_failed",
          decision: "mark_conflict",
          dashboard_time_mode: "replay_run",
          dashboard_replay_run_id: "replay-1",
          dashboard_data_view: "all_revisions",
          dashboard_limit_mode: "compare",
          result_event_id: "decision-event-1",
          target_event_id: "decision-event-1",
          target_observation_identity_id: "identity-1",
          message: "Failed to apply telemetry revision decision."
        ),
        "revision_decision"
      )

    assert presentation.action == "revision_decision"
    assert presentation.status == "error"

    assert presentation.metadata == %{
             "decision" => "mark_conflict",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-1",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "compare",
             "result_event_id" => "decision-event-1",
             "target_event_id" => "decision-event-1",
             "target_observation_identity_id" => "identity-1"
           }
  end

  test "normalizes comparison review bulk decision outcomes" do
    presentation =
      DataLinkActionOutcomePresentation.for_action(
        ComparisonReviewActionOutcome.new(
          status: :degraded,
          kind: :warning,
          reason: "comparison_review_bulk_decision_partially_applied",
          decision: "mark_conflict",
          decision_reason: "dashboard_comparison_review_mark_conflict",
          source_request_event_id: "review-request-1",
          workflow_id: "review-request-1",
          requested: 2,
          applied: 1,
          failed: 1,
          result_event_ids: "decision-event-1",
          target_event_id: "review-request-1",
          message: "Comparison review decisions applied to 1 findings; 1 failed."
        ),
        :comparison_review_bulk_decision
      )

    assert presentation.action == "comparison_review_bulk_decision"
    assert presentation.status == "degraded"
    assert presentation.kind == "warning"
    assert presentation.reason == "comparison_review_bulk_decision_partially_applied"
    assert presentation.message == "Comparison review decisions applied to 1 findings; 1 failed."

    assert presentation.metadata == %{
             "decision" => "mark_conflict",
             "decision_reason" => "dashboard_comparison_review_mark_conflict",
             "source_request_event_id" => "review-request-1",
             "workflow_id" => "review-request-1",
             "requested" => "2",
             "applied" => "1",
             "failed" => "1",
             "result_event_ids" => "decision-event-1",
             "target_event_id" => "review-request-1"
           }
  end

  test "builds stable attributes from normalized outcome fields" do
    presentation =
      DataLinkActionOutcomePresentation.for_action(
        LateDataPolicyActionOutcome.new(
          status: :ok,
          kind: :info,
          reason: "late_data_policy_applied",
          decision: "accept",
          execution_mode: "sample_execution",
          dashboard_time_mode: "replay_run",
          dashboard_replay_run_id: "replay-1",
          dashboard_data_view: "all_revisions",
          dashboard_limit_mode: "compare",
          result_event_id: "late-event-1",
          target_event_id: "late-event-1",
          target_run_id: "run-1"
        ),
        :late_data_policy
      )

    assert DataLinkActionOutcomePresentation.stable_attrs(
             presentation,
             "data-data-link-action-outcome",
             action_suffix: "action"
           ) == %{
             "data-data-link-action-outcome-action" => "late_data_policy",
             "data-data-link-action-outcome-dashboard-data-view" => "all_revisions",
             "data-data-link-action-outcome-dashboard-limit-mode" => "compare",
             "data-data-link-action-outcome-dashboard-replay-run-id" => "replay-1",
             "data-data-link-action-outcome-dashboard-time-mode" => "replay_run",
             "data-data-link-action-outcome-decision" => "accept",
             "data-data-link-action-outcome-execution-mode" => "sample_execution",
             "data-data-link-action-outcome-kind" => "info",
             "data-data-link-action-outcome-metadata" => presentation.metadata_json,
             "data-data-link-action-outcome-reason" => "late_data_policy_applied",
             "data-data-link-action-outcome-result-event-id" => "late-event-1",
             "data-data-link-action-outcome-status" => "ok",
             "data-data-link-action-outcome-target-event-id" => "late-event-1",
             "data-data-link-action-outcome-target-run-id" => "run-1"
           }
  end

  test "builds stable attributes with component-specific metadata aliases" do
    presentation =
      DataLinkActionOutcomePresentation.for_action(
        ComparisonReviewActionOutcome.new(
          status: :ok,
          kind: :info,
          reason: "comparison_review_bulk_decision_applied",
          source_request_event_id: "request-1",
          workflow_id: "request-1",
          requested: 2,
          applied: 2,
          failed: 0,
          scope_kind: "transport",
          scope_ids: "transport-alpha,transport-beta",
          contact_ids: "contact-alpha,contact-beta",
          resource_ids: "transport-alpha",
          transport_ids: "transport-alpha",
          source_endpoint_ids: "endpoint-alpha",
          ground_station_ids: "dss-14",
          scope_link_ids: "link-alpha",
          result_event_ids: "decision-1,decision-2",
          target_event_id: "request-1"
        ),
        :comparison_review_bulk_decision
      )

    attrs =
      DataLinkActionOutcomePresentation.stable_attrs(
        presentation,
        "data-dashboard-comparison-review-action",
        aliases: %{"source_request_event_id" => "source-request-id"}
      )

    assert attrs["data-dashboard-comparison-review-action"] ==
             "comparison_review_bulk_decision"

    assert attrs["data-dashboard-comparison-review-action-source-request-id"] == "request-1"
    assert attrs["data-dashboard-comparison-review-action-workflow-id"] == "request-1"
    assert attrs["data-dashboard-comparison-review-action-requested"] == "2"
    assert attrs["data-dashboard-comparison-review-action-applied"] == "2"
    assert attrs["data-dashboard-comparison-review-action-failed"] == "0"
    assert attrs["data-dashboard-comparison-review-action-scope-kind"] == "transport"

    assert attrs["data-dashboard-comparison-review-action-scope-ids"] ==
             "transport-alpha,transport-beta"

    assert attrs["data-dashboard-comparison-review-action-contact-ids"] ==
             "contact-alpha,contact-beta"

    assert attrs["data-dashboard-comparison-review-action-resource-ids"] == "transport-alpha"
    assert attrs["data-dashboard-comparison-review-action-transport-ids"] == "transport-alpha"

    assert attrs["data-dashboard-comparison-review-action-source-endpoint-ids"] ==
             "endpoint-alpha"

    assert attrs["data-dashboard-comparison-review-action-ground-station-ids"] == "dss-14"
    assert attrs["data-dashboard-comparison-review-action-scope-link-ids"] == "link-alpha"

    assert attrs["data-dashboard-comparison-review-action-result-event-ids"] ==
             "decision-1,decision-2"

    assert attrs["data-dashboard-comparison-review-action-target-event-id"] == "request-1"
    refute Map.has_key?(attrs, "data-dashboard-comparison-review-action-source-request-event-id")
  end

  test "filters by expected action" do
    refute DataLinkActionOutcomePresentation.for_action(
             RevisionDecisionActionOutcome.new(decision: "mark_conflict"),
             :late_data_policy
           )
  end
end
