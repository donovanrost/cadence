defmodule CadenceWeb.OpsNavigationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  test "Explore mounts a compiled contribution and preserves admitted query context" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/explore?point_id=HK.temp&logical_source=operational_observables&time_mode=last_1h"
      )

    snapshot = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]
    page = snapshot["ops_page"]
    assert page["id"] == "dashboards.exploration"
    assert page["context"]["missionId"] == mission.mission_id
    assert page["status"] == "ready"
    assert page["data"]["status"] == "unsupported_exploration_source"

    assert page["data"]["query"] == %{
             "point_id" => "HK.temp",
             "logical_source" => "operational_observables",
             "time_mode" => "last_1h"
           }

    assert has_element?(view, "#application-shell")
  end

  test "Explore without a point renders a query-ready state rather than fake empty results" do
    {conn, mission} = signed_in()
    {:ok, view, _} = live(conn, ~p"/missions/#{mission.mission_id}/ops/explore")
    page = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
    assert page["status"] == "ready"
    assert page["data"]["status"] == "point_required"
  end

  test "unknown Explore selectors are contained rather than silently removed" do
    {conn, mission} = signed_in()
    {:ok, view, _} = live(conn, ~p"/missions/#{mission.mission_id}/ops/explore?ignored=stale")
    page = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
    assert page["status"] == "unavailable"
    refute Map.has_key?(page, "data")
    assert has_element?(view, "#application-shell")
  end

  test "Explore remains authentication scoped" do
    {_conn, _user, _organization, mission} = signed_in_user_org_and_mission()

    assert {:error, {:redirect, %{to: "/console/sign-in"}}} =
             live(build_conn(), ~p"/missions/#{mission.mission_id}/ops/explore")
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
end
