defmodule CadenceWeb.SpacecraftApplicationsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "authenticated inventory mounts the federated spacecraft applications surface" do
    {conn, mission, spacecraft} = signed_in_spacecraft()

    {:ok, view, _html} = live(conn, inventory_path(mission, spacecraft))

    assert_surface(view, mission, spacecraft)
  end

  test "missing spacecraft redirects to the mission inventory" do
    {conn, mission, _spacecraft} = signed_in_spacecraft()
    path = ~p"/missions/#{mission.mission_id}/spacecraft"

    assert {:error, {:redirect, %{to: ^path, flash: flash}}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/spacecraft/missing-spacecraft/applications"
             )

    assert flash["error"] == "Spacecraft not found."
  end

  test "unauthenticated inventory requests redirect to sign in" do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), "/missions/mission-test/spacecraft/spacecraft-test/applications")
  end

  defp assert_surface(view, mission, spacecraft) do
    assert has_element?(view, "#spacecraft-applications-page-component.contents")

    vue = Test.get_vue(view, id: "spacecraft-applications-page-component")
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == "spacecraft-applications-page-component"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "spacecraft",
             "surface_id" => "applications",
             "host_scope" => "spacecraft",
             "mission_id" => mission.mission_id,
             "spacecraft_id" => spacecraft.spacecraft_id,
             "query_params" => %{}
           }
  end

  defp signed_in_spacecraft do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")
    {TestFixtures.member_conn(user), mission, spacecraft}
  end

  defp inventory_path(mission, spacecraft) do
    ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
  end
end
