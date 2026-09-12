defmodule CadenceWeb.OpsDashboardDirectoryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "dashboard directory owns URL filters and mounts its host contribution" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards?query=thermal&tag=flight")

    HostTransportTestSupport.assert_context(view, %{
      "application_key" => nil,
      "surface_id" => nil,
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => %{"query" => "thermal", "tag" => "flight"}
    })

    page = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
    assert page["id"] == "dashboards.directory"
    assert page["status"] == "ready"

    {:ok, viewer, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/dashboard-1")

    HostTransportTestSupport.assert_context(viewer, %{
      "application_key" => nil,
      "surface_id" => nil,
      "kind" => "ops_module",
      "contribution" => "dashboards.workspace",
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => %{"dashboard_id" => "dashboard-1"}
    })

    viewer_page =
      LiveVue.Test.get_vue(viewer, id: "application-shell").props["snapshot"]["ops_page"]

    assert viewer_page["id"] == "dashboards.workspace"
    assert viewer_page["context"]["resourceId"] == "dashboard-1"
    assert viewer_page["status"] == "unavailable"
  end

  test "dashboard directory remains authentication scoped" do
    {_conn, _user, _organization, mission} = signed_in_user_org_and_mission()

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), ~p"/missions/#{mission.mission_id}/ops/dashboards")
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
