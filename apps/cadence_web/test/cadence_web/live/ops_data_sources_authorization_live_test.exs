defmodule CadenceWeb.OpsDataSourcesAuthorizationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.OpsConsole
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "ordinary operators can inspect the reader surface but not administrator routes" do
    {conn, mission} = signed_in(:member)
    {:ok, inventory, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources")

    assert_surface(inventory, "ops-data-sources-component", "data_sources", mission, %{})

    assert {:error, {:redirect, %{to: "/"}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources/registration/new")

    assert {:error, {:redirect, %{to: "/"}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources/source-1/settings")
  end

  test "organization administrators receive distinct registration and subject descriptors" do
    {conn, mission} = signed_in(:organization_admin)

    {:ok, registration, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources/registration/new")

    assert_surface(
      registration,
      "ops-data-sources-component",
      "data_source_registration",
      mission,
      %{}
    )

    {:ok, settings, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources/source-1/settings")

    assert_surface(
      settings,
      "ops-data-sources-component",
      "data_source_settings",
      mission,
      %{"data_source_id" => "source-1"}
    )
  end

  test "data source descriptors declare exact subject and query contracts" do
    assert {:ok, %{subject_param: nil, query_params: []}} =
             OpsConsole.surface_query_contract("data_source_registration")

    assert {:ok, %{subject_param: "data_source_id", query_params: ["data_source_id"]}} =
             OpsConsole.surface_query_contract("data_source_settings")
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

    assert vue.props == %{
             "application_key" => "ops_console",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params,
             "surface_id" => surface_id
           }
  end
end
