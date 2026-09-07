defmodule CadenceWeb.CommsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "authenticated Comms overview mounts the federated mission surface" do
    {conn, _organization, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

    assert_surface(view, "comms-overview-component", "overview", mission, %{})
  end

  test "authenticated Comms validation mounts the federated mission surface" do
    {conn, _organization, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/validation")

    assert_surface(view, "comms-validation-component", "validation", mission, %{})
  end

  test "Comms routes redirect unauthenticated users to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, "/missions/mission-test/comms")
  end

  test "Comms routes redirect members without organization access" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(organization)

    assert {:error, {:redirect, %{to: "/no-organization"}}} =
             live(TestFixtures.member_conn(user), ~p"/missions/#{mission.mission_id}/comms")
  end

  test "Comms routes redirect when the mission is outside the current organization" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    other_organization = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(other_organization)

    assert {:error, {:redirect, %{to: "/missions"}}} =
             live(TestFixtures.member_conn(user), ~p"/missions/#{mission.mission_id}/comms")
  end

  defp assert_surface(view, _id, surface_id, mission, query_params) do
    HostTransportTestSupport.assert_context(view, %{
      "application_key" => "comms",
      "surface_id" => surface_id,
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => query_params
    })
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)

    {TestFixtures.member_conn(user), organization, mission}
  end
end
