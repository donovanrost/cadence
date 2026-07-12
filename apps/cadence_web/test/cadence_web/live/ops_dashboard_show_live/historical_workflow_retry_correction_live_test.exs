defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRetryCorrectionLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias Cadence.Telemetry.Storage
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
      Process.get(:ops_dashboard_historical_workflow_retry_correction_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(
        :ops_dashboard_historical_workflow_retry_correction_views,
        MapSet.put(tracked_views, pid)
      )

      on_exit({:ops_dashboard_historical_workflow_retry_correction_view, pid}, fn ->
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

  describe "historical workflow retry surfaces" do
    test "retries failed historical workflow jobs from the lifecycle inspector" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_run_id: "dashboard-workflow-run-retry",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{"failure" => "source window unavailable"}
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, job} =
               Cadence.Jobs.enqueue(
                 :telemetry_historical_data_workflow,
                 mission.mission_id,
                 "dashboard-workflow-run-retry",
                 %{
                   "workflow" => "backfill",
                   "attrs" => %{"backfill_run_id" => "dashboard-workflow-run-retry"}
                 }
               )

      assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_job.job_id == job.job_id
      assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :source_window_failed)
      assert failed_job.status == :failed

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{event.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-status[data-historical-workflow-job-id="#{job.job_id}"][data-historical-workflow-job-status="failed"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-guidance[data-historical-workflow-job-guidance-next-action="retry_job"][data-historical-workflow-job-guidance-retry-eligible="true"][data-historical-workflow-job-guidance-retry-reason="failed_job_retryable"]),
               "Retry failed job #{job.job_id}"
             )

      view
      |> element("#dashboard-historical-workflow-retry-job")
      |> render_click()

      assert_patch(view)

      assert {:ok, retried_job} = Cadence.fetch_background_job(job.job_id)
      assert retried_job.status == :queued
      assert retried_job.attempt_count == 1
      assert retried_job.failure_reason == nil
      assert retried_job.started_at == nil
      assert retried_job.completed_at == nil

      events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-workflow-run-retry"
        )

      assert Enum.map(events, & &1.event_type) == [:backfill_failed, :backfill_retried]
      retried_event = List.last(events)
      assert retried_event.reason == "dashboard_historical_workflow_retried"
      assert retried_event.payload["retry_action"] == "retry_job"
      assert retried_event.payload["retry_source_event_id"] == event.backfill_lifecycle_event_id
      assert retried_event.payload["retry_job_id"] == job.job_id
      assert retried_event.payload["retry_job_status"] == "queued"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Backfill lifecycle event"]),
               retried_event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow stage"]),
               "retried"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="retry_job"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="retry_job_recorded"][data-workflow-latest-action-job-id="#{job.job_id}"][data-workflow-latest-action-result-event-ids="#{retried_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{retried_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-workflow-run-retry"]),
               retried_event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{retried_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target_result"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_id=#{retried_event.backfill_lifecycle_event_id}"]),
               "Selected result"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow retry source event"]),
               event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-status[data-historical-workflow-job-id="#{job.job_id}"][data-historical-workflow-job-status="queued"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-guidance[data-historical-workflow-job-guidance-next-action="monitor_job"][data-historical-workflow-job-guidance-retry-eligible="false"][data-historical-workflow-job-guidance-retry-reason="job_not_failed"]),
               "monitor the worker outcome"
             )

      refute has_element?(view, "#dashboard-historical-workflow-retry-job")
    end
  end
end
