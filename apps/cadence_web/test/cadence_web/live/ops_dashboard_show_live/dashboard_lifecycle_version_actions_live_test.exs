defmodule CadenceWeb.OpsDashboardShowLive.DashboardLifecycleVersionActionsLiveTest do
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

  defp fetch_dashboard_version!(org, mission, dashboard, version_number) do
    assert {:ok, dashboard_version} =
             Cadence.Dashboards.fetch_version(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               version_number
             )

    dashboard_version
  end

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views = Process.get(:ops_dashboard_lifecycle_version_action_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_lifecycle_version_action_views, MapSet.put(tracked_views, pid))

      on_exit({:ops_dashboard_lifecycle_version_action_view, pid}, fn ->
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

  test "renames the dashboard from the toolbar menu without exposing hard delete" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

    {:ok, view, _html} = live(conn, show_path(mission, dashboard))
    render_dashboard_async(view)

    view |> element(~s(#dashboard-menu button[phx-click="open_rename"])) |> render_click()

    view
    |> form("#rename-dashboard-form", dashboard: %{name: "Power North", description: "EPS"})
    |> render_submit()

    renamed = fetch_dashboard_document!(org, mission, dashboard)

    assert renamed.name == "Power North"
    version = fetch_dashboard_version!(org, mission, dashboard, 2)
    assert version.change_summary == "Renamed dashboard"
    assert version.created_by == user.user_id

    assert has_element?(view, "h1", "Power North")
    assert has_element?(view, ~s(#ops-nav-rail), "Power North")

    assert has_element?(
             view,
             ~s(#dashboard-menu button[data-dashboard-lifecycle-action="archive"][data-dashboard-action-available="true"])
           )

    refute has_element?(view, ~s(#dashboard-menu button[phx-click="delete_dashboard"]))
  end

  test "publishes a historical version from the versions panel without discarding the newer draft" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()

    %Document{} =
      dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Original Power")

    assert {:ok, %Document{} = updated} =
             Cadence.Dashboards.update_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %Document{dashboard | name: "Published Power"},
               expected_version: 1
             )

    assert {:ok, %Cadence.Dashboards.Version{}} =
             Cadence.Dashboards.publish_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               Document.version(updated),
               expected_version: Document.version(updated)
             )

    {:ok, view, _html} = live(conn, show_path(mission, dashboard))
    render_dashboard_async(view)

    view |> element("#dashboard-versions-button") |> render_click()

    view |> element("#publish-version-1") |> render_click()
    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"][data-dashboard-publication-state="draft_ahead"][data-dashboard-publishable-version="2"])
           )

    assert has_element?(view, "h1", "Original Power")

    assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert summary.latest_version == 2
    assert summary.draft_version == 2
    assert summary.published_version == 1

    assert %Cadence.Dashboards.LifecycleEvent{} =
             published =
             org.organization_id
             |> Cadence.Dashboards.list_lifecycle_events(
               mission.mission_id,
               dashboard.dashboard_id
             )
             |> List.last()

    assert published.event_type == :published
    assert published.dashboard_version == 1
    assert published.actor_id == user.user_id
  end
end
