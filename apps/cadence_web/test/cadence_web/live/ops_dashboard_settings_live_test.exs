defmodule CadenceWeb.OpsDashboardSettingsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  test "dashboard settings forwards the current dashboard subject" do
    {conn, mission} = signed_in()
    dashboard_id = "dashboard-1"

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard_id}/settings")

    page = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
    assert page["id"] == "dashboards.settings"
    assert page["status"] == "unavailable"
    assert page["context"]["missionId"] == mission.mission_id
    assert page["context"]["resourceId"] == dashboard_id
  end

  defp signed_in do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end
end
