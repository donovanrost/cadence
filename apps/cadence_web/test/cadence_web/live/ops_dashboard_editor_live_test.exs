defmodule CadenceWeb.OpsDashboardEditorLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "dashboard editor forwards only the dashboard subject" do
    {conn, mission} = signed_in()
    dashboard_id = "dashboard-1"

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard_id}/edit?stale=ignored"
      )

    assert_surface(view, "ops-dashboard-editor-surface", "dashboard_editor", mission, %{
      "dashboard_id" => dashboard_id
    })
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
