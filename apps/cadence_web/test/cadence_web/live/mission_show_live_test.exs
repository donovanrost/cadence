defmodule CadenceWeb.MissionShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "authenticated mission members mount the core mission overview" do
    {conn, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}")

    snapshot =
      HostTransportTestSupport.assert_context(view, %{
        "application_key" => nil,
        "surface_id" => nil,
        "kind" => "mission",
        "mission_page" => "mission_overview",
        "host_scope" => "mission",
        "mission_id" => mission.mission_id,
        "query_params" => %{}
      })

    assert %{"page" => "mission_overview", "version" => 1, "status" => "ready"} =
             snapshot["mission_page"]
  end

  # L4 (f2e4f172d): the legacy mission list is gone, so an unknown mission goes to the console's.
  test "unknown mission ids redirect to the console's mission list" do
    {conn, organization} = signed_in_org()
    missions = CadenceWeb.ConsolePaths.organization(organization.organization_id, "/org/missions")

    assert {:error, {:redirect, %{to: ^missions, flash: %{"error" => "Mission not found."}}}} =
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
end
