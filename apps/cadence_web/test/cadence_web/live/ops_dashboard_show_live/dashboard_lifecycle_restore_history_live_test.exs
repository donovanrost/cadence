defmodule CadenceWeb.OpsDashboardShowLive.DashboardLifecycleRestoreHistoryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

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

    {:ok, activity, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/activity"
      )

    assert has_element?(activity, ~s(#dashboard-version-detail[data-selected-version="2"]))
    assert has_element?(activity, "#dashboard-version-1")
    assert has_element?(activity, ~s([data-dashboard-activity-type="published"]))
    assert has_element?(activity, ~s(#dashboard-activity-restore[disabled]))

    activity |> element("#dashboard-version-1") |> render_click()
    refute has_element?(activity, ~s(#dashboard-activity-restore[disabled]))
    activity |> element("#dashboard-activity-restore") |> render_click()

    assert has_element?(activity, ~s([data-dashboard-activity-type="reverted"]))

    {:ok, restored_view, _html} = live(conn, show_path(mission, dashboard))
    render_dashboard_async(restored_view)

    assert has_element?(
             restored_view,
             ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"][data-dashboard-publication-state="draft_ahead"][data-dashboard-publishable-version="3"])
           )

    assert has_element?(restored_view, "h1", "Published Power")

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
