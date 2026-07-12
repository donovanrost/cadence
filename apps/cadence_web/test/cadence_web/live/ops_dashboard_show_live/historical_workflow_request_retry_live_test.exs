defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRequestRetryLiveTest do
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

  describe "historical workflow request and retry surfaces" do
    test "records direct historical workflow requests from the dashboard toolbar" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view
      |> element("#dashboard-historical-workflow-request-button")
      |> render_click()

      assert has_element?(view, "#dashboard-historical-workflow-request-form")

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[dashboard_id]"][value="#{dashboard.dashboard_id}"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[dashboard_version]"][value="1"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[dashboard_limit_mode]"][value="observed"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-request-preview [data-preview-field="dashboard"]),
               "#{dashboard.dashboard_id} v1"
             )

      view
      |> element("#dashboard-historical-workflow-request-form")
      |> render_submit(%{
        "historical_workflow_request" => %{
          "workflow" => "backfill",
          "run_id" => "dashboard-workflow-run-direct",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "observable_id" => "HK.counter",
          "point_id" => "HK.counter",
          "source_from" => "2026-06-22T10:00:00Z",
          "source_to" => "2026-06-22T11:00:00Z",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "live",
          "dashboard_replay_run_id" => "",
          "dashboard_data_view" => "canonical",
          "dashboard_limit_mode" => "observed",
          "reason" => "operator_requested_backfill_from_dashboard",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      assert [requested] =
               Storage.list_backfill_lifecycle_events(
                 mission.mission_id,
                 organization_id: org.organization_id,
                 backfill_run_id: "dashboard-workflow-run-direct"
               )

      assert requested.event_type == :backfill_requested
      assert requested.reason == "operator_requested_backfill_from_dashboard"
      assert requested.realm == :backfill
      assert requested.data_source_id == "managed_questdb_backfill"
      assert requested.binding_id == "backfill_telemetry"
      assert requested.observable_id == "HK.counter"
      assert requested.point_id == "HK.counter"
      assert requested.source_from == ~U[2026-06-22 10:00:00.000000Z]
      assert requested.source_to == ~U[2026-06-22 11:00:00.000000Z]
      assert requested.payload["request_source"] == "dashboard_direct_request"

      assert requested.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "live",
               "dashboard_data_view" => "canonical",
               "dashboard_limit_mode" => "observed"
             }

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Backfill run"]),
               "dashboard-workflow-run-direct"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow stage"]),
               "requested"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="request"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="request_recorded"][data-workflow-latest-action-count="1"][data-workflow-latest-action-result-event-ids="#{requested.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{requested.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-workflow-run-direct"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="live"][data-workflow-latest-action-dashboard-data-view="canonical"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Historical data workflow request recorded."
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action-handoffs[data-workflow-latest-action-handoff-count="1"][data-workflow-latest-action-handoff-primary-event="#{requested.backfill_lifecycle_event_id}"])
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{requested.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target_result"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_target=telemetry_backfill_lifecycle_event"][data-workflow-latest-action-handoff-href*="selected_id=#{requested.backfill_lifecycle_event_id}"]),
               "Selected result"
             )
    end

    test "records direct import workflow requests from the dashboard toolbar" do
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
          "run_id" => "dashboard-import-run-direct",
          "realm" => "backfill",
          "data_source_id" => "customer_archive_import",
          "source_binding_id" => "import_telemetry",
          "observable_id" => "HK.counter",
          "point_id" => "HK.counter",
          "source_from" => "2026-06-22T12:00:00Z",
          "source_to" => "2026-06-22T13:00:00Z",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "archive",
          "dashboard_replay_run_id" => "",
          "dashboard_data_view" => "as_recorded",
          "dashboard_limit_mode" => "observed",
          "reason" => "operator_requested_import_from_dashboard",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      assert [requested] =
               Storage.list_backfill_lifecycle_events(
                 mission.mission_id,
                 organization_id: org.organization_id,
                 backfill_run_id: "dashboard-import-run-direct"
               )

      assert requested.event_type == :import_requested
      assert requested.reason == "operator_requested_import_from_dashboard"
      assert requested.realm == :backfill
      assert requested.data_source_id == "customer_archive_import"
      assert requested.binding_id == "import_telemetry"
      assert requested.observable_id == "HK.counter"
      assert requested.point_id == "HK.counter"
      assert requested.source_from == ~U[2026-06-22 12:00:00.000000Z]
      assert requested.source_to == ~U[2026-06-22 13:00:00.000000Z]
      assert requested.payload["request_source"] == "dashboard_direct_request"
      assert requested.payload["workflow"] == "import"
      assert requested.payload["run_id"] == "dashboard-import-run-direct"

      assert requested.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "archive",
               "dashboard_data_view" => "as_recorded",
               "dashboard_limit_mode" => "observed"
             }

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow"]),
               "import"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "import_requested"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow run"]),
               "dashboard-import-run-direct"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="request"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="request_recorded"][data-workflow-latest-action-count="1"][data-workflow-latest-action-result-event-ids="#{requested.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{requested.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-import-run-direct"]),
               "Historical data workflow request recorded."
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{requested.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target_result"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_target=telemetry_backfill_lifecycle_event"][data-workflow-latest-action-handoff-href*="selected_id=#{requested.backfill_lifecycle_event_id}"]),
               "Selected result"
             )
    end
  end
end
