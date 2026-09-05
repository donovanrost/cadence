defmodule CadenceWeb.OpsDashboardAuthoringEntryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "dashboard directory and new routes mount their federated surfaces" do
    {conn, mission} = signed_in()

    {:ok, directory, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")

    assert_surface(
      directory,
      "ops-dashboard-directory-component",
      "dashboard_directory",
      mission,
      %{}
    )

    {:ok, new_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/new")
    assert_surface(new_view, "ops-dashboard-new-component", "dashboard_new", mission, %{})
  end

  defp signed_in do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}.contents")
    vue = Test.get_vue(view, id: id)

    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert vue.slots == %{}

    assert vue.props == %{
             "application_key" => "ops_console",
             "surface_id" => surface_id,
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params
           }
  end
end
