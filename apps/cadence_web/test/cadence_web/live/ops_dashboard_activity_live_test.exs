defmodule CadenceWeb.OpsDashboardActivityLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "activity forwards only its bounded dashboard query" do
    {conn, mission} = signed_in()
    dashboard_id = "dashboard-1"

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard_id}/activity?version=2&selected_publish_issue=issue-1&stale=ignored"
      )

    assert_surface(view, "ops-dashboard-activity-surface", "dashboard_activity", mission, %{
      "dashboard_id" => dashboard_id,
      "version" => "2",
      "selected_publish_issue" => "issue-1"
    })
  end

  defp signed_in do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
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
