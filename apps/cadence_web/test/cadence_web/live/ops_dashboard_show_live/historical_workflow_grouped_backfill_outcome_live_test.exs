defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupedBackfillOutcomeLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views =
      Process.get(:ops_dashboard_historical_workflow_grouped_backfill_outcome_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(
        :ops_dashboard_historical_workflow_grouped_backfill_outcome_views,
        MapSet.put(tracked_views, pid)
      )

      on_exit({:ops_dashboard_historical_workflow_grouped_backfill_outcome_view, pid}, fn ->
        stop_dashboard_view(view)
      end)
    end
  end

  defp stop_dashboard_view(view) do
    if Process.alive?(view.pid) do
      drain_dashboard_view(view)

      ref = Process.monitor(view.pid)
      {_proxy_ref, _topic, proxy_pid} = view.proxy
      ClientProxy.stop(proxy_pid, {:shutdown, :dashboard_test_cleanup})

      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 1_000
    end

    :ok
  end

  defp drain_dashboard_view(view) do
    render_async(view, 5_000)
    :ok
  catch
    :exit, _reason -> :ok
  end

  describe "historical workflow grouped backfill mixed outcomes" do
    test "summarizes completed and failed group items with recovery previews" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      request_group_backfill!(view)
      transition_group!(view, "approved", "operator_approved_bulk_backfill_from_dashboard")
      transition_group!(view, "started", "operator_started_bulk_backfill_from_dashboard")

      assert {:ok, voltage_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(
                 "dashboard-workflow-run-bulk-outcome-002"
               )

      assert {:ok, current_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(
                 "dashboard-workflow-run-bulk-outcome-003"
               )

      assert {:ok, _counter_completed} =
               record_backfill_event(org, mission, "completed", "HK.counter", 1,
                 run_id: "dashboard-workflow-run-bulk-outcome-001",
                 authority: :authoritative,
                 reason: "historical_data_job_completed"
               )

      assert {:ok, failed_voltage_job} =
               Cadence.Jobs.fail_worker_start(voltage_job.job_id, :source_window_unavailable)

      assert failed_voltage_job.status == :failed

      assert {:ok, failed_current_job} =
               Cadence.Jobs.fail_worker_start(current_job.job_id, :missing_point_id)

      assert failed_current_job.status == :failed

      assert {:ok, failed_event} =
               record_backfill_event(org, mission, "failed", "HK.voltage", 2,
                 run_id: "dashboard-workflow-run-bulk-outcome-002",
                 authority: :advisory,
                 reason: "historical_data_job_failed",
                 failure: %{
                   "code" => "source_window_unavailable",
                   "retryable" => true,
                   "recovery_action" => "retry_job"
                 }
               )

      assert {:ok, nonretryable_failed_event} =
               record_backfill_event(org, mission, "failed", "HK.current", 3,
                 run_id: "dashboard-workflow-run-bulk-outcome-003",
                 authority: :advisory,
                 reason: "historical_data_job_failed",
                 failure: %{
                   "code" => "missing_field:point_id",
                   "retryable" => false,
                   "retry_blockers" => ["missing point_id"],
                   "recovery_action" => "correct_workflow_request"
                 }
               )

      failed_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{failed_event.backfill_lifecycle_event_id}"

      {:ok, failed_view, _html} = live(conn, failed_path)
      render_dashboard_async(failed_view)

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="completed_with_failures"][data-historical-workflow-group-terminal="true"][data-historical-workflow-group-completed="1"][data-historical-workflow-group-failed="2"][data-historical-workflow-group-retryable-failed="1"][data-historical-workflow-group-nonretryable-failed="1"]),
               "HK.voltage"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-job-progress[data-historical-workflow-group-job-progress="queued 1, failed 2"][data-historical-workflow-group-job-progress-queued="1"][data-historical-workflow-group-job-progress-running="0"][data-historical-workflow-group-job-progress-completed="0"][data-historical-workflow-group-job-progress-failed="2"][data-historical-workflow-group-job-progress-missing="0"]),
               "dashboard-workflow-run-bulk-outcome-002"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-execution-audit[data-historical-workflow-group-execution-audit-request-group="dashboard-workflow-run-bulk-outcome"][data-historical-workflow-group-execution-audit-summary*="failed 2"][data-historical-workflow-group-execution-audit-summary*="job_progress queued 1, failed 2"])
             )

      assert has_element?(
               failed_view,
               ~s([data-historical-workflow-group-execution-step="failed"][data-historical-workflow-group-execution-count="2"]),
               "HK.current"
             )

      assert has_element?(
               failed_view,
               "#dashboard-historical-workflow-group-summary",
               "HK.current"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery[data-historical-workflow-group-recovery-id="dashboard-workflow-run-bulk-outcome"][data-historical-workflow-group-recovery-failed="2"][data-historical-workflow-group-recovery-retryable="1"][data-historical-workflow-group-recovery-correction="1"][data-historical-workflow-group-recovery-resolved="0"][data-historical-workflow-group-recovery-retried="0"][data-historical-workflow-group-recovery-correction-requested="0"]),
               "HK.voltage"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery[data-historical-workflow-group-recovery-next-action="retry_failed_items"][data-historical-workflow-group-recovery-unresolved="2"][data-historical-workflow-group-recovery-correction-task-count="0"])
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery-guidance[data-historical-workflow-group-recovery-guidance-next-action="retry_failed_items"][data-historical-workflow-group-recovery-guidance-retry-eligible="true"][data-historical-workflow-group-recovery-guidance-retry-reason="retryable_group_failures"]),
               "Retry 1 failed jobs in request group dashboard-workflow-run-bulk-outcome"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery-execution-plan[data-historical-workflow-group-recovery-execution-plan-request-group="dashboard-workflow-run-bulk-outcome"][data-historical-workflow-group-recovery-execution-plan-next-action="retry_failed_items"][data-historical-workflow-group-recovery-execution-plan-retry-eligible="true"][data-historical-workflow-group-recovery-execution-plan-retry-count="1"][data-historical-workflow-group-recovery-execution-plan-correction-count="1"][data-historical-workflow-group-recovery-execution-plan-unresolved="2"]),
               "Retry will requeue 1 failed item and select the retried lifecycle event."
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-retry-failed[data-workflow-action-eligible-count="1"][data-workflow-action-expected-effect="Retry will requeue 1 failed item and select the retried lifecycle event."])
             )

      assert has_element?(
               failed_view,
               "#dashboard-historical-workflow-group-recovery",
               "HK.current"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery[data-historical-workflow-group-recovery-failed-item-handoffs="2"])
             )

      assert has_element?(
               failed_view,
               ~s([data-historical-workflow-group-recovery-failed-item="#{failed_event.backfill_lifecycle_event_id}"][data-historical-workflow-group-recovery-failed-item-label="HK.voltage"][data-historical-workflow-group-recovery-failed-item-recovery="retry_job"][data-historical-workflow-group-recovery-failed-item-retryable="true"][data-historical-workflow-group-recovery-failed-item-href*="selected_target=telemetry_backfill_lifecycle_event"][data-historical-workflow-group-recovery-failed-item-href*="selected_id=#{failed_event.backfill_lifecycle_event_id}"]),
               "HK.voltage"
             )

      assert has_element?(
               failed_view,
               ~s([data-historical-workflow-group-recovery-failed-item="#{nonretryable_failed_event.backfill_lifecycle_event_id}"][data-historical-workflow-group-recovery-failed-item-label="HK.current"][data-historical-workflow-group-recovery-failed-item-recovery="correct_workflow_request"][data-historical-workflow-group-recovery-failed-item-retryable="false"][data-historical-workflow-group-recovery-failed-item-href*="selected_target=telemetry_backfill_lifecycle_event"][data-historical-workflow-group-recovery-failed-item-href*="selected_id=#{nonretryable_failed_event.backfill_lifecycle_event_id}"]),
               "HK.current"
             )
    end
  end

  defp request_group_backfill!(view) do
    view
    |> element("#dashboard-historical-workflow-request-button")
    |> render_click()

    view
    |> element("#dashboard-historical-workflow-request-form")
    |> render_submit(%{
      "historical_workflow_request" => %{
        "workflow" => "backfill",
        "run_id" => "dashboard-workflow-run-bulk-outcome",
        "realm" => "backfill",
        "data_source_id" => "managed_questdb_backfill",
        "source_binding_id" => "backfill_telemetry",
        "point_ids" => "HK.counter, HK.voltage\nHK.current",
        "source_from" => "2026-06-22T10:00:00Z",
        "source_to" => "2026-06-22T11:00:00Z",
        "reason" => "operator_requested_bulk_backfill_from_dashboard",
        "confirmed" => "confirmed"
      }
    })

    assert_patch(view)
  end

  defp transition_group!(view, stage, reason) do
    view
    |> element("#dashboard-historical-workflow-group-form")
    |> render_submit(%{
      "historical_workflow_group" => %{
        "workflow" => "backfill",
        "request_group_id" => "dashboard-workflow-run-bulk-outcome",
        "realm" => "backfill",
        "data_source_id" => "managed_questdb_backfill",
        "source_binding_id" => "backfill_telemetry",
        "stage" => stage,
        "reason" => reason,
        "confirmed" => "confirmed"
      }
    })

    assert_patch(view)
  end

  defp record_backfill_event(org, mission, stage, point_id, item_index, opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    failure = Keyword.get(opts, :failure)

    payload =
      %{
        "request_source" => "dashboard_direct_request",
        "request_mode" => "bulk_points",
        "request_group_id" => "dashboard-workflow-run-bulk-outcome",
        "request_item_index" => item_index,
        "request_item_count" => 3,
        "request_item_run_id" => run_id
      }
      |> maybe_put_failure(failure)

    Cadence.record_telemetry_historical_data_workflow_event(
      "backfill",
      stage,
      %{
        backfill_run_id: run_id,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        realm: :backfill,
        data_source_id: "managed_questdb_backfill",
        binding_id: "backfill_telemetry",
        observable_id: point_id,
        point_id: point_id,
        source_from: ~U[2026-06-22 10:00:00Z],
        source_to: ~U[2026-06-22 11:00:00Z],
        authority: Keyword.fetch!(opts, :authority),
        reason: Keyword.fetch!(opts, :reason),
        actor_id: "system",
        actor_kind: "system",
        payload: payload
      },
      dashboard_runtime_invalidation?: false
    )
  end

  defp maybe_put_failure(payload, nil), do: payload

  defp maybe_put_failure(payload, failure),
    do: Map.put(payload, "source", %{"failure" => failure})
end
