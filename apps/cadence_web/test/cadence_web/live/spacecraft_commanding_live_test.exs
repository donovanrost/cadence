defmodule CadenceWeb.SpacecraftCommandingLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "authenticated command route mounts the federated spacecraft surface" do
    {conn, mission, spacecraft} = signed_in_spacecraft()

    {:ok, view, _html} = live(conn, commanding_path(mission, spacecraft))

    assert_surface(view, mission, spacecraft)
  end

  test "out-of-scope spacecraft redirects to the mission inventory" do
    {conn, mission, spacecraft} = signed_in_spacecraft()
    path = ~p"/missions/#{mission.mission_id}/spacecraft"

    assert {:error, {:redirect, %{to: ^path, flash: %{"error" => "Spacecraft not found."}}}} =
             live(conn, commanding_path(mission, spacecraft.spacecraft_id <> "-missing"))
  end

  test "unauthenticated command requests redirect to sign in" do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), "/missions/mission-test/spacecraft/spacecraft-test/commanding")
  end

  defp assert_surface(view, mission, spacecraft) do
    assert has_element?(view, "#spacecraft-commanding-component")

    vue = Test.get_vue(view, id: "spacecraft-commanding-component")
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == "spacecraft-commanding-component"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "spacecraft",
             "surface_id" => "commanding",
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

  defp commanding_path(mission, spacecraft_or_id) do
    spacecraft_id =
      case spacecraft_or_id do
        %{spacecraft_id: id} -> id
        id -> id
      end

    ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft_id}/commanding"
  end
end
