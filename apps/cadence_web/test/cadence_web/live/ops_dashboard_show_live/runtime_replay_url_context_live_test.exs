defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayUrlContextLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSources,
    Document,
    RenderItem
  }

  alias Cadence.Control.Replay.Store.ReplayRunRow
  alias Cadence.Replay.Run
  alias Cadence.Repo
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

  defp value_tile(point_id, mode, spacecraft_id) do
    %{
      type: :value_tile,
      title: "Counter",
      binding: %{mode: mode, spacecraft_id: spacecraft_id, point_id: point_id}
    }
  end

  defp persist_dashboard_realm!(
         mission,
         realm,
         capabilities \\ %{range_scan?: true, latest?: true}
       ) do
    data_source_id = "test-#{realm}-questdb-#{System.unique_integer([:positive])}"

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: capabilities
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "test-#{realm}-binding-#{System.unique_integer([:positive])}",
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               realm: realm,
               logical_source: :telemetry,
               data_source_id: data_source_id,
               dataset: to_string(realm),
               priority: 0
             })

    %{data_source_id: data_source_id}
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp fetch_dashboard_document!(org, mission, dashboard) do
    assert {:ok, document} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    document
  end

  defp render_item_by_title(%Document{} = document, title) do
    document
    |> RenderItem.from_document()
    |> Enum.find(&(&1.widget.title == title))
  end

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views = Process.get(:ops_dashboard_live_test_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_live_test_views, MapSet.put(tracked_views, pid))

      on_exit({:ops_dashboard_live_view, pid}, fn ->
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

  test "replay URL runtime params drive replay contexts without live refresh" do
    {conn, org, mission} = signed_in_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Replay")
    _source = persist_dashboard_realm!(mission, :replay)

    replay_run =
      Run.new(%{
        replay_run_id: "replay_run_001",
        mission_id: mission.mission_id,
        binding_set_id: "replay-runtime-binding-set",
        binding_set_version: 1,
        status: :completed,
        replayed_evidence_count: 3,
        replayed_packet_count: 3,
        replayed_sample_count: 2,
        started_at: ~U[2026-06-17 11:59:00Z],
        completed_at: ~U[2026-06-17 12:06:00Z]
      })

    Repo.insert!(ReplayRunRow.changeset(replay_run))

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Runtime",
        widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    replay_widget = render_item_by_title(document, "Counter").widget

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=replay_run_001"
      )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-dashboard-replay-run-id="replay_run_001"][data-dashboard-data-realm="replay"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="replay_run_001"][data-engine-snapshot="true"][data-engine-live-append-eligible="false"])
           )

    assert has_element?(view, ~s(#dashboard-time-mode option[value="replay_run"]))

    assert has_element?(
             view,
             ~s(#dashboard-replay-run-selector option[value="replay_run_001"][selected])
           )

    assert has_element?(
             view,
             ~s(#dashboard-replay-progress-clock[data-dashboard-replay-run-id="replay_run_001"][data-dashboard-replay-run-known="true"][data-dashboard-replay-run-status="completed"][data-dashboard-replay-run-sample-count="2"])
           )

    refute has_element?(view, "#dashboard-replay-metadata-warning")

    view
    |> element("#dashboard-historical-workflow-request-button")
    |> render_click()

    assert has_element?(
             view,
             ~s(input[name="historical_workflow_request[dashboard_time_mode]"][value="replay_run"])
           )

    assert has_element?(
             view,
             ~s(input[name="historical_workflow_request[dashboard_replay_run_id]"][value="replay_run_001"])
           )

    assert has_element?(
             view,
             ~s(input[name="historical_workflow_request[dashboard_limit_mode]"][value="observed"])
           )

    view
    |> element(
      ~s(#widget-#{replay_widget.widget_id} [data-engine-warning-detail="capability_fallback"] [data-warning-link-target="telemetry point"])
    )
    |> render_click()

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_point"][data-data-link-status="context_only"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Time mode"]),
             "replay_run"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             "replay_run_001"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Data realm"]),
             "replay"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="time_mode=replay_run"][data-clipboard-text*="replay_run_id=replay_run_001"][data-clipboard-text*="selected_target=telemetry_point"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-explore[href*="time_mode=replay_run"][href*="replay_run_id=replay_run_001"][href*="realm=replay"])
           )

    send(view.pid, :tick)
    render(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-runtime-refresh-noops*="live_tick:not_live_time_mode"][data-runtime-canceled-resolves="0"][data-runtime-failed-resolves="0"])
           )

    view |> element("#dashboard-time-preset-live") |> render_click()
    assert_patch(view, show_path(mission, dashboard))
    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"][data-engine-snapshot="false"][data-engine-live-append-eligible="true"])
           )
  end
end
