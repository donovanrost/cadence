defmodule CadenceWeb.OpsDataOperationsLive.HistoricalWorkflowCommandsTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Telemetry.Storage
  alias CadenceWeb.OpsDataOperationsLive.HistoricalWorkflowCommands

  @opts [dashboard_runtime_invalidation?: false]
  @scope %{organization_id: "org-dashboard-command", user: %{id: "operator-command"}}
  @mission %{mission_id: "mission-dashboard-command"}

  describe "record_stage/4" do
    test "records a direct historical workflow stage event with dashboard actor context" do
      params = %{
        "workflow" => "backfill",
        "stage" => "requested",
        "run_id" => "dashboard-command-stage",
        "realm" => "backfill",
        "data_source_id" => "managed_questdb_backfill",
        "source_binding_id" => "backfill_telemetry",
        "observable_id" => "HK.counter",
        "point_id" => "HK.counter",
        "source_from" => "2026-06-22T10:00:00Z",
        "source_to" => "2026-06-22T11:00:00Z",
        "reason" => "operator_requested_backfill"
      }

      assert {:ok, event, {:ok, nil}} =
               HistoricalWorkflowCommands.record_stage(params, @scope, @mission, @opts)

      assert event.event_type == :backfill_requested
      assert event.backfill_run_id == "dashboard-command-stage"
      assert event.organization_id == "org-dashboard-command"
      assert event.mission_id == "mission-dashboard-command"
      assert event.actor_id == "operator-command"
      assert event.actor_kind == "operator"
      assert event.point_id == "HK.counter"
      assert event.reason == "operator_requested_backfill"

      assert [listed] =
               Storage.list_backfill_lifecycle_events("mission-dashboard-command",
                 organization_id: "org-dashboard-command",
                 backfill_run_id: "dashboard-command-stage"
               )

      assert listed.backfill_lifecycle_event_id == event.backfill_lifecycle_event_id
    end

    test "routes correction lifecycle stages through the correction transition API" do
      failed_job = failed_historical_workflow_job("dashboard-command-correction-source-run")

      assert {:ok, source_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_lifecycle_event_id: "dashboard-command-correction-source",
                   backfill_run_id: "dashboard-command-correction-source-run",
                   organization_id: "org-dashboard-command",
                   mission_id: "mission-dashboard-command",
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   payload: %{
                     "job_id" => failed_job.job_id,
                     "source" => %{
                       "failure" => %{
                         "retryable" => false,
                         "recovery_action" => "correct_workflow_request"
                       }
                     }
                   }
                 },
                 @opts
               )

      assert {:ok, correction_request} =
               Cadence.record_telemetry_historical_data_workflow_correction_request(
                 "backfill",
                 %{
                   backfill_run_id: "dashboard-command-correction-run",
                   organization_id: "org-dashboard-command",
                   mission_id: "mission-dashboard-command",
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   authority: :unknown,
                   reason: "operator_corrected_backfill"
                 },
                 %{"original_event_id" => source_event.backfill_lifecycle_event_id},
                 @opts
               )

      assert {:ok, approved, {:ok, nil}} =
               HistoricalWorkflowCommands.record_stage(
                 %{
                   "workflow" => "backfill",
                   "stage" => "approved",
                   "event_id" => correction_request.backfill_lifecycle_event_id,
                   "correction_source_event_id" => source_event.backfill_lifecycle_event_id,
                   "run_id" => correction_request.backfill_run_id,
                   "realm" => "backfill",
                   "data_source_id" => "managed_questdb_backfill",
                   "source_binding_id" => "backfill_telemetry",
                   "reason" => "operator_approved_corrected_backfill"
                 },
                 @scope,
                 @mission,
                 @opts
               )

      assert approved.event_type == :backfill_approved
      assert approved.backfill_run_id == correction_request.backfill_run_id
      assert approved.payload["correction_transition_source"] == "dashboard_correction_transition"
      assert approved.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id

      assert approved.payload["requested_event_id"] ==
               correction_request.backfill_lifecycle_event_id
    end

    test "routes selected lifecycle stages through guarded product transitions" do
      assert {:ok, requested} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "requested",
                 %{
                   backfill_lifecycle_event_id: "dashboard-command-stage-source",
                   backfill_run_id: "dashboard-command-stage-source-run",
                   organization_id: "org-dashboard-command",
                   mission_id: "mission-dashboard-command",
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   reason: "operator_requested_backfill"
                 },
                 @opts
               )

      assert {:error,
              {:historical_workflow_stage_transition_blocked, "dashboard-command-stage-source",
               "stage_transition_out_of_order"}} =
               HistoricalWorkflowCommands.record_stage(
                 %{
                   "workflow" => "backfill",
                   "stage" => "completed",
                   "event_id" => requested.backfill_lifecycle_event_id,
                   "run_id" => requested.backfill_run_id,
                   "realm" => "backfill",
                   "data_source_id" => "managed_questdb_backfill",
                   "source_binding_id" => "backfill_telemetry",
                   "reason" => "operator_completed_backfill"
                 },
                 @scope,
                 @mission,
                 @opts
               )

      assert {:ok, approved, {:ok, nil}} =
               HistoricalWorkflowCommands.record_stage(
                 %{
                   "workflow" => "backfill",
                   "stage" => "approved",
                   "event_id" => requested.backfill_lifecycle_event_id,
                   "run_id" => requested.backfill_run_id,
                   "realm" => "backfill",
                   "data_source_id" => "managed_questdb_backfill",
                   "source_binding_id" => "backfill_telemetry",
                   "reason" => "operator_approved_backfill"
                 },
                 @scope,
                 @mission,
                 @opts
               )

      assert approved.event_type == :backfill_approved
      assert approved.payload["stage_transition_source"] == "dashboard_stage_action"
      assert approved.payload["source_event_id"] == requested.backfill_lifecycle_event_id
    end
  end

  describe "record_request/4" do
    test "records grouped requests and returns params with requested stage" do
      params = %{
        "workflow" => "backfill",
        "run_id" => "dashboard-command-request",
        "realm" => "backfill",
        "data_source_id" => "managed_questdb_backfill",
        "source_binding_id" => "backfill_telemetry",
        "point_ids" => "HK.counter HK.voltage",
        "source_from" => "2026-06-22T10:00:00Z",
        "source_to" => "2026-06-22T11:00:00Z",
        "reason" => "operator_requested_bulk_backfill"
      }

      assert {:ok, events, returned_params} =
               HistoricalWorkflowCommands.record_request(params, @scope, @mission, @opts)

      assert returned_params["workflow"] == "backfill"
      assert returned_params["stage"] == "requested"

      assert Enum.map(events, & &1.backfill_run_id) == [
               "dashboard-command-request-001",
               "dashboard-command-request-002"
             ]

      assert Enum.map(events, & &1.point_id) == ["HK.counter", "HK.voltage"]
      assert Enum.all?(events, &(&1.actor_id == "operator-command"))
      assert Enum.all?(events, &(&1.payload["request_group_id"] == "dashboard-command-request"))
    end
  end

  describe "record_group_stage/4" do
    test "normalizes missing request group ids before calling the domain API" do
      assert {:error, {:missing_field, :request_group_id}} =
               HistoricalWorkflowCommands.record_group_stage(
                 %{"workflow" => "backfill", "stage" => "approved"},
                 @scope,
                 @mission,
                 @opts
               )
    end
  end

  describe "retry_group_failed_jobs/5" do
    test "retries retryable group failures through the product API" do
      retryable_job = failed_historical_workflow_job("dashboard-command-group-retry-001")
      nonretryable_job = failed_historical_workflow_job("dashboard-command-group-retry-002")

      assert {:ok, retryable_event} =
               record_group_failed_event(
                 "dashboard-command-group-retry-event-1",
                 "dashboard-command-group-retry-001",
                 1,
                 retryable: true,
                 job_id: retryable_job.job_id
               )

      assert {:ok, nonretryable_event} =
               record_group_failed_event(
                 "dashboard-command-group-retry-event-2",
                 "dashboard-command-group-retry-002",
                 2,
                 retryable: false,
                 job_id: nonretryable_job.job_id
               )

      assert {:ok, summary} =
               HistoricalWorkflowCommands.retry_group_failed_jobs(
                 " dashboard-command-group-retry ",
                 @scope,
                 @mission,
                 @opts
               )

      assert summary.retried == 1
      assert summary.nonretryable == 1
      assert summary.skipped == 0
      assert summary.failed == 0
      assert summary.retry_error_items == []

      assert summary.nonretryable_items == [
               %{
                 event_id: nonretryable_event.backfill_lifecycle_event_id,
                 reason: "nonretryable_failure",
                 run_id: "dashboard-command-group-retry-002"
               }
             ]

      assert [retry_event] = summary.events
      assert retry_event.event_type == :backfill_retried
      assert retry_event.actor_id == "operator-command"
      assert retry_event.payload["retry_action"] == "retry_job"

      assert retry_event.payload["retry_source_event_id"] ==
               retryable_event.backfill_lifecycle_event_id

      assert retry_event.payload["retry_job_id"] == retryable_job.job_id
      assert retry_event.payload["retry_job_status"] == "queued"
      assert retry_event.payload["request_group_id"] == "dashboard-command-group-retry"
      assert retry_event.payload["request_item_index"] == 1
      assert retry_event.payload["request_item_count"] == 2

      assert {:ok, retried_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(
                 "dashboard-command-group-retry-001"
               )

      assert retried_job.status == :queued

      assert {:ok, still_failed_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(
                 "dashboard-command-group-retry-002"
               )

      assert still_failed_job.status == :failed
    end

    test "normalizes blank request group ids before calling the domain API" do
      assert {:error, {:missing_field, :request_group_id}} =
               HistoricalWorkflowCommands.retry_group_failed_jobs(" ", @scope, @mission, @opts)
    end
  end

  describe "inspect_missing_replacement_job/5" do
    test "normalizes blank ids before calling the domain API" do
      assert {:error, {:missing_field, :request_group_id}} =
               HistoricalWorkflowCommands.inspect_missing_replacement_job(
                 " ",
                 "run-1-corrected",
                 @scope,
                 @mission,
                 @opts
               )

      assert {:error, {:missing_field, :replacement_run_id}} =
               HistoricalWorkflowCommands.inspect_missing_replacement_job(
                 "group-1",
                 " ",
                 @scope,
                 @mission,
                 @opts
               )
    end
  end

  describe "retry_job/5" do
    test "normalizes blank retry ids before calling the domain API" do
      assert {:error, {:missing_field, :job_id}} =
               HistoricalWorkflowCommands.retry_job(" ", "event-1", @scope, @mission, @opts)

      assert {:error, {:missing_field, :event_id}} =
               HistoricalWorkflowCommands.retry_job("job-1", " ", @scope, @mission, @opts)
    end
  end

  describe "recover_job/6" do
    test "normalizes recovery ids before calling the domain API" do
      for action <- [
            :retry_job,
            :inspect_stale_replacement_job,
            :requeue_stale_replacement_job
          ] do
        assert {:error, {:missing_field, :job_id}} =
                 HistoricalWorkflowCommands.recover_job(
                   action,
                   " ",
                   "event-1",
                   @scope,
                   @mission,
                   @opts
                 )

        assert {:error, {:missing_field, :event_id}} =
                 HistoricalWorkflowCommands.recover_job(
                   action,
                   "job-1",
                   " ",
                   @scope,
                   @mission,
                   @opts
                 )
      end
    end

    test "rejects unsupported recovery actions before calling the domain API" do
      assert {:error, {:unsupported_job_recovery_action, :cancel_job}} =
               HistoricalWorkflowCommands.recover_job(
                 :cancel_job,
                 "job-1",
                 "event-1",
                 @scope,
                 @mission,
                 @opts
               )
    end
  end

  defp failed_historical_workflow_job(run_id) do
    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-dashboard-command",
               run_id,
               %{"workflow" => "backfill", "attrs" => %{"backfill_run_id" => run_id}}
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id

    assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :source_failed)
    assert failed_job.status == :failed

    failed_job
  end

  defp record_group_failed_event(event_id, run_id, item_index, opts) do
    failure =
      %{"retryable" => Keyword.fetch!(opts, :retryable)}
      |> maybe_put("recovery_action", Keyword.get(opts, :recovery_action))

    payload =
      %{
        "request_group_id" => "dashboard-command-group-retry",
        "request_item_index" => item_index,
        "request_item_count" => 2,
        "source" => %{"failure" => failure}
      }
      |> maybe_put("job_id", Keyword.get(opts, :job_id))

    Cadence.record_telemetry_historical_data_workflow_event(
      "backfill",
      "failed",
      %{
        backfill_lifecycle_event_id: event_id,
        backfill_run_id: run_id,
        organization_id: "org-dashboard-command",
        mission_id: "mission-dashboard-command",
        realm: :backfill,
        data_source_id: "managed_questdb_backfill",
        binding_id: "backfill_telemetry",
        observable_id: "HK.group_failed#{item_index}",
        point_id: "HK.group_failed#{item_index}",
        source_from: ~U[2026-06-22 10:00:00Z],
        source_to: ~U[2026-06-22 11:00:00Z],
        authority: :advisory,
        reason: "historical_data_job_failed",
        payload: payload
      },
      @opts
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
