defmodule CadenceWeb.OpsDataSourcesAuthorizationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.OpsConsole
  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "members can inspect sources but not administrator routes" do
    {conn, mission} = signed_in(:member)

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources")
    assert_surface(view, "ops-data-sources-component", "data_sources", mission, %{})

    assert {:error, {:redirect, %{to: "/"}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources/registration/new")

    assert {:error, {:redirect, %{to: "/"}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources/source-1/settings")
  end

  test "administrators receive exact registration and settings subjects" do
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

    assert_surface(settings, "ops-data-sources-component", "data_source_settings", mission, %{
      "data_source_id" => "source-1"
    })
  end

  test "data-source query contracts keep registration unscoped and settings source-scoped" do
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

  defp assert_surface(view, _id, surface_id, mission, query_params) do
    contribution =
      case surface_id do
        "data_sources" -> "data-operations.sources"
        "data_source_registration" -> "data-operations.source-registration"
        "data_source_settings" -> "data-operations.source-settings"
      end

    snapshot =
      HostTransportTestSupport.assert_context(view, %{
        "kind" => "ops_module",
        "contribution" => contribution,
        "host_scope" => "mission",
        "mission_id" => mission.mission_id,
        "query_params" => query_params
      })

    assert snapshot["ops_page"]["id"] == contribution
  end
end
