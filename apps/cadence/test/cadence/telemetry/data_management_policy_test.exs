defmodule Cadence.Telemetry.DataManagementPolicyTest do
  use Cadence.UnitCase, async: true

  test "historical workflow action policy owns stage and recovery eligibility" do
    assert %{
             id: "stage_approved",
             kind: :stage,
             eligible?: true,
             disabled?: false,
             reason: "stage_transition_available"
           } =
             Cadence.telemetry_historical_data_workflow_stage_action_policy(
               %{"stage" => "requested"},
               "approved"
             )

    assert %{
             eligible?: false,
             disabled?: true,
             reason: "job_already_exists"
           } =
             Cadence.telemetry_historical_data_workflow_stage_action_policy(
               %{
                 stage: "approved",
                 job_id: "job-1",
                 job_status: "queued"
               },
               "started"
             )

    assert %{
             id: "group_stage_completed",
             kind: :group_stage,
             eligible?: true,
             disabled?: false,
             eligible_count: 2,
             reason: "eligible_group_items"
           } =
             Cadence.telemetry_historical_data_workflow_group_stage_action_policy(
               %{
                 request_group_id: "group-1",
                 request_group_complete_eligible: "2"
               },
               "completed"
             )

    actions =
      Cadence.telemetry_historical_data_workflow_action_policy(%{
        request_group_id: "group-1",
        request_group_retryable_failed: "0",
        event_id: "event-1",
        job_id: "job-1",
        job_status: "failed",
        retryable: "true",
        recovery_action: "correct_workflow_request"
      })

    assert actions.retry_job.reason == "correction_required"
    refute actions.retry_job.eligible?
    assert actions.retry_group_failed_jobs.reason == "no_retryable_group_failures"
    refute actions.retry_group_failed_jobs.eligible?
    assert actions.correction_request.reason == "correction_request_required"
    assert actions.correction_request.eligible?
  end

  test "historical workflow explanation summary owns lifecycle state semantics" do
    assert %{
             severity: :warning,
             state: "late_data_rejected",
             badge: "rejected",
             reason: "late_data_rejected"
           } =
             Cadence.telemetry_historical_data_workflow_explanation_summary(%{
               event_type: "late_data_rejected",
               stage: "completed"
             })

    assert %{
             severity: :error,
             state: "failed_correction_required",
             badge: "correction",
             reason: "failed_correction_required"
           } =
             Cadence.telemetry_historical_data_workflow_explanation_summary(%{
               "stage" => "failed",
               "retryable" => "false"
             })

    assert %{
             severity: :warning,
             state: "dispatch_failed",
             badge: "degraded",
             reason: "workflow_dispatch_failed"
           } =
             Cadence.telemetry_historical_data_workflow_explanation_summary(%{
               stage: "started",
               job_status: "failed"
             })

    assert %{
             severity: :warning,
             state: "correction",
             badge: "correction",
             reason: "correction_replacement_event"
           } =
             Cadence.telemetry_historical_data_workflow_explanation_summary(%{
               correction_source_event_id: "failed-event-1"
             })

    assert %{
             severity: :info,
             state: "backfill_requested",
             badge: "recorded",
             reason: "historical_data_workflow_recorded"
           } =
             Cadence.telemetry_historical_data_workflow_explanation_summary(%{
               event_type: "backfill_requested"
             })
  end

  test "late-data policy execution mode is product-owned" do
    assert :sample_execution =
             Cadence.telemetry_late_data_policy_execution_mode(%{
               point_id: "HK.counter",
               source_from: "2026-06-22T10:00:00Z",
               source_to: "2026-06-22T11:00:00Z"
             })

    assert :sample_execution =
             Cadence.telemetry_late_data_policy_execution_mode(%{
               point_id: "HK.counter",
               source_from: ~U[2026-06-22 10:00:00Z],
               source_to: ~U[2026-06-22 11:00:00Z]
             })

    assert :event_only =
             Cadence.telemetry_late_data_policy_execution_mode(%{
               observable_id: "HK.counter",
               source_from: "2026-06-22T10:00:00Z",
               source_to: "2026-06-22T11:00:00Z"
             })
  end

  test "late-data policy write opts lock projection semantics" do
    assert {:ok, accept_opts} =
             Cadence.telemetry_late_data_policy_write_opts("accept",
               metadata: %{"caller" => "dashboard"},
               validity_state: :advisory,
               record_current_values?: false
             )

    assert Keyword.fetch!(accept_opts, :late_data?)
    assert Keyword.fetch!(accept_opts, :backfill_lifecycle_event_type) == :late_data_accepted
    assert Keyword.fetch!(accept_opts, :validity_state) == :canonical
    assert Keyword.fetch!(accept_opts, :record_current_values?)
    assert Keyword.fetch!(accept_opts, :refresh_latest_value?)
    assert Keyword.fetch!(accept_opts, :authority) == :authoritative
    assert Keyword.fetch!(accept_opts, :metadata)["caller"] == "dashboard"

    assert Keyword.fetch!(accept_opts, :metadata)["late_data_projection_effect"] ==
             "canonical_history_and_current_projection"

    assert {:ok, reject_opts} =
             Cadence.telemetry_late_data_policy_write_opts(:reject,
               metadata: %{"caller" => "dashboard"},
               validity_state: :canonical,
               record_current_values?: true,
               refresh_latest_value?: true
             )

    assert Keyword.fetch!(reject_opts, :late_data?)
    assert Keyword.fetch!(reject_opts, :backfill_lifecycle_event_type) == :late_data_rejected
    assert Keyword.fetch!(reject_opts, :validity_state) == :advisory
    refute Keyword.fetch!(reject_opts, :record_current_values?)
    refute Keyword.fetch!(reject_opts, :refresh_latest_value?)
    assert Keyword.fetch!(reject_opts, :authority) == :advisory
    assert Keyword.fetch!(reject_opts, :metadata)["caller"] == "dashboard"

    assert Keyword.fetch!(reject_opts, :metadata)["late_data_projection_effect"] ==
             "advisory_history_only"

    assert {:error, {:unsupported_late_data_policy_decision, "quarantine"}} =
             Cadence.telemetry_late_data_policy_write_opts("quarantine")
  end
end
