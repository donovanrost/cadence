defmodule CadenceWeb.OpsAwarenessLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "alarms mount as the mission-scoped federated surface" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/alarms?state=nominal&ignored=stale")

    assert_surface(view, "ops-alarms-component", "alarms", mission, %{"state" => "nominal"})
  end

  test "alarms forward their bounded URL query state to the federated surface" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/alarms?severity=critical&state=active&spacecraft_id=sc-1&query=thermal&ignored=stale"
      )

    assert_surface(view, "ops-alarms-component", "alarms", mission, %{
      "severity" => "critical",
      "state" => "active",
      "spacecraft_id" => "sc-1",
      "query" => "thermal"
    })
  end

  test "alarms remain authentication scoped" do
    {_conn, _user, _organization, mission} = signed_in_user_org_and_mission()

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), ~p"/missions/#{mission.mission_id}/ops/alarms")
  end

  defp signed_in do
    {conn, _user, _organization, mission} = signed_in_user_org_and_mission()
    {conn, mission}
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), user, organization, mission}
  end

  defp assert_surface(view, _id, surface_id, mission, query_params) do
    HostTransportTestSupport.assert_context(view, %{
      "application_key" => "ops_console",
      "surface_id" => surface_id,
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => query_params
    })
  end
end
