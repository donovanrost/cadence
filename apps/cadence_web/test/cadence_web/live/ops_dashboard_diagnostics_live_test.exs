defmodule CadenceWeb.OpsDashboardDiagnosticsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  test "diagnostics mounts with the current dashboard subject" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Diagnostics")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/diagnostics"
      )

    assert_surface(
      view,
      "ops-dashboard-diagnostics-page-component",
      "dashboard_diagnostics",
      mission,
      %{"dashboard_id" => dashboard.dashboard_id}
    )
  end

  test "diagnostic access is isolated to the authenticated mission" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    dashboards_path = "/missions/#{mission.mission_id}/ops/dashboards"

    assert {:error, {:live_redirect, %{to: ^dashboards_path}}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/ops/dashboards/missing/diagnostics"
             )
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}.contents")
    vue = LiveVue.Test.get_vue(view, id: id)
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "ops_console",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params,
             "surface_id" => surface_id
           }
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-diagnostics")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
