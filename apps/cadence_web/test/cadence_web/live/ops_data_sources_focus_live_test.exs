defmodule CadenceWeb.OpsDataSourcesFocusLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "source focus remains bounded to the source subject" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources?data_source_id=focus-source&selected_target=transport&selected_id=transport-1"
      )

    assert_surface(view, "ops-data-sources-component", "data_sources", mission, %{
      "data_source_id" => "focus-source"
    })
  end

  test "source settings forward their exact path subject" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/focus-source/settings?selected_target=transport"
      )

    assert_surface(view, "ops-data-sources-component", "data_source_settings", mission, %{
      "data_source_id" => "focus-source"
    })
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
