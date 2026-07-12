defmodule CadenceWeb.OpsDashboardShowLive.DashboardLifecycleRestoreHistoryLiveTest do
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
    tracked_views = Process.get(:ops_dashboard_lifecycle_restore_history_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_lifecycle_restore_history_views, MapSet.put(tracked_views, pid))

      on_exit({:ops_dashboard_lifecycle_restore_history_view, pid}, fn ->
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

  test "shows version history and restores a historical version as the latest draft" do
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

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"])
           )

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-publication-state="published_current"][data-dashboard-published-current="true"])
           )

    assert has_element?(view, "h1", "Published Power")

    view |> element("#dashboard-versions-button") |> render_click()

    assert has_element?(view, "#dashboard-versions-panel")
    assert has_element?(view, ~s(#dashboard-version-2 [data-version-pointer="published"]))
    assert has_element?(view, ~s(#dashboard-version-2 [data-version-pointer="latest"]))
    refute has_element?(view, ~s(#dashboard-version-2 [data-version-pointer="draft"]))

    assert has_element?(
             view,
             ~s(#dashboard-version-2[data-version-publish-available="false"][data-version-publish-reason="already_published"][data-version-restore-available="false"][data-version-restore-reason="already_latest"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-version-1[data-version-publish-available="true"][data-version-publish-reason="available"][data-version-restore-available="true"][data-version-restore-reason="available"])
           )

    assert has_element?(view, ~s(#publish-version-2[disabled]))
    assert has_element?(view, ~s(#restore-version-2[disabled]))
    refute has_element?(view, ~s(#publish-version-1[disabled]))
    refute has_element?(view, ~s(#restore-version-1[disabled]))
    assert has_element?(view, "#dashboard-version-1", "draft save")
    assert has_element?(view, "#dashboard-activity-list")
    assert has_element?(view, ~s([data-lifecycle-event-type="published"]))

    assert has_element?(
             view,
             ~s([data-lifecycle-event-type="published"] [data-activity-field="Published"]),
             "- -> v2"
           )

    view |> element("#restore-version-1") |> render_click()

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-document-mode="draft"])
           )

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-publication-state="draft_ahead"][data-dashboard-publishable-version="3"][data-dashboard-draft-ahead="true"])
           )

    assert has_element?(view, "#edit-paused-note")
    refute has_element?(view, "#dashboard-versions-panel")
    assert has_element?(view, "h1", "Original Power")

    view |> element("#dashboard-versions-button") |> render_click()

    assert has_element?(view, ~s([data-lifecycle-event-type="reverted"]))

    assert has_element?(
             view,
             ~s([data-lifecycle-event-type="reverted"][data-lifecycle-source-version="1"][data-lifecycle-reverted-version="3"])
           )

    assert has_element?(
             view,
             ~s([data-lifecycle-event-type="reverted"] [data-activity-field="Source"]),
             "v1"
           )

    assert has_element?(
             view,
             ~s([data-lifecycle-event-type="reverted"] [data-activity-field="New draft"]),
             "v3"
           )

    assert {:ok, %Document{} = latest_document} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    assert latest_document.name == "Original Power"
    assert Document.version(latest_document) == 3
    version = fetch_dashboard_version!(org, mission, dashboard, 3)
    assert version.change_summary == "Restored version 1 as draft"
    assert version.created_by == user.user_id

    assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert summary.latest_version == 3
    assert summary.draft_version == 3
    assert summary.published_version == 2
  end
end
