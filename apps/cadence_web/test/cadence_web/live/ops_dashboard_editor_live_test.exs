defmodule CadenceWeb.OpsDashboardEditorLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "dashboard editor binds its path subject without a remote application" do
    {conn, mission} = signed_in()
    dashboard_id = "dashboard-1"

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard_id}/edit?stale=ignored"
      )

    HostTransportTestSupport.assert_context(view, %{
      "application_key" => nil,
      "surface_id" => nil,
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => %{}
    })

    page = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
    assert page["id"] == "dashboards.workspace"
    assert page["context"]["resourceId"] == dashboard_id
    assert page["status"] == "unavailable"
  end

  test "dashboard editor remains authentication scoped" do
    {_conn, _user, _organization, mission} = signed_in_user_org_and_mission()

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(
               build_conn(),
               ~p"/missions/#{mission.mission_id}/ops/dashboards/dashboard-1/edit"
             )
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
