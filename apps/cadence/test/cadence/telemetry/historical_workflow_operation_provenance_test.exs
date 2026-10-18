defmodule Cadence.Telemetry.HistoricalWorkflowOperationProvenanceTest do
  use Cadence.DataCase, async: false

  import Cadence.Telemetry.DataManagementFixtures

  alias Cadence.Telemetry.DataManagement, as: Workflows
  alias Cadence.Telemetry.DataManagement.WorkflowCorrections
  alias Cadence.Telemetry.Storage

  @opts [dashboard_runtime_invalidation?: false]

  test "request, group approval and start retain their own operation and actual job identity" do
    assert {:ok, requested} =
             Workflows.record_historical_data_workflow_request(
               :backfill,
               attrs("group", "request-operation"),
               ["one", "two"],
               @opts
             )

    assert Enum.all?(requested, &(&1.payload["host_operation_id"] == "request-operation"))

    assert {:ok, approved, [ok: nil, ok: nil]} =
             Workflows.record_historical_data_workflow_group_transition(
               :backfill,
               :approved,
               "group",
               attrs("unused", "approval-operation"),
               @opts
             )

    assert Enum.all?(approved, &(&1.payload["host_operation_id"] == "approval-operation"))

    assert {:ok, started, jobs} =
             Workflows.record_historical_data_workflow_group_transition(
               :backfill,
               :started,
               "group",
               attrs("unused", "start-operation"),
               @opts
             )

    for {event, {:ok, job}} <- Enum.zip(started, jobs) do
      assert event.payload["host_operation_id"] == "start-operation"
      assert job.run_id == event.backfill_run_id
      assert job.payload["attrs"]["payload"]["host_operation_id"] == "start-operation"
      assert persisted(event).payload["host_operation_id"] == "start-operation"
    end
  end

  test "a later compatibility transition does not inherit the previous host operation" do
    assert {:ok, [requested]} =
             Workflows.record_historical_data_workflow_request(
               :import,
               attrs("single", "request-operation"),
               ["one"],
               @opts
             )

    assert {:ok, approved} =
             Workflows.record_historical_data_workflow_stage_transition(
               :import,
               :approved,
               requested.backfill_lifecycle_event_id,
               attrs("unused", "approval-operation"),
               @opts
             )

    assert approved.payload["host_operation_id"] == "approval-operation"

    assert {:ok, rejected} =
             Workflows.record_historical_data_workflow_stage_transition(
               :import,
               :rejected,
               approved.backfill_lifecycle_event_id,
               Map.delete(attrs("unused", "unused"), :payload),
               @opts
             )

    refute Map.has_key?(rejected.payload, "host_operation_id")
    assert rejected.payload["source_event_id"] == approved.backfill_lifecycle_event_id
  end

  test "retry audit carries the current operation and the actual retried job" do
    job = failed_historical_workflow_job("retry-run")

    assert {:ok, failed} =
             record_group_failed_event("retry-failed", "retry-run", 1,
               retryable: true,
               job_id: job.job_id
             )

    assert {:ok, retried, event} =
             Workflows.retry_historical_data_workflow_job(
               job.job_id,
               failed.backfill_lifecycle_event_id,
               attrs("unused", "retry-operation"),
               @opts
             )

    assert retried.job_id == job.job_id
    assert event.payload["host_operation_id"] == "retry-operation"
    assert event.payload["retry_job_id"] == job.job_id
    assert persisted(event).payload["host_operation_id"] == "retry-operation"
  end

  test "correction lineage survives while each correction decision gets its own operation" do
    job = failed_historical_workflow_job("failed-run")

    assert {:ok, failed} =
             record_group_failed_event("correction-failed", "failed-run", 1,
               retryable: false,
               job_id: job.job_id,
               recovery_action: "correct_workflow_request"
             )

    assert {:ok, correction} =
             Workflows.record_historical_data_workflow_correction_request(
               :backfill,
               attrs("corrected-run", "correction-operation"),
               %{"original_event_id" => failed.backfill_lifecycle_event_id},
               @opts
             )

    assert correction.payload["host_operation_id"] == "correction-operation"
    assert correction.payload["corrects_event_id"] == failed.backfill_lifecycle_event_id

    assert {:ok, approved} =
             Workflows.record_historical_data_workflow_correction_transition(
               :backfill,
               :approved,
               correction.backfill_lifecycle_event_id,
               attrs("unused", "correction-approval"),
               @opts
             )

    assert approved.payload["host_operation_id"] == "correction-approval"
    assert approved.payload["corrects_event_id"] == failed.backfill_lifecycle_event_id
    assert persisted(approved).payload["host_operation_id"] == "correction-approval"
  end

  test "foreign jobs cannot be retried or used as correction evidence" do
    job = failed_historical_workflow_job("foreign-run")

    Repo.update_all(from(j in Cadence.Jobs.BackgroundJobRow, where: j.job_id == ^job.job_id),
      set: [mission_id: "another-mission"]
    )

    assert {:ok, failed} =
             record_group_failed_event("foreign-failed", job.run_id, 1,
               retryable: true,
               job_id: job.job_id
             )

    assert {:error, :historical_workflow_job_scope_mismatch} =
             Workflows.retry_historical_data_workflow_job(
               job.job_id,
               failed.backfill_lifecycle_event_id,
               attrs("unused", "retry"),
               @opts
             )

    assert {:ok, %{retried: 0, skipped: 1, skipped_items: [item]}} =
             Workflows.retry_historical_data_workflow_group_failed_jobs(
               "backfill-run-group-failed",
               attrs("unused", "retry"),
               @opts
             )

    refute Map.has_key?(item, :job_id)
    assert {:ok, current} = Cadence.Jobs.fetch_job(job.job_id)
    assert current.status == :failed

    assert {:ok, correction_source} =
             record_group_failed_event("foreign-correction", job.run_id, 1,
               retryable: false,
               job_id: job.job_id,
               recovery_action: "correct_workflow_request"
             )

    assert {:error, :historical_workflow_job_scope_mismatch} =
             WorkflowCorrections.review_request(:backfill, attrs("replacement", "correction"), %{
               "original_event_id" => correction_source.backfill_lifecycle_event_id
             })
  end

  test "a job identity mismatch blocks both individual and group retry before mutation" do
    job = failed_historical_workflow_job("mismatch-run")

    assert {:ok, failed} =
             record_group_failed_event("mismatch-failed", job.run_id, 1,
               retryable: true,
               job_id: "different-job"
             )

    assert {:error, :historical_workflow_job_identity_mismatch} =
             Workflows.retry_historical_data_workflow_job(
               job.job_id,
               failed.backfill_lifecycle_event_id,
               attrs("unused", "retry"),
               @opts
             )

    assert {:ok, %{retried: 0, failed: 1, events: []}} =
             Workflows.retry_historical_data_workflow_group_failed_jobs(
               "backfill-run-group-failed",
               attrs("unused", "retry"),
               @opts
             )

    assert {:ok, current} = Cadence.Jobs.fetch_job(job.job_id)
    assert current.status == :failed
  end

  test "completed correction lineage is blocked consistently by group review and execution" do
    job = failed_historical_workflow_job("closed-run")

    assert {:ok, failed} =
             record_group_failed_event("closed-failed", job.run_id, 1,
               retryable: false,
               job_id: job.job_id,
               recovery_action: "correct_workflow_request"
             )

    context = attrs("replacement", "correction")

    assert {:ok, correction} =
             Workflows.record_historical_data_workflow_correction_request(
               :backfill,
               context,
               %{"original_event_id" => failed.backfill_lifecycle_event_id},
               @opts
             )

    assert :ok = WorkflowCorrections.review_transition(:backfill, :approved, correction, context)

    assert {:ok, _} =
             Workflows.record_historical_data_workflow_event(
               :backfill,
               :completed,
               Map.put(context, :payload, %{
                 "corrects_event_id" => failed.backfill_lifecycle_event_id
               }),
               @opts
             )

    assert {:ok, %{sources: [], blocked: [blocked]}} =
             Workflows.historical_data_workflow_group_transition_review(
               :backfill,
               :approved,
               "backfill-run-group-failed",
               context
             )

    assert blocked == correction.backfill_lifecycle_event_id

    assert {:error, {:no_eligible_items, :approved}} =
             Workflows.record_historical_data_workflow_group_transition(
               :backfill,
               :approved,
               "backfill-run-group-failed",
               context,
               @opts
             )
  end

  defp attrs(run, operation) do
    %{
      organization_id: "org-product",
      mission_id: "mission-product",
      backfill_run_id: run,
      import_run_id: run,
      realm: :backfill,
      data_source_id: "source",
      binding_id: "binding",
      actor_id: "operator",
      actor_kind: "operator",
      payload: %{"host_operation_id" => operation}
    }
  end

  defp persisted(event) do
    Storage.fetch_backfill_lifecycle_event(event.backfill_lifecycle_event_id,
      organization_id: "org-product",
      mission_id: "mission-product"
    )
  end
end
