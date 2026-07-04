defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowHandoffTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflowCorrectionRequestHandoff,
    HistoricalWorkflowGroupStageHandoff,
    HistoricalWorkflowHandoff,
    HistoricalWorkflowJobRecoveryHandoff,
    HistoricalWorkflowRequestHandoff,
    HistoricalWorkflowRetryGroupFailedJobsHandoff,
    HistoricalWorkflowRetryJobHandoff,
    HistoricalWorkflowStageHandoff
  }

  @scope %{organization_id: "org-handoff", user: %{id: "operator-handoff"}}
  @mission %{mission_id: "mission-handoff"}

  describe "stage/3" do
    test "builds an individual stage handoff" do
      params = %{
        "workflow" => " backfill ",
        "stage" => " started ",
        "run_id" => "stage-handoff",
        "realm" => "backfill",
        "data_source_id" => "managed_questdb",
        "source_binding_id" => "telemetry-history",
        "observable_id" => "HK.counter",
        "point_id" => "HK.counter"
      }

      assert {:ok, handoff} = HistoricalWorkflowHandoff.stage(params, @scope, @mission)

      assert %HistoricalWorkflowStageHandoff{kind: :stage} = handoff
      assert handoff.workflow == "backfill"
      assert handoff.stage == "started"
      assert handoff.selection_params["workflow"] == "backfill"
      assert handoff.selection_params["stage"] == "started"
      assert handoff.attrs.backfill_run_id == "stage-handoff"
      assert handoff.attrs.point_id == "HK.counter"
      assert handoff.attrs.authority == :unknown
      assert handoff.attrs.reason == "dashboard_backfill_started"
    end
  end

  describe "group_stage/3" do
    test "builds a group transition handoff with a normalized request group" do
      params = %{
        "workflow" => "backfill",
        "stage" => "approved",
        "request_group_id" => " group-handoff ",
        "realm" => "backfill",
        "data_source_id" => "managed_questdb",
        "source_binding_id" => "telemetry-history",
        "reason" => "operator_approved_group"
      }

      assert {:ok, handoff} = HistoricalWorkflowHandoff.group_stage(params, @scope, @mission)

      assert %HistoricalWorkflowGroupStageHandoff{kind: :group_stage} = handoff
      assert handoff.workflow == "backfill"
      assert handoff.stage == "approved"
      assert handoff.request_group_id == "group-handoff"
      assert handoff.selection_params["request_group_id"] == "group-handoff"
      assert handoff.group_transition_scope == nil
      assert handoff.group_correction_tasks == nil
      assert handoff.replacement_run_ids == []
      assert handoff.attrs.authority == :authoritative
      assert handoff.attrs.reason == "operator_approved_group"
    end

    test "builds replacement-correction group transition scope and run ids" do
      params = %{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "stage" => "started",
          "request_group_id" => " group-handoff ",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb",
          "source_binding_id" => "telemetry-history",
          "group_transition_scope" => " replacement_corrections ",
          "group_correction_tasks" =>
            "approve replacement corrected-run-1 stage requested; start replacement corrected-run-2 stage approved; repeat replacement corrected-run-1 stage requested"
        }
      }

      assert {:ok, handoff} = HistoricalWorkflowHandoff.group_stage(params, @scope, @mission)

      assert %HistoricalWorkflowGroupStageHandoff{kind: :group_stage} = handoff
      assert handoff.group_transition_scope == "replacement_corrections"

      assert handoff.group_correction_tasks ==
               "approve replacement corrected-run-1 stage requested; start replacement corrected-run-2 stage approved; repeat replacement corrected-run-1 stage requested"

      assert handoff.replacement_run_ids == ["corrected-run-1", "corrected-run-2"]
      assert handoff.selection_params["group_transition_scope"] == "replacement_corrections"

      assert handoff.selection_params["group_correction_tasks"] ==
               handoff.group_correction_tasks

      assert handoff.attrs.payload["group_transition_scope"] == "replacement_corrections"
    end

    test "rejects missing request group ids before the product API" do
      assert {:error, {:missing_field, :request_group_id}} =
               HistoricalWorkflowHandoff.group_stage(
                 %{"workflow" => "backfill", "stage" => "approved", "request_group_id" => " "},
                 @scope,
                 @mission
               )
    end
  end

  describe "request/3" do
    test "builds a dashboard request handoff with normalized workflow and stage" do
      params = %{
        "workflow" => " ",
        "run_id" => "request-handoff",
        "realm" => "backfill",
        "data_source_id" => "managed_questdb",
        "source_binding_id" => "telemetry-history",
        "point_ids" => "HK.counter, HK.voltage\nHK.counter",
        "source_from" => "2026-06-27T01:00:00Z",
        "source_to" => "2026-06-27T02:00:00Z",
        "dashboard_id" => "dashboard-power",
        "dashboard_version" => "9",
        "dashboard_time_mode" => "archive",
        "dashboard_replay_run_id" => "replay-9",
        "dashboard_data_view" => "as_recorded",
        "dashboard_limit_mode" => "observed"
      }

      assert {:ok, handoff} = HistoricalWorkflowHandoff.request(params, @scope, @mission)

      assert %HistoricalWorkflowRequestHandoff{kind: :request} = handoff
      assert handoff.workflow == "backfill"
      assert handoff.stage == "requested"
      assert handoff.point_ids == ["HK.counter", "HK.voltage"]
      assert handoff.selection_params["workflow"] == "backfill"
      assert handoff.selection_params["stage"] == "requested"

      assert handoff.attrs.backfill_run_id == "request-handoff"
      assert handoff.attrs.organization_id == "org-handoff"
      assert handoff.attrs.mission_id == "mission-handoff"
      assert handoff.attrs.actor_id == "operator-handoff"
      assert handoff.attrs.authority == :unknown
      assert handoff.attrs.reason == "dashboard_backfill_requested"

      assert handoff.attrs.payload == %{
               "dashboard_context" => %{
                 "dashboard_id" => "dashboard-power",
                 "dashboard_version" => "9",
                 "dashboard_time_mode" => "archive",
                 "dashboard_replay_run_id" => "replay-9",
                 "dashboard_data_view" => "as_recorded",
                 "dashboard_limit_mode" => "observed"
               }
             }
    end

    test "preserves explicit import workflow and single-point fallback" do
      params = %{
        "workflow" => "import",
        "run_id" => "request-import",
        "realm" => "import",
        "observable_id" => "HK.temperature",
        "point_id" => "HK.temperature"
      }

      assert {:ok, handoff} = HistoricalWorkflowHandoff.request(params, @scope, @mission)

      assert %HistoricalWorkflowRequestHandoff{kind: :request} = handoff
      assert handoff.workflow == "import"
      assert handoff.point_ids == ["HK.temperature"]
      assert handoff.selection_params["workflow"] == "import"
      assert handoff.selection_params["stage"] == "requested"
      assert handoff.attrs.import_run_id == "request-import"
      assert handoff.attrs.reason == "dashboard_import_requested"
    end
  end

  describe "correction_request/3" do
    test "builds a correction request handoff without rewriting correction refs" do
      params = %{
        "workflow" => "backfill",
        "run_id" => "corrected-handoff",
        "realm" => "backfill",
        "point_id" => "HK.counter",
        "original_run_id" => "original-run",
        "original_event_id" => "failed-event",
        "original_job_id" => "failed-job"
      }

      assert {:ok, handoff} =
               HistoricalWorkflowHandoff.correction_request(params, @scope, @mission)

      assert %HistoricalWorkflowCorrectionRequestHandoff{kind: :correction_request} = handoff
      assert handoff.workflow == "backfill"
      assert handoff.stage == "requested"
      assert handoff.correction_params == params
      assert handoff.selection_params["workflow"] == "backfill"
      refute Map.has_key?(handoff.selection_params, "stage")
      refute Map.has_key?(handoff.attrs, :stage)
      assert handoff.attrs.backfill_run_id == "corrected-handoff"
      assert handoff.attrs.reason == "dashboard_backfill"
    end
  end

  describe "retry_job/4" do
    test "builds a retry job handoff with actor attrs" do
      assert {:ok, handoff} =
               HistoricalWorkflowHandoff.retry_job(" job-1 ", " event-1 ", @scope, @mission)

      assert %HistoricalWorkflowRetryJobHandoff{kind: :retry_job} = handoff
      assert handoff.job_id == "job-1"
      assert handoff.event_id == "event-1"

      assert handoff.actor_attrs == %{
               organization_id: "org-handoff",
               mission_id: "mission-handoff",
               actor_id: "operator-handoff",
               actor_kind: "operator"
             }
    end

    test "rejects missing retry ids before the product API" do
      assert {:error, {:missing_field, :job_id}} =
               HistoricalWorkflowHandoff.retry_job(" ", "event-1", @scope, @mission)

      assert {:error, {:missing_field, :event_id}} =
               HistoricalWorkflowHandoff.retry_job("job-1", " ", @scope, @mission)
    end
  end

  describe "job_recovery/5" do
    test "declares every supported job recovery action" do
      assert HistoricalWorkflowHandoff.supported_job_recovery_actions() == [
               :retry_job,
               :inspect_stale_replacement_job,
               :requeue_stale_replacement_job
             ]
    end

    test "builds a job recovery handoff with actor attrs" do
      for action <- HistoricalWorkflowHandoff.supported_job_recovery_actions() do
        assert {:ok, handoff} =
                 HistoricalWorkflowHandoff.job_recovery(
                   action,
                   " job-1 ",
                   " event-1 ",
                   @scope,
                   @mission
                 )

        assert %HistoricalWorkflowJobRecoveryHandoff{kind: :job_recovery} = handoff
        assert handoff.action == action
        assert handoff.job_id == "job-1"
        assert handoff.event_id == "event-1"

        assert handoff.actor_attrs == %{
                 organization_id: "org-handoff",
                 mission_id: "mission-handoff",
                 actor_id: "operator-handoff",
                 actor_kind: "operator"
               }
      end
    end

    test "rejects missing ids and unsupported actions before the product API" do
      assert {:error, {:missing_field, :job_id}} =
               HistoricalWorkflowHandoff.job_recovery(
                 :retry_job,
                 " ",
                 "event-1",
                 @scope,
                 @mission
               )

      assert {:error, {:missing_field, :event_id}} =
               HistoricalWorkflowHandoff.job_recovery(
                 :retry_job,
                 "job-1",
                 " ",
                 @scope,
                 @mission
               )

      assert {:error, {:unsupported_job_recovery_action, :cancel_job}} =
               HistoricalWorkflowHandoff.job_recovery(
                 :cancel_job,
                 "job-1",
                 "event-1",
                 @scope,
                 @mission
               )
    end
  end

  describe "retry_group_failed_jobs/3" do
    test "builds a group retry handoff with actor attrs" do
      assert {:ok, handoff} =
               HistoricalWorkflowHandoff.retry_group_failed_jobs(
                 " group-1 ",
                 @scope,
                 @mission
               )

      assert %HistoricalWorkflowRetryGroupFailedJobsHandoff{kind: :retry_group_failed_jobs} =
               handoff

      assert handoff.request_group_id == "group-1"
      assert handoff.actor_attrs.actor_id == "operator-handoff"
    end

    test "rejects missing request group ids before the product API" do
      assert {:error, {:missing_field, :request_group_id}} =
               HistoricalWorkflowHandoff.retry_group_failed_jobs(" ", @scope, @mission)
    end
  end
end
