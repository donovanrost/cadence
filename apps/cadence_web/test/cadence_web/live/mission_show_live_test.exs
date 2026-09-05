defmodule CadenceWeb.MissionShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "authenticated mission members mount the mission overview surface" do
    {conn, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}")

    assert has_element?(view, "#mission-overview-page")

    assert_surface(view, "mission-overview-component", "mission_overview", mission, %{})
  end

  test "unknown mission ids redirect to the mission list" do
    {conn, _organization} = signed_in_org()

    assert {:error, {:redirect, %{to: "/missions"}}} =
             live(conn, ~p"/missions/mission_unknown")
  end

  test "unauthenticated requests redirect to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, ~p"/missions/mission-test")
  end

  defp signed_in_org_and_mission do
    {conn, organization} = signed_in_org()
    mission = TestFixtures.persist_mission!(organization)
    {conn, mission}
  end

  defp signed_in_org do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    {TestFixtures.member_conn(user), organization}
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}")

    vue = Test.get_vue(view, id: id)

    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == "space-y-6"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "mission_catalog",
             "surface_id" => surface_id,
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params
           }
  end
end
