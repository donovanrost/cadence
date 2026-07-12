defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowImportRetryLiveTest do
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
      Process.get(:ops_dashboard_historical_workflow_request_retry_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(
        :ops_dashboard_historical_workflow_request_retry_views,
        MapSet.put(tracked_views, pid)
      )

      on_exit({:ops_dashboard_historical_workflow_request_retry_view, pid}, fn ->
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

  describe "historical workflow import retry surfaces" do
    test "retries failed import workflow jobs from the lifecycle inspector" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "import",
                 "failed",
                 %{
                   import_run_id: "dashboard-import-run-retry",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "customer_archive_import",
                   binding_id: "import_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   source_from: ~U[2026-06-22 12:00:00Z],
                   source_to: ~U[2026-06-22 13:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "dashboard_context" => %{
                       "dashboard_id" => dashboard.dashboard_id,
                       "dashboard_version" => "1",
                       "dashboard_time_mode" => "replay_run",
                       "dashboard_replay_run_id" => "replay-retry-1",
                       "dashboard_data_view" => "all_revisions",
                       "dashboard_limit_mode" => "compare"
                     },
                     "failure" => "archive source window unavailable"
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert event.event_type == :import_failed
      assert event.backfill_run_id == "dashboard-import-run-retry"
      assert event.payload["workflow"] == "import"

      assert {:ok, job} =
               Cadence.Jobs.enqueue(
                 :telemetry_historical_data_workflow,
                 mission.mission_id,
                 "dashboard-import-run-retry",
                 %{
                   "workflow" => "import",
                   "attrs" => %{"import_run_id" => "dashboard-import-run-retry"}
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
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow"]),
               "import"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "import_failed"
             )

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

      events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-import-run-retry"
        )

      assert Enum.map(events, & &1.event_type) == [:import_failed, :import_retried]
      retried_event = List.last(events)
      assert retried_event.reason == "dashboard_historical_workflow_retried"
      assert retried_event.payload["workflow"] == "import"
      assert retried_event.payload["retry_action"] == "retry_job"
      assert retried_event.payload["retry_source_event_id"] == event.backfill_lifecycle_event_id
      assert retried_event.payload["retry_source_event_type"] == "import_failed"
      assert retried_event.payload["retry_job_id"] == job.job_id
      assert retried_event.payload["retry_job_status"] == "queued"

      assert retried_event.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "replay_run",
               "dashboard_replay_run_id" => "replay-retry-1",
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "compare"
             }

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow stage"]),
               "retried"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="retry_job"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="retry_job_recorded"][data-workflow-latest-action-job-id="#{job.job_id}"][data-workflow-latest-action-result-event-ids="#{retried_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{retried_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-import-run-retry"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="replay_run"][data-workflow-latest-action-dashboard-replay-run-id="replay-retry-1"][data-workflow-latest-action-dashboard-data-view="all_revisions"][data-workflow-latest-action-dashboard-limit-mode="compare"]),
               retried_event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{retried_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target_result"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_target=telemetry_backfill_lifecycle_event"][data-workflow-latest-action-handoff-href*="selected_id=#{retried_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-href*="time_mode=replay_run"][data-workflow-latest-action-handoff-href*="replay_run_id=replay-retry-1"][data-workflow-latest-action-handoff-href*="selected_data_view=all_revisions"][data-workflow-latest-action-handoff-href*="limit_mode=compare"]),
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

      refute has_element?(view, "#dashboard-historical-workflow-retry-job")
    end

    test "retries grouped failed import workflow jobs from the lifecycle inspector" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      import_items = [
        {"HK.counter", "dashboard-import-run-group-retry-001", 1},
        {"HK.voltage", "dashboard-import-run-group-retry-002", 2}
      ]

      failed_items =
        for {point_id, run_id, item_index} <- import_items do
          assert {:ok, job} =
                   Cadence.Jobs.enqueue(
                     :telemetry_historical_data_workflow,
                     mission.mission_id,
                     run_id,
                     %{"workflow" => "import", "attrs" => %{"import_run_id" => run_id}}
                   )

          assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
          assert claimed_job.job_id == job.job_id
          assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :source_failed)
          assert failed_job.status == :failed

          assert {:ok, failed_event} =
                   Cadence.record_telemetry_historical_data_workflow_event(
                     "import",
                     "failed",
                     %{
                       import_run_id: run_id,
                       organization_id: org.organization_id,
                       mission_id: mission.mission_id,
                       realm: :backfill,
                       data_source_id: "customer_archive_import",
                       binding_id: "import_telemetry",
                       observable_id: point_id,
                       point_id: point_id,
                       source_from: ~U[2026-06-22 14:00:00Z],
                       source_to: ~U[2026-06-22 15:00:00Z],
                       authority: :advisory,
                       reason: "historical_data_job_failed",
                       actor_id: "system",
                       actor_kind: "system",
                       payload: %{
                         "request_source" => "dashboard_direct_request",
                         "request_mode" => "bulk_points",
                         "request_group_id" => "dashboard-import-run-group-retry",
                         "request_item_index" => item_index,
                         "request_item_count" => 2,
                         "request_item_run_id" => run_id,
                         "job_id" => job.job_id,
                         "dashboard_context" => %{
                           "dashboard_id" => dashboard.dashboard_id,
                           "dashboard_version" => "1",
                           "dashboard_time_mode" => "archive",
                           "dashboard_data_view" => "as_recorded",
                           "dashboard_limit_mode" => "observed"
                         },
                         "source" => %{
                           "failure" => %{
                             "code" => "archive_source_window_unavailable",
                             "retryable" => true,
                             "recovery_action" => "retry_job"
                           }
                         }
                       }
                     },
                     dashboard_runtime_invalidation?: false
                   )

          {failed_event, job}
        end

      [{first_failed_event, first_job}, {second_failed_event, second_job}] = failed_items

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{first_failed_event.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow"]),
               "import"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="failed"][data-historical-workflow-group-failed="2"][data-historical-workflow-group-retryable-failed="2"][data-historical-workflow-group-nonretryable-failed="0"]),
               "HK.counter"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-guidance[data-historical-workflow-group-recovery-guidance-next-action="retry_failed_items"][data-historical-workflow-group-recovery-guidance-retry-eligible="true"][data-historical-workflow-group-recovery-guidance-retry-reason="retryable_group_failures"]),
               "Retry 2 failed jobs in request group dashboard-import-run-group-retry"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-retry-failed[data-workflow-action-eligible-count="2"])
             )

      view
      |> element("#dashboard-historical-workflow-group-retry-failed")
      |> render_click()

      assert_patch(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="retry_group_failed_jobs"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-request-group-id="dashboard-import-run-group-retry"][data-workflow-latest-action-retried="2"][data-workflow-latest-action-retry-nonretryable="0"][data-workflow-latest-action-retry-skipped="0"][data-workflow-latest-action-retry-errors="0"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="archive"][data-workflow-latest-action-dashboard-data-view="as_recorded"][data-workflow-latest-action-dashboard-limit-mode="observed"])
             )

      assert {:ok, retried_first_job} = Cadence.fetch_background_job(first_job.job_id)
      assert retried_first_job.status == :queued

      assert {:ok, retried_second_job} = Cadence.fetch_background_job(second_job.job_id)
      assert retried_second_job.status == :queued

      retried_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :import_retried
        )
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-import-run-group-retry"))
        |> Enum.sort_by(& &1.payload["request_item_index"])

      assert Enum.map(retried_events, & &1.backfill_run_id) == [
               "dashboard-import-run-group-retry-001",
               "dashboard-import-run-group-retry-002"
             ]

      assert Enum.map(retried_events, & &1.payload["workflow"]) == ["import", "import"]

      assert Enum.map(retried_events, & &1.payload["retry_source_event_id"]) == [
               first_failed_event.backfill_lifecycle_event_id,
               second_failed_event.backfill_lifecycle_event_id
             ]

      assert Enum.map(retried_events, & &1.payload["retry_source_event_type"]) == [
               "import_failed",
               "import_failed"
             ]

      assert Enum.map(retried_events, & &1.payload["retry_job_id"]) == [
               first_job.job_id,
               second_job.job_id
             ]

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "import_retried"
             )
    end
  end
end
