defmodule CadenceWeb.SpacecraftNewLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "authenticated new route mounts the host spacecraft form" do
    {conn, mission} = signed_in_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

    assert_surface(view, mission)
  end

  test "unauthenticated new requests redirect to sign in" do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), "/missions/mission-test/spacecraft/new")
  end

  defp assert_surface(view, mission) do
    HostTransportTestSupport.assert_context(view, %{
      "kind" => "spacecraft",
      "spacecraft_page" => "spacecraft_new",
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => %{}
    })
  end

  defp signed_in_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end
end
