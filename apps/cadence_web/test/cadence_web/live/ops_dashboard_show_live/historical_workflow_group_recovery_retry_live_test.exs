defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupRecoveryRetryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp signed_in_org_and_mission do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    {conn, org, mission}
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
      Process.get(:ops_dashboard_historical_workflow_group_recovery_retry_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(
        :ops_dashboard_historical_workflow_group_recovery_retry_views,
        MapSet.put(tracked_views, pid)
      )

      on_exit({:ops_dashboard_historical_workflow_group_recovery_retry_view, pid}, fn ->
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

  describe "historical workflow group recovery retry surfaces" do
    test "group retry latest action exposes skipped item details from the product path" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, retryable_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_run_id: "dashboard-workflow-run-skip-001",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.voltage",
                   point_id: "HK.voltage",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-skip",
                     "request_item_index" => 1,
                     "request_item_count" => 2,
                     "request_item_run_id" => "dashboard-workflow-run-skip-001",
                     "source" => %{
                       "failure" => %{
                         "code" => "source_window_unavailable",
                         "retryable" => true,
                         "recovery_action" => "retry_job"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, skipped_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_run_id: "dashboard-workflow-run-skip-002",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.current",
                   point_id: "HK.current",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-skip",
                     "request_item_index" => 2,
                     "request_item_count" => 2,
                     "request_item_run_id" => "dashboard-workflow-run-skip-002",
                     "source" => %{
                       "failure" => %{
                         "code" => "source_window_unavailable",
                         "retryable" => true,
                         "recovery_action" => "retry_job"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, retryable_job} =
               Cadence.Jobs.enqueue(
                 :telemetry_historical_data_workflow,
                 mission.mission_id,
                 "dashboard-workflow-run-skip-001",
                 %{
                   "workflow" => "backfill",
                   "attrs" => %{"backfill_run_id" => "dashboard-workflow-run-skip-001"}
                 }
               )

      assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_job.job_id == retryable_job.job_id

      assert {:ok, failed_job} =
               Cadence.Jobs.fail_worker_start(retryable_job.job_id, :source_window_failed)

      assert failed_job.status == :failed

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{retryable_event.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-retry-failed[data-workflow-action-eligible-count="1"])
             )

      view
      |> element("#dashboard-historical-workflow-group-retry-failed")
      |> render_click()

      assert_patch(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="retry_group_failed_jobs"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-retried="1"][data-workflow-latest-action-retry-nonretryable="0"][data-workflow-latest-action-retry-skipped="1"][data-workflow-latest-action-retry-errors="0"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action-retry-skipped-run-ids="dashboard-workflow-run-skip-002"][data-workflow-latest-action-retry-skipped-event-ids="#{skipped_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-retry-skipped-items="run=dashboard-workflow-run-skip-002 event=#{skipped_event.backfill_lifecycle_event_id} reason=job_status_missing"])
             )

      assert has_element?(
               view,
               "#dashboard-historical-workflow-latest-action",
               "run=dashboard-workflow-run-skip-002 event=#{skipped_event.backfill_lifecycle_event_id} reason=job_status_missing"
             )

      assert {:ok, retried_job} = Cadence.fetch_background_job(retryable_job.job_id)
      assert retried_job.status == :queued
    end
  end
end
