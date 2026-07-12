defmodule CadenceWeb.OpsDashboardShowLive.DashboardLifecycleConflictLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias Cadence.Persistence.Schemas.OpsDashboardRow
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

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp bump_dashboard_row_latest_version!(org, mission, dashboard, version)
       when is_integer(version) and version > 0 do
    row =
      Repo.get_by!(OpsDashboardRow,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: dashboard.dashboard_id
      )

    row
    |> Ecto.Changeset.change(%{latest_version: version, draft_version: version})
    |> Repo.update!()
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

  test "refreshes archived dashboard list when a stale restore conflicts" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Restore Conflict")

    assert :ok =
             Cadence.Dashboards.archive_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               expected_version: 1
             )

    {:ok, list_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")

    assert has_element?(
             list_view,
             ~s(#restore-dashboard-#{dashboard.dashboard_id}[phx-value-expected-version="1"])
           )

    bump_dashboard_row_latest_version!(org, mission, dashboard, 2)

    html =
      list_view
      |> element("#restore-dashboard-#{dashboard.dashboard_id}")
      |> render_click()

    assert html =~ "Dashboard changed in another session. Reloaded version 2"
    assert has_element?(list_view, "#archived-dashboard-#{dashboard.dashboard_id}")

    assert [] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert [%Cadence.Dashboards.DashboardSummary{} = archived_summary] =
             Cadence.Dashboards.list_archived_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert archived_summary.lifecycle_state == "archived"
    assert archived_summary.latest_version == 2

    assert [%Cadence.Dashboards.LifecycleEvent{event_type: :archived}] =
             Cadence.Dashboards.list_lifecycle_events(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )
  end

  test "reloads the latest dashboard when a stale publish conflicts" do
    {conn, org, mission} = signed_in_org_and_mission()
    %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

    {:ok, view, _html} = live(conn, show_path(mission, dashboard))
    render_dashboard_async(view)

    assert {:ok, %Document{} = _updated} =
             Cadence.Dashboards.update_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %Document{dashboard | name: "Power Updated"},
               expected_version: Document.version(dashboard)
             )

    html =
      view
      |> element(~s(#dashboard-menu button[phx-click="publish_dashboard"]))
      |> render_click()

    assert html =~ "Dashboard changed in another session"
    assert has_element?(view, "h1", "Power Updated")

    assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert summary.latest_version == 2
    assert summary.draft_version == 2
    assert summary.published_version == nil

    assert [] =
             Cadence.Dashboards.list_lifecycle_events(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )
  end

  test "reloads the latest dashboard when a stale archive conflicts" do
    {conn, org, mission} = signed_in_org_and_mission()
    %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

    {:ok, view, _html} = live(conn, show_path(mission, dashboard))
    render_dashboard_async(view)

    assert {:ok, %Document{} = _updated} =
             Cadence.Dashboards.update_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %Document{dashboard | name: "Power Updated"},
               expected_version: Document.version(dashboard)
             )

    html =
      view
      |> element(~s(#dashboard-menu button[phx-click="archive_dashboard"]))
      |> render_click()

    assert html =~ "Dashboard changed in another session"
    assert has_element?(view, "h1", "Power Updated")

    assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert summary.latest_version == 2
    assert summary.lifecycle_state == "active"

    assert [] =
             Cadence.Dashboards.list_lifecycle_events(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )
  end
end
