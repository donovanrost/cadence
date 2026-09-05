defmodule CadenceWeb.SpacecraftNewLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "authenticated new route mounts the federated mission surface" do
    {conn, mission} = signed_in_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

    assert_surface(view, mission)
  end

  test "unauthenticated new requests redirect to sign in" do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), "/missions/mission-test/spacecraft/new")
  end

  defp assert_surface(view, mission) do
    assert has_element?(view, "#spacecraft-new-component")

    vue = Test.get_vue(view, id: "spacecraft-new-component")
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == "spacecraft-new-component"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "spacecraft",
             "surface_id" => "new",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => %{}
           }
  end

  defp signed_in_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end
end
