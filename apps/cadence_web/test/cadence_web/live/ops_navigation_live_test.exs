defmodule CadenceWeb.OpsNavigationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "Explore mounts a compiled contribution and preserves admitted query context" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/explore?point_id=HK.temp&logical_source=operational_observables&time_mode=last_1h"
      )

    snapshot = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]
    page = snapshot["ops_page"]
    assert page["id"] == "dashboards.exploration"
    assert page["context"]["missionId"] == mission.mission_id
    assert page["status"] == "ready"
    assert page["data"]["status"] == "unsupported_exploration_source"

    assert page["data"]["query"] == %{
             "point_id" => "HK.temp",
             "logical_source" => "operational_observables",
             "time_mode" => "last_1h"
           }

    assert has_element?(view, "#application-shell")
  end

  test "Explore without a point renders a query-ready state rather than fake empty results" do
    {conn, mission} = signed_in()
    {:ok, view, _} = live(conn, ~p"/missions/#{mission.mission_id}/ops/explore")
    page = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
    assert page["status"] == "ready"
    assert page["data"]["status"] == "point_required"
  end

  test "unknown Explore selectors are contained rather than silently removed" do
    {conn, mission} = signed_in()
    {:ok, view, _} = live(conn, ~p"/missions/#{mission.mission_id}/ops/explore?ignored=stale")
    page = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
    assert page["status"] == "unavailable"
    refute Map.has_key?(page, "data")
    assert has_element?(view, "#application-shell")
  end

  test "unknown Commands selectors are contained rather than silently removed" do
    {conn, mission} = signed_in()
    {:ok, view, _} = live(conn, ~p"/missions/#{mission.mission_id}/ops/commands?ignored=stale")
    page = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
    assert page["status"] == "unavailable"
    refute Map.has_key?(page, "data")
    assert has_element?(view, "#application-shell")
  end

  test "Commands mount the mission-scoped compiled contribution" do
    {conn, mission} = signed_in()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/commands")

    assert_surface(view, "ops-commands-component", "commands", mission, %{})
  end

  test "Commands retain their admitted URL query in the compiled contribution" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/commands?status=queued&target=sc-1&query=deploy&focus_command_id=cmd-1"
      )

    assert_surface(view, "ops-commands-component", "commands", mission, %{
      "status" => "queued",
      "target" => "sc-1",
      "query" => "deploy",
      "focus_command_id" => "cmd-1"
    })
  end

  test "legacy Explore bookmarks retain their complete query string" do
    {conn, mission} = signed_in()

    conn =
      get(
        conn,
        "/missions/#{mission.mission_id}/ops/telemetry/explore?point_id=HK.temp&time_mode=historical&from=2026-08-01T12%3A00%3A00Z"
      )

    assert conn.status == 301

    assert get_resp_header(conn, "location") == [
             "/missions/#{mission.mission_id}/ops/explore?point_id=HK.temp&time_mode=historical&from=2026-08-01T12%3A00%3A00Z"
           ]
  end

  test "Explore remains authentication scoped" do
    {_conn, _user, _organization, mission} = signed_in_user_org_and_mission()

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), ~p"/missions/#{mission.mission_id}/ops/explore")
  end

  defp signed_in do
    {conn, _user, _organization, mission} = signed_in_user_org_and_mission()
    {conn, mission}
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), user, organization, mission}
  end

  defp assert_surface(view, _id, "commands", mission, query_params) do
    snapshot =
      HostTransportTestSupport.assert_context(view, %{
        "kind" => "ops_module",
        "contribution" => "commanding.monitor",
        "host_scope" => "mission",
        "mission_id" => mission.mission_id,
        "query_params" => query_params
      })

    assert snapshot["ops_page"]["id"] == "commanding.monitor"
    assert snapshot["ops_page"]["status"] == "ready"

    assert snapshot["ops_page"]["data"]["query"] ==
             Map.merge(
               %{"status" => "all", "target" => "all", "query" => "", "page" => "1"},
               query_params
             )
  end
end
