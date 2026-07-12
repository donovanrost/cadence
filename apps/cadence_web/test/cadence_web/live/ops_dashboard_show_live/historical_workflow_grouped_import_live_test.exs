defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupedImportLiveTest do
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
      Process.get(:ops_dashboard_historical_workflow_grouped_import_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(
        :ops_dashboard_historical_workflow_grouped_import_views,
        MapSet.put(tracked_views, pid)
      )

      on_exit({:ops_dashboard_historical_workflow_grouped_import_view, pid}, fn ->
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

  describe "grouped historical import workflow request surfaces" do
    test "records grouped import workflow requests and group approval from the dashboard toolbar" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view
      |> element("#dashboard-historical-workflow-request-button")
      |> render_click()

      view
      |> element("#dashboard-historical-workflow-request-form")
      |> render_submit(%{
        "historical_workflow_request" => %{
          "workflow" => "import",
          "run_id" => "dashboard-import-run-bulk",
          "realm" => "backfill",
          "data_source_id" => "customer_archive_import",
          "source_binding_id" => "import_telemetry",
          "point_ids" => "HK.counter, HK.voltage",
          "source_from" => "2026-06-22T14:00:00Z",
          "source_to" => "2026-06-22T15:00:00Z",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "archive",
          "dashboard_replay_run_id" => "",
          "dashboard_data_view" => "as_recorded",
          "dashboard_limit_mode" => "observed",
          "reason" => "operator_requested_bulk_import_from_dashboard",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      requested_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :import_requested
        )
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-import-run-bulk"))
        |> Enum.sort_by(& &1.payload["request_item_index"])

      assert Enum.map(requested_events, & &1.point_id) == ["HK.counter", "HK.voltage"]

      assert Enum.map(requested_events, & &1.backfill_run_id) == [
               "dashboard-import-run-bulk-001",
               "dashboard-import-run-bulk-002"
             ]

      assert Enum.all?(requested_events, &(&1.payload["workflow"] == "import"))
      assert Enum.all?(requested_events, &(&1.payload["request_mode"] == "bulk_points"))
      assert Enum.all?(requested_events, &(&1.payload["request_item_count"] == 2))
      assert Enum.all?(requested_events, &(&1.realm == :backfill))
      assert Enum.all?(requested_events, &(&1.data_source_id == "customer_archive_import"))
      assert Enum.all?(requested_events, &(&1.binding_id == "import_telemetry"))

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="request"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="request_group_recorded"][data-workflow-latest-action-request-group-id="dashboard-import-run-bulk"][data-workflow-latest-action-count="2"][data-workflow-latest-action-result-event-ids*="#{Enum.at(requested_events, 0).backfill_lifecycle_event_id}"][data-workflow-latest-action-result-event-ids*="#{Enum.at(requested_events, 1).backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-import-run-bulk-001"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="archive"][data-workflow-latest-action-dashboard-data-view="as_recorded"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Historical data workflow request group recorded for 2 points."
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="requested"][data-historical-workflow-group-size="2"][data-historical-workflow-group-requested="2"][data-historical-workflow-group-approved="0"][data-historical-workflow-group-approve-eligible="2"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-eligible-items[data-historical-workflow-group-eligible-request-group="dashboard-import-run-bulk"][data-historical-workflow-group-eligible-size="2"])
             )

      view
      |> element("#dashboard-historical-workflow-group-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "import",
          "request_group_id" => "dashboard-import-run-bulk",
          "realm" => "backfill",
          "data_source_id" => "customer_archive_import",
          "source_binding_id" => "import_telemetry",
          "stage" => "approved",
          "reason" => "operator_approved_bulk_import_from_dashboard",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "archive",
          "dashboard_replay_run_id" => "",
          "dashboard_data_view" => "as_recorded",
          "dashboard_limit_mode" => "observed",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      approved_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :import_approved
        )
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-import-run-bulk"))
        |> Enum.sort_by(& &1.payload["request_item_index"])

      assert Enum.map(approved_events, & &1.point_id) == ["HK.counter", "HK.voltage"]

      assert Enum.map(approved_events, & &1.backfill_run_id) == [
               "dashboard-import-run-bulk-001",
               "dashboard-import-run-bulk-002"
             ]

      assert Enum.all?(
               approved_events,
               &(&1.reason == "operator_approved_bulk_import_from_dashboard")
             )

      assert Enum.all?(
               approved_events,
               &(&1.payload["group_transition_source"] == "dashboard_group_action")
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow"]),
               "import"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "import_approved"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="group_stage_transition"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="group_approved_recorded"][data-workflow-latest-action-stage="approved"][data-workflow-latest-action-request-group-id="dashboard-import-run-bulk"][data-workflow-latest-action-count="2"][data-workflow-latest-action-result-event-ids*="#{Enum.at(approved_events, 0).backfill_lifecycle_event_id}"][data-workflow-latest-action-result-event-ids*="#{Enum.at(approved_events, 1).backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-import-run-bulk-001"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="archive"][data-workflow-latest-action-dashboard-data-view="as_recorded"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Historical data workflow group approved recorded for 2 items."
             )

      view
      |> element("#dashboard-historical-workflow-group-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "import",
          "request_group_id" => "dashboard-import-run-bulk",
          "realm" => "backfill",
          "data_source_id" => "customer_archive_import",
          "source_binding_id" => "import_telemetry",
          "stage" => "started",
          "reason" => "operator_started_bulk_import_from_dashboard",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "archive",
          "dashboard_replay_run_id" => "",
          "dashboard_data_view" => "as_recorded",
          "dashboard_limit_mode" => "observed",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      started_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :import_started
        )
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-import-run-bulk"))
        |> Enum.sort_by(& &1.payload["request_item_index"])

      assert Enum.map(started_events, & &1.backfill_run_id) == [
               "dashboard-import-run-bulk-001",
               "dashboard-import-run-bulk-002"
             ]

      assert Enum.all?(
               started_events,
               &(&1.reason == "operator_started_bulk_import_from_dashboard")
             )

      assert {:ok, counter_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(
                 "dashboard-import-run-bulk-001"
               )

      assert {:ok, voltage_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(
                 "dashboard-import-run-bulk-002"
               )

      assert Enum.map([counter_job, voltage_job], & &1.status) == [:queued, :queued]

      assert Enum.map([counter_job, voltage_job], & &1.payload["workflow"]) == [
               "import",
               "import"
             ]

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="group_stage_transition"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="group_started"][data-workflow-latest-action-stage="started"][data-workflow-latest-action-request-group-id="dashboard-import-run-bulk"][data-workflow-latest-action-count="2"][data-workflow-latest-action-queued-jobs="2"][data-workflow-latest-action-failed-jobs="0"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="archive"][data-workflow-latest-action-dashboard-data-view="as_recorded"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Historical data workflow group started for 2 items; 2 jobs queued."
             )

      claimed_jobs = Cadence.Jobs.claim_jobs(2)

      assert MapSet.new(Enum.map(claimed_jobs, & &1.job_id)) ==
               MapSet.new([counter_job.job_id, voltage_job.job_id])

      assert {:ok, completed_job} = Cadence.Jobs.run_job(counter_job.job_id)
      assert completed_job.status == :completed

      import_events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-import-run-bulk-001"
        )

      assert Enum.map(import_events, & &1.event_type) == [
               :import_requested,
               :import_approved,
               :import_started,
               :import_completed
             ]

      completed_event = List.last(import_events)
      assert completed_event.reason == "historical_data_job_completed"
      assert completed_event.payload["workflow_job_status"] == "completed"
      assert completed_event.payload["job_id"] == counter_job.job_id
      assert completed_event.payload["request_group_id"] == "dashboard-import-run-bulk"
    end
  end
end
