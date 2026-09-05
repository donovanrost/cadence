defmodule CadenceWeb.SpacecraftEditLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "authenticated edit and identity routes mount the federated spacecraft surface" do
    {conn, mission, spacecraft} = signed_in_spacecraft()

    for path <- [
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/edit",
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"
        ] do
      {:ok, view, _html} = live(conn, path)
      assert_surface(view, mission, spacecraft)
    end
  end

  test "missing spacecraft redirects to the mission inventory" do
    {conn, mission, _spacecraft} = signed_in_spacecraft()
    path = ~p"/missions/#{mission.mission_id}/spacecraft"

    assert {:error, {:redirect, %{to: ^path, flash: %{"error" => "Spacecraft not found."}}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/missing-spacecraft/edit")
  end

  test "unauthenticated edit requests redirect to sign in" do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), "/missions/mission-test/spacecraft/spacecraft-test/edit")
  end

  defp assert_surface(view, mission, spacecraft) do
    assert has_element?(view, "#spacecraft-edit-component")

    vue = Test.get_vue(view, id: "spacecraft-edit-component")
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == "spacecraft-edit-component"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "spacecraft",
             "surface_id" => "edit",
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
end
