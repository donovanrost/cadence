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

  test "dashboard context mounts the reader descriptor with exact bounded query params" do
    {conn, mission} = signed_in(:organization_admin)

    query = %{
      dashboard_id: "dashboard-1",
      dashboard_version: "3",
      dashboard_time_mode: "absolute",
      dashboard_data_view: "all_revisions",
      dashboard_limit_mode: "observed",
      realm: "flight",
      data_source_id: "flight-telemetry",
      source_binding_id: "flight-telemetry-binding",
      point_id: "HK.counter",
      point_ids: "HK.counter, HK.voltage",
      source_from: "2026-08-01T10:00:00Z",
      source_to: "2026-08-01T11:00:00Z"
    }

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/data-operations?#{query}")

    assert_surface(view, "ops-data-operations-component", "data_operations", mission, %{})
    refute has_element?(view, "#ops-data-operations-page")
  end

  test "management route carries only the selected group into the federated descriptor" do
    {conn, mission} = signed_in(:organization_admin)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/data-operations/manage?group=group-alpha")

    assert_surface(
      view,
      "ops-data-operations-component",
      "data_operations_manage",
      mission,
      %{}
    )

    render_hook(view, "validate_request", %{
      "historical_workflow_request" => %{"workflow" => "backfill", "confirmed" => "false"}
    })

    assert_surface(
      view,
      "ops-data-operations-component",
      "data_operations_manage",
      mission,
      %{}
    )
  end

  test "data operations descriptor declares the query provider and bounded manage query" do
    assert {:ok, %{subject_param: nil, query_params: []}} =
             OpsConsole.surface_query_contract("data_operations")

    assert {:ok, %{subject_param: nil, query_params: ["group"]}} =
             OpsConsole.surface_query_contract("data_operations_manage")
  end

  defp signed_in(role \\ :member) do
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

    assert vue.props == %{
             "application_key" => "ops_console",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params,
             "surface_id" => surface_id
           }
  end
end
