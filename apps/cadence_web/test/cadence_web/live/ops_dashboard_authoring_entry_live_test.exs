defmodule CadenceWeb.OpsDashboardAuthoringEntryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "dashboard directory and creation mount their host contributions" do
    {conn, mission} = signed_in()

    {:ok, directory, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")

    HostTransportTestSupport.assert_context(directory, %{
      "application_key" => nil,
      "surface_id" => nil,
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => %{}
    })

    page = LiveVue.Test.get_vue(directory, id: "application-shell").props["snapshot"]["ops_page"]
    assert page["id"] == "dashboards.directory"
    assert page["slot"] == "ops.page"
    assert page["status"] == "ready"

    {:ok, new_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/new")

    HostTransportTestSupport.assert_context(new_view, %{
      "application_key" => nil,
      "surface_id" => nil,
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => %{}
    })

    creation =
      LiveVue.Test.get_vue(new_view, id: "application-shell").props["snapshot"]["ops_page"]

    assert creation["id"] == "dashboards.creation"
    assert creation["slot"] == "ops.page"
    assert creation["status"] == "ready"
  end

  defp signed_in do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end
end
