defmodule CadenceWeb.OpsDataOperationsHandoffLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.OpsConsole
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "reader route ignores unowned dashboard context" do
    {conn, mission} = signed_in(:member)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-operations?dashboard_id=dashboard-1&point_id=HK.temp"
      )

    assert_surface(view, "ops-data-operations-component", "data_operations", mission, %{})
  end

  test "management route forwards only the selected group" do
    {conn, mission} = signed_in(:organization_admin)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-operations/manage?group=group-alpha&point_id=ignored"
      )

    assert_surface(view, "ops-data-operations-component", "data_operations_manage", mission, %{
      "group" => "group-alpha"
    })
  end

  test "management route remains administrator scoped" do
    {conn, mission} = signed_in(:member)

    assert {:error, {:redirect, %{to: "/"}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/ops/data-operations/manage")
  end

  test "data operations retain bounded reader and management contracts" do
    assert {:ok, %{subject_param: nil, query_params: []}} =
             OpsConsole.surface_query_contract("data_operations")

    assert {:ok, %{subject_param: nil, query_params: ["group"]}} =
             OpsConsole.surface_query_contract("data_operations_manage")
  end

  defp signed_in(role) do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization, role: role)
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
