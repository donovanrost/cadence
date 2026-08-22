defmodule CadenceWeb.OpsNavigationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  test "groups Ops navigation and gives Explore its own active canonical route" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/explore")

    for group <- ~w(observe act plan system) do
      assert has_element?(view, ~s([data-ops-nav-group="#{group}"]))
    end

    refute has_element?(view, "#ops-application-dock")

    assert has_element?(
             view,
             ~s([data-ops-nav-item="explore"][href="/missions/#{mission.mission_id}/ops/explore"])
           )
  end

  test "legacy Explore bookmarks preserve their complete query string" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()

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

  test "navigation exposes no more than five starred and five recent dashboards" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    observed_at = ~U[2026-08-01 12:00:00Z]

    dashboards =
      for index <- 1..12 do
        TestFixtures.persist_dashboard_document!(mission, name: "Dashboard #{index}")
      end

    dashboards
    |> Enum.take(6)
    |> Enum.each(fn dashboard ->
      assert {:ok, _preference} =
               Cadence.Dashboards.set_dashboard_starred(
                 org.organization_id,
                 mission.mission_id,
                 user.user_id,
                 dashboard.dashboard_id,
                 true,
                 observed_at: observed_at
               )
    end)

    dashboards
    |> Enum.drop(6)
    |> Enum.with_index()
    |> Enum.each(fn {dashboard, index} ->
      assert {:ok, _preference} =
               Cadence.Dashboards.record_dashboard_view(
                 org.organization_id,
                 mission.mission_id,
                 user.user_id,
                 dashboard.dashboard_id,
                 observed_at: DateTime.add(observed_at, index, :second)
               )
    end)

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")
    document = view |> render() |> LazyHTML.from_fragment()

    assert 5 ==
             document
             |> LazyHTML.query(
               ~s([data-ops-dashboard-nav-group="starred"] [data-ops-dashboard-nav-item])
             )
             |> LazyHTML.attribute("data-ops-dashboard-nav-item")
             |> length()

    assert 5 ==
             document
             |> LazyHTML.query(
               ~s([data-ops-dashboard-nav-group="recent"] [data-ops-dashboard-nav-item])
             )
             |> LazyHTML.attribute("data-ops-dashboard-nav-item")
             |> length()
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops-nav", display_name: "Ops Nav")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
