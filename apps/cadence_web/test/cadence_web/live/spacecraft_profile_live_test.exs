defmodule CadenceWeb.SpacecraftProfileLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "authenticated profile list mounts the host profile directory" do
    {conn, mission} = signed_in_mission()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles")

    assert_surface(view, "spacecraft-type-list-page-component", "profile_list", mission, %{})
  end

  test "authenticated profile new mounts the host profile creation slice" do
    {conn, mission} = signed_in_mission()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles/new")

    assert_surface(view, "spacecraft-profile-new-component", "profile_new", mission, %{})
  end

  test "profile show forwards only its bounded profile query" do
    {conn, mission} = signed_in_mission()
    profile_id = "profile-test"

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles/#{profile_id}")

    assert_surface(view, "spacecraft-profile-show-component", "profile_show", mission, %{
      "profile_id" => profile_id
    })
  end

  test "unauthenticated profile requests redirect to sign in" do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), "/missions/mission-test/spacecraft/profiles/profile-test")
  end

  defp assert_surface(view, _id, surface_id, mission, query_params) do
    ownership = %{"kind" => "spacecraft", "spacecraft_page" => surface_id}

    HostTransportTestSupport.assert_context(
      view,
      Map.merge(ownership, %{
        "host_scope" => "mission",
        "mission_id" => mission.mission_id,
        "query_params" => query_params
      })
    )
  end

  defp signed_in_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end
end
