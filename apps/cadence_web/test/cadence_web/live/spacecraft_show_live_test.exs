defmodule CadenceWeb.SpacecraftShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "authenticated show route mounts the core spacecraft feature" do
    {conn, mission, spacecraft} = signed_in_spacecraft()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

    assert_surface(view, mission, spacecraft)
  end

  test "out-of-scope spacecraft redirects to the mission inventory" do
    {conn, mission, _spacecraft} = signed_in_spacecraft()
    path = ~p"/missions/#{mission.mission_id}/spacecraft"

    assert {:error, {:redirect, %{to: ^path, flash: %{"error" => _message}}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/missing-spacecraft")
  end

  test "unauthenticated show requests redirect to sign in" do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), "/missions/mission-test/spacecraft/spacecraft-test")
  end

  defp assert_surface(view, mission, spacecraft) do
    HostTransportTestSupport.assert_context(view, %{
      "kind" => "spacecraft",
      "spacecraft_page" => "spacecraft_show",
      "host_scope" => "spacecraft",
      "mission_id" => mission.mission_id,
      "spacecraft_id" => spacecraft.spacecraft_id,
      "query_params" => %{}
    })
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
