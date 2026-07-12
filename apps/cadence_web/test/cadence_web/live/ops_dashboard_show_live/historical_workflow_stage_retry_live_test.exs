defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStageRetryLiveTest do
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
      Process.get(:ops_dashboard_historical_workflow_stage_retry_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(
        :ops_dashboard_historical_workflow_stage_retry_views,
        MapSet.put(tracked_views, pid)
      )

      on_exit({:ops_dashboard_historical_workflow_stage_retry_view, pid}, fn ->
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

  describe "historical workflow stage surfaces" do
    test "records historical workflow stages from the backfill lifecycle inspector" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "requested",
                 %{
                   backfill_run_id: "dashboard-workflow-run-1",
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
                   reason: "operator_requested_backfill",
                   actor_id: "operator-2",
                   actor_kind: "operator",
                   payload: %{
                     "dashboard_context" => %{
                       "dashboard_id" => dashboard.dashboard_id,
                       "dashboard_version" => "1",
                       "dashboard_time_mode" => "replay_run",
                       "dashboard_replay_run_id" => "replay-stage-1",
                       "dashboard_data_view" => "all_revisions",
                       "dashboard_limit_mode" => "observed"
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{event.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_backfill_lifecycle_event"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-controls[data-historical-workflow="backfill"][data-historical-workflow-stage="requested"][data-historical-workflow-run-id="dashboard-workflow-run-1"])
             )

      assert has_element?(view, "#dashboard-historical-workflow-requested[disabled]")
      assert has_element?(view, "#dashboard-historical-workflow-approved:not([disabled])")
      assert has_element?(view, "#dashboard-historical-workflow-confirm[required]")

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-dashboard-replay-run-id[value="replay-stage-1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-dashboard-limit-mode[value="observed"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-action-explanations [data-workflow-action-explanation-id="stage_requested"][data-workflow-action-explanation-reason="already_in_stage"]),
               "Request is already the current workflow stage."
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-action-explanations [data-workflow-action-explanation-id="stage_requested"][data-workflow-action-explanation-state="current stage requested"]),
               "current stage requested"
             )

      unconfirmed_html =
        view
        |> element("#dashboard-historical-workflow-form")
        |> render_submit(%{
          "historical_workflow" => %{
            "stage" => "approved",
            "reason" => "operator_approved_backfill_window",
            "source_from" => "2026-06-22T10:15:00Z",
            "source_to" => "2026-06-22T10:45:00Z"
          }
        })

      assert unconfirmed_html =~
               "Confirm the historical data workflow approved transition before recording it."

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-action-outcome[data-workflow-action="stage_transition"][data-workflow-action-status="blocked"][data-workflow-action-reason="confirmation_required"][data-workflow-action-stage="approved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="stage_transition"][data-workflow-latest-action-status="blocked"][data-workflow-latest-action-reason="confirmation_required"][data-workflow-latest-action-stage="approved"]),
               "Confirm the historical data workflow approved transition before recording it."
             )

      assert [_requested] =
               Storage.list_backfill_lifecycle_events(
                 mission.mission_id,
                 organization_id: org.organization_id,
                 backfill_run_id: "dashboard-workflow-run-1"
               )

      view
      |> element("#dashboard-historical-workflow-form")
      |> render_submit(%{
        "historical_workflow" => %{
          "stage" => "approved",
          "confirmed" => "confirmed",
          "reason" => "operator_approved_backfill_window",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "replay_run",
          "dashboard_replay_run_id" => "replay-stage-1",
          "dashboard_data_view" => "all_revisions",
          "dashboard_limit_mode" => "observed",
          "source_from" => "2026-06-22T10:15:00Z",
          "source_to" => "2026-06-22T10:45:00Z"
        }
      })

      assert_patch(view)

      assert [_requested, approved] =
               Storage.list_backfill_lifecycle_events(
                 mission.mission_id,
                 organization_id: org.organization_id,
                 backfill_run_id: "dashboard-workflow-run-1"
               )

      assert approved.event_type == :backfill_approved
      assert approved.reason == "operator_approved_backfill_window"
      assert approved.source_from == ~U[2026-06-22 10:15:00.000000Z]
      assert approved.source_to == ~U[2026-06-22 10:45:00.000000Z]

      assert approved.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "replay_run",
               "dashboard_replay_run_id" => "replay-stage-1",
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "observed"
             }

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-action-outcome[data-workflow-action="stage_transition"][data-workflow-action-status="ok"][data-workflow-action-reason="stage_recorded"][data-workflow-action-stage="approved"][data-workflow-action-target-event-id="#{approved.backfill_lifecycle_event_id}"][data-workflow-action-target-run-id="dashboard-workflow-run-1"][data-workflow-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-action-dashboard-version="1"][data-workflow-action-dashboard-time-mode="replay_run"][data-workflow-action-dashboard-replay-run-id="replay-stage-1"][data-workflow-action-dashboard-data-view="all_revisions"][data-workflow-action-dashboard-limit-mode="observed"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="stage_transition"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="stage_recorded"][data-workflow-latest-action-stage="approved"][data-workflow-latest-action-target-event-id="#{approved.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-workflow-run-1"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="replay_run"][data-workflow-latest-action-dashboard-replay-run-id="replay-stage-1"][data-workflow-latest-action-dashboard-data-view="all_revisions"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Historical data workflow approved recorded."
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{approved.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_id=#{approved.backfill_lifecycle_event_id}"]),
               "Selected event"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "backfill_approved"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow stage"]),
               "approved"
             )

      view
      |> element("#dashboard-historical-workflow-form")
      |> render_submit(%{
        "historical_workflow" => %{
          "stage" => "started",
          "confirmed" => "confirmed",
          "reason" => "operator_started_backfill_window",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "replay_run",
          "dashboard_replay_run_id" => "replay-stage-1",
          "dashboard_data_view" => "all_revisions",
          "dashboard_limit_mode" => "observed",
          "source_from" => "2026-06-22T10:15:00Z",
          "source_to" => "2026-06-22T10:45:00Z"
        }
      })

      assert_patch(view)

      assert {:ok, job} =
               Cadence.fetch_telemetry_historical_data_workflow_job("dashboard-workflow-run-1")

      assert job.job_type == :telemetry_historical_data_workflow
      assert job.status == :queued
      assert job.payload["workflow"] == "backfill"

      started_events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-workflow-run-1"
        )

      started = Enum.find(started_events, &(&1.event_type == :backfill_started))

      assert started.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "replay_run",
               "dashboard_replay_run_id" => "replay-stage-1",
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "observed"
             }

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="stage_transition"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="stage_recorded_job_queued"][data-workflow-latest-action-stage="started"][data-workflow-latest-action-job-id="#{job.job_id}"][data-workflow-latest-action-target-event-id="#{started.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-workflow-run-1"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="replay_run"][data-workflow-latest-action-dashboard-replay-run-id="replay-stage-1"][data-workflow-latest-action-dashboard-data-view="all_revisions"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Historical data workflow started recorded and job #{job.job_id} queued."
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{started.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_id=#{started.backfill_lifecycle_event_id}"]),
               "Selected event"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-status[data-historical-workflow-job-id="#{job.job_id}"][data-historical-workflow-job-status="queued"])
             )

      assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_job.job_id == job.job_id

      assert {:ok, completed_job} = Cadence.Jobs.run_job(claimed_job.job_id)
      assert completed_job.status == :completed

      events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-workflow-run-1"
        )

      assert Enum.map(events, & &1.event_type) == [
               :backfill_requested,
               :backfill_approved,
               :backfill_started,
               :backfill_completed
             ]

      completed = List.last(events)
      assert completed.reason == "historical_data_job_completed"
      assert completed.payload["job_id"] == job.job_id
    end
  end
end
