defmodule CadenceWeb.OpsDataSourcesByoLifecycleLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "BYO registration uses the native source contribution" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources/registration/new")

    assert_surface(view, "ops-data-sources-component", "data_source_registration", mission, %{})
  end

  defp signed_in do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization, role: :organization_admin)
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
