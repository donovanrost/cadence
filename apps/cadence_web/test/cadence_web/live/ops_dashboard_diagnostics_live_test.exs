defmodule CadenceWeb.OpsDashboardDiagnosticsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  test "diagnostics binds the dashboard subject and contains an unavailable publication" do
    {conn, mission} = signed_in()
    dashboard_id = "dashboard-1"

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard_id}/diagnostics")

    page = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
    assert page["id"] == "dashboards.execution-diagnostics"
    assert page["context"]["missionId"] == mission.mission_id
    assert page["context"]["resourceId"] == dashboard_id
    assert page["status"] == "unavailable"
    refute Map.has_key?(page, "data")
  end

  defp signed_in do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end
end
