defmodule CadenceWeb.OpsDashboardDirectoryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  test "searches, sorts, and filters dashboard tags through restorable URL state" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()

    thermal =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Thermal Flight",
        description: "Payload temperatures",
        metadata: %{"tags" => ["thermal", "flight"]}
      )

    power =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Power Ground",
        description: "Battery posture",
        metadata: %{"tags" => ["power", "ground"]}
      )

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")

    assert has_element?(view, "#dashboard-directory-filter-form")
    assert has_element?(view, "#dashboard-directory-row-#{thermal.dashboard_id}")
    assert has_element?(view, "#dashboard-directory-row-#{power.dashboard_id}")

    view
    |> form("#dashboard-directory-filter-form",
      directory: %{query: "thermal", lifecycle: "active", tag: "flight", sort: "name"}
    )
    |> render_change()

    assert_patch(
      view,
      "/missions/#{mission.mission_id}/ops/dashboards?query=thermal&sort=name&tag=flight"
    )

    assert has_element?(view, "#dashboard-directory-row-#{thermal.dashboard_id}")
    refute has_element?(view, "#dashboard-directory-row-#{power.dashboard_id}")
  end

  test "stars are personal while opening a dashboard promotes it into recent navigation" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Mission Power")

    {:ok, directory, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")

    directory
    |> element("#dashboard-directory-star-#{dashboard.dashboard_id}")
    |> render_click()

    assert has_element?(
             directory,
             ~s(#dashboard-directory-row-#{dashboard.dashboard_id}[data-dashboard-directory-starred="true"])
           )

    assert has_element?(
             directory,
             ~s([data-ops-dashboard-nav-group="starred"] [data-ops-dashboard-nav-item="#{dashboard.dashboard_id}"])
           )

    second_user = TestFixtures.persist_user!()
    _membership = TestFixtures.grant_membership!(second_user, org)

    {:ok, second_directory, _html} =
      live(
        TestFixtures.member_conn(second_user),
        ~p"/missions/#{mission.mission_id}/ops/dashboards"
      )

    assert has_element?(
             second_directory,
             ~s(#dashboard-directory-row-#{dashboard.dashboard_id}[data-dashboard-directory-starred="false"])
           )

    refute has_element?(
             second_directory,
             ~s([data-ops-dashboard-nav-group="starred"] [data-ops-dashboard-nav-item="#{dashboard.dashboard_id}"])
           )

    assert [%{dashboard_id: dashboard_id, starred: true}] =
             Cadence.Dashboards.list_dashboard_user_preferences(
               org.organization_id,
               mission.mission_id,
               user.user_id
             )

    {:ok, recent_view, _html} =
      live(
        TestFixtures.member_conn(second_user),
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
      )

    assert dashboard_id == dashboard.dashboard_id

    assert has_element?(
             recent_view,
             ~s([data-ops-dashboard-nav-group="recent"] [data-ops-dashboard-nav-item="#{dashboard.dashboard_id}"])
           )
  end

  test "archived dashboards have a dedicated filtered view and restore outcome" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Archived Thermal")

    assert :ok =
             Cadence.Dashboards.archive_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               expected_version: 1,
               actor_id: user.user_id
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards?#{%{lifecycle: "archived"}}"
      )

    assert has_element?(
             view,
             ~s(#dashboard-directory-row-#{dashboard.dashboard_id}[data-dashboard-directory-lifecycle="archived"])
           )

    view
    |> element("#restore-dashboard-#{dashboard.dashboard_id}")
    |> render_click()

    refute has_element?(view, "#dashboard-directory-row-#{dashboard.dashboard_id}")

    assert [%{dashboard_id: restored_id}] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert restored_id == dashboard.dashboard_id
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "dashboard-directory",
        display_name: "Dashboard Directory"
      )

    {TestFixtures.member_conn(user), user, org, mission}
  end
end
