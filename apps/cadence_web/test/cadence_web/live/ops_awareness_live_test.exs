defmodule CadenceWeb.OpsAwarenessLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  test "alarms mount as the mission-scoped module contribution" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/alarms?state=nominal&ignored=stale")

    assert_surface(view, "ops-alarms-component", "alarms", mission, %{"state" => "nominal"})
  end

  test "alarms preserve bounded URL filters in the contributed read" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/alarms?severity=critical&state=active&spacecraft_id=mission&query=thermal&ignored=stale"
      )

    assert_surface(view, "ops-alarms-component", "alarms", mission, %{
      "severity" => "critical",
      "state" => "active",
      "spacecraft_id" => "mission",
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

  defp assert_surface(view, _id, _surface_id, mission, query_params) do
    snapshot = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]
    assert snapshot["ops_page"]["id"] == "limits.alarm-conditions"
    assert snapshot["ops_page"]["status"] == "ready"
    assert snapshot["ops_page"]["context"]["missionId"] == mission.mission_id
    assert Map.take(snapshot["ops_page"]["data"]["query"], Map.keys(query_params)) == query_params
  end
end
