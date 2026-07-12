defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowNonretryableCorrectionLiveTest do
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
      Process.get(:ops_dashboard_historical_workflow_nonretryable_correction_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(
        :ops_dashboard_historical_workflow_nonretryable_correction_views,
        MapSet.put(tracked_views, pid)
      )

      on_exit({:ops_dashboard_historical_workflow_nonretryable_correction_view, pid}, fn ->
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

  describe "historical workflow non-retryable correction surfaces" do
    test "does not offer retry for non-retryable historical workflow failures" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_run_id: "dashboard-workflow-run-nonretryable",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "dashboard_context" => %{
                       "dashboard_id" => dashboard.dashboard_id,
                       "dashboard_version" => "1",
                       "dashboard_time_mode" => "replay_run",
                       "dashboard_replay_run_id" => "replay-correction-1",
                       "dashboard_data_view" => "all_revisions",
                       "dashboard_limit_mode" => "observed"
                     },
                     "source" => %{
                       "failure" => %{
                         "code" => "missing_field:point_id",
                         "retryable" => false,
                         "retry_blockers" => ["missing point_id"],
                         "recovery_action" => "correct_workflow_request"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, job} =
               Cadence.Jobs.enqueue(
                 :telemetry_historical_data_workflow,
                 mission.mission_id,
                 "dashboard-workflow-run-nonretryable",
                 %{
                   "workflow" => "backfill",
                   "attrs" => %{"backfill_run_id" => "dashboard-workflow-run-nonretryable"}
                 }
               )

      assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_job.job_id == job.job_id
      assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :missing_point_id)
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
               "#dashboard-historical-workflow-job-status",
               "missing_field:point_id"
             )

      assert has_element?(view, "#dashboard-historical-workflow-job-status", "false")

      assert has_element?(
               view,
               "#dashboard-historical-workflow-job-status",
               "correct_workflow_request"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-guidance[data-historical-workflow-job-guidance-next-action="create_corrected_request"][data-historical-workflow-job-guidance-retry-eligible="false"][data-historical-workflow-job-guidance-retry-reason="correction_required"][data-historical-workflow-job-guidance-correction-eligible="true"][data-historical-workflow-job-guidance-correction-reason="correction_request_required"]),
               "Create a corrected request for failed event"
             )

      refute has_element?(view, "#dashboard-historical-workflow-retry-job")
      assert has_element?(view, "#dashboard-historical-workflow-correction-form")

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-correction-dashboard-replay-run-id[value="replay-correction-1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-correction-dashboard-limit-mode[value="observed"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-action-explanations [data-workflow-action-explanation-id="retry_job"][data-workflow-action-explanation-reason="correction_required"]),
               "Create a corrected workflow request instead of retrying this job."
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-action-explanations [data-workflow-action-explanation-id="retry_job"][data-workflow-action-explanation-state="job #{job.job_id}; status failed; retryable false; recovery correct_workflow_request"]),
               "job #{job.job_id}; status failed; retryable false; recovery correct_workflow_request"
             )

      view
      |> element("#dashboard-historical-workflow-correction-form")
      |> render_submit(%{
        "historical_workflow_correction" => %{
          "workflow" => "backfill",
          "run_id" => "dashboard-workflow-run-corrected",
          "original_run_id" => "dashboard-workflow-run-nonretryable",
          "original_event_id" => event.backfill_lifecycle_event_id,
          "original_job_id" => job.job_id,
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "observable_id" => "HK.counter",
          "point_id" => "HK.counter",
          "source_from" => "2026-06-22T10:00:00Z",
          "source_to" => "2026-06-22T11:00:00Z",
          "reason" => "operator_corrected_missing_point",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "replay_run",
          "dashboard_replay_run_id" => "replay-correction-1",
          "dashboard_data_view" => "all_revisions",
          "dashboard_limit_mode" => "observed",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-workflow-run-corrected"
        )

      assert [corrected] = events
      assert corrected.event_type == :backfill_requested
      assert corrected.reason == "operator_corrected_missing_point"
      assert corrected.point_id == "HK.counter"
      assert corrected.payload["recovery_action"] == "correct_workflow_request"
      assert corrected.payload["correction_source"] == "dashboard_correction_request"
      assert corrected.payload["correction_source_event_type"] == "backfill_failed"
      assert corrected.payload["corrects_run_id"] == "dashboard-workflow-run-nonretryable"
      assert corrected.payload["corrects_event_id"] == event.backfill_lifecycle_event_id
      assert corrected.payload["corrects_job_id"] == job.job_id

      assert corrected.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "replay_run",
               "dashboard_replay_run_id" => "replay-correction-1",
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "observed"
             }

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Backfill run"]),
               "dashboard-workflow-run-corrected"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow stage"]),
               "requested"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="correction_request"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="correction_request_recorded"][data-workflow-latest-action-result-event-ids="#{corrected.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{corrected.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-workflow-run-corrected"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="replay_run"][data-workflow-latest-action-dashboard-replay-run-id="replay-correction-1"][data-workflow-latest-action-dashboard-data-view="all_revisions"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Corrected historical data workflow request recorded."
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-action-outcome[data-workflow-action="correction_request"][data-workflow-action-status="ok"][data-workflow-action-reason="correction_request_recorded"][data-workflow-action-result-event-ids="#{corrected.backfill_lifecycle_event_id}"][data-workflow-action-target-event-id="#{corrected.backfill_lifecycle_event_id}"][data-workflow-action-target-run-id="dashboard-workflow-run-corrected"][data-workflow-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-action-dashboard-version="1"][data-workflow-action-dashboard-time-mode="replay_run"][data-workflow-action-dashboard-replay-run-id="replay-correction-1"][data-workflow-action-dashboard-data-view="all_revisions"][data-workflow-action-dashboard-limit-mode="observed"])
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{corrected.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target_result"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_id=#{corrected.backfill_lifecycle_event_id}"]),
               "Selected result"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction action"]),
               "correct_workflow_request"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source"]),
               "dashboard_correction_request"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source event type"]),
               "backfill_failed"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source event"]),
               event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s([data-data-link-related-id="#{event.backfill_lifecycle_event_id}"]),
               "Correction source event"
             )

      source_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{event.backfill_lifecycle_event_id}&realm=backfill&data_source_id=managed_questdb_backfill&source_binding_id=backfill_telemetry"

      {:ok, source_view, _html} = live(conn, source_path)
      render_dashboard_async(source_view)

      assert has_element?(
               source_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_backfill_lifecycle_event"][data-data-link-status="resolved"])
             )

      assert has_element?(
               source_view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="query_only"][data-dashboard-selection-target="telemetry_backfill_lifecycle_event"])
             )

      assert has_element?(
               source_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data realm"]),
               "backfill"
             )

      assert has_element?(
               source_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
               "managed_questdb_backfill"
             )

      assert has_element?(
               source_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Source binding"]),
               "backfill_telemetry"
             )

      assert has_element?(
               source_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=telemetry_backfill_lifecycle_event"][data-clipboard-text*="selected_id=#{URI.encode_www_form(event.backfill_lifecycle_event_id)}"][data-clipboard-text*="realm=backfill"][data-clipboard-text*="data_source_id=managed_questdb_backfill"][data-clipboard-text*="source_binding_id=backfill_telemetry"])
             )

      assert has_element?(
               source_view,
               ~s([data-data-link-related-id="#{corrected.backfill_lifecycle_event_id}"]),
               "Correction request HK.counter"
             )

      source_view
      |> element(~s([data-data-link-related-id="#{corrected.backfill_lifecycle_event_id}"]))
      |> render_click()

      corrected_path = assert_patch(source_view)
      assert corrected_path =~ "panel=data_link"

      assert corrected_path =~
               "selected_id=#{URI.encode_www_form(corrected.backfill_lifecycle_event_id)}"

      assert corrected_path =~
               "nav_from_target_id=#{URI.encode_www_form(event.backfill_lifecycle_event_id)}"

      assert corrected_path =~ "nav_from_relationship_kind=correction_request"
      assert corrected_path =~ "nav_trail="
      assert corrected_path =~ "realm=backfill"
      assert corrected_path =~ "data_source_id=managed_questdb_backfill"
      assert corrected_path =~ "source_binding_id=backfill_telemetry"

      assert has_element?(
               source_view,
               ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{event.backfill_lifecycle_event_id}"])
             )

      source_view
      |> element(
        ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{event.backfill_lifecycle_event_id}"])
      )
      |> render_click()

      breadcrumb_path = assert_patch(source_view)
      assert breadcrumb_path =~ "panel=data_link"

      assert breadcrumb_path =~
               "selected_id=#{URI.encode_www_form(event.backfill_lifecycle_event_id)}"

      assert breadcrumb_path =~ "realm=backfill"
      assert breadcrumb_path =~ "data_source_id=managed_questdb_backfill"
      assert breadcrumb_path =~ "source_binding_id=backfill_telemetry"
    end
  end
end
