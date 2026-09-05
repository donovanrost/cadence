defmodule CadenceWeb.OpsDashboardDirectoryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  test "authenticated mission members mount the descriptor-only dashboard directory" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")

    assert_surface(view, "ops-dashboard-directory-component", "dashboard_directory", mission, %{})
    assert has_element?(view, "#ops-context-rail-component")
    refute has_element?(view, "#ops-dashboards-page")
  end

  test "directory remains mission-scoped when URL filters are supplied" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards?query=thermal&tag=flight")

    assert_surface(view, "ops-dashboard-directory-component", "dashboard_directory", mission, %{})
  end

  test "unauthenticated directory access redirects to authentication" do
    {_conn, _user, _org, mission} = signed_in_user_org_and_mission()

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), ~p"/missions/#{mission.mission_id}/ops/dashboards")
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}.contents")

    vue = LiveVue.Test.get_vue(view, id: id)

    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert vue.slots == %{}

    assert vue.props == %{
             "application_key" => "ops_console",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params,
             "surface_id" => surface_id
           }
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-directory")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
