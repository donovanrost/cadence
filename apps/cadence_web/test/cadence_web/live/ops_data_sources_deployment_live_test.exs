defmodule CadenceWeb.OpsDataSourcesDeploymentLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.OpsConsole
  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "deployment routes preserve the source subject contract" do
    {conn, mission} = signed_in()

    {:ok, inventory, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources")
    assert_surface(inventory, "ops-data-sources-component", "data_sources", mission, %{})

    {:ok, settings, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources/deployment-source/settings")

    assert_surface(settings, "ops-data-sources-component", "data_source_settings", mission, %{
      "data_source_id" => "deployment-source"
    })
  end

  test "deployment source contracts remain owned by the Ops provider" do
    assert {:ok, %{subject_param: "data_source_id", query_params: ["data_source_id"]}} =
             OpsConsole.surface_query_contract("data_source_settings")

    assert Enum.all?(OpsConsole.surface_query_contributions(), fn contribution ->
             contribution.provider == Cadence.Reads.ApplicationSurfaces.OpsConsole
           end)
  end

  defp signed_in do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization, role: :organization_admin)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
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
