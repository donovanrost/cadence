defmodule CadenceWeb.OpsDataOperationsLive.HistoricalWorkflowCommandsEarlyReturnTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDataOperationsLive.HistoricalWorkflowCommands

  @opts [dashboard_runtime_invalidation?: false]
  @scope %{organization_id: "org-dashboard-command", user: %{id: "operator-command"}}
  @mission %{mission_id: "mission-dashboard-command"}

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
end
