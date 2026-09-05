defmodule CadenceWeb.OpsNavigationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "Explore forwards its bounded telemetry query contract" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/explore?point_id=HK.temp&time_mode=historical&from=2026-08-01T12%3A00%3A00Z&ignored=stale"
      )

    assert_surface(view, "ops-telemetry-explore-component", "telemetry_explore", mission, %{
      "point_id" => "HK.temp",
      "time_mode" => "historical",
      "from" => "2026-08-01T12:00:00Z"
    })
  end

  test "Commands mount the mission-scoped federated surface" do
    {conn, mission} = signed_in()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/commands")

    assert_surface(view, "ops-commands-component", "commands", mission, %{})
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
