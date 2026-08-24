defmodule CadenceWeb.OpsNavigationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.OpsNavTestSupport
  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  test "groups Ops navigation and gives Explore its own active canonical route" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/explore")

    nav = ops_nav_vue(view)

    assert nav.props["groups"] == expected_groups(mission, :explore)
    assert nav.props["dashboard_groups"] == []
    assert nav.props["empty_state"] == "Star dashboards or open one to keep it close."

    assert nav.props["new_dashboard"] == %{
             "href" => "/missions/#{mission.mission_id}/ops/dashboards/new",
             "icon" => "hero-plus",
             "label" => "New Dashboard",
             "title" => "New dashboard"
           }

    refute has_element?(view, "#ops-application-dock")
    assert ops_nav_item(nav, "explore")["active"]
    refute ops_nav_item(nav, "dashboards")["active"]
    refute ops_nav_item(nav, "approvals")
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
    nav = ops_nav_vue(view)

    assert 5 ==
             nav
             |> ops_dashboard_nav_group("starred")
             |> then(& &1["items"])
             |> length()

    assert 5 ==
             nav
             |> ops_dashboard_nav_group("recent")
             |> then(& &1["items"])
             |> length()
  end

  test "authorization projects Approvals into the server-owned navigation DTO" do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org, slug: "ops-nav-admin", display_name: "Ops Nav")

    {:ok, view, _html} =
      live(TestFixtures.member_conn(user), ~p"/missions/#{mission.mission_id}/ops/explore")

    assert ops_nav_item(ops_nav_vue(view), "approvals") == %{
             "active" => false,
             "href" => "/missions/#{mission.mission_id}/ops/activations",
             "icon" => "hero-shield-check",
             "key" => "approvals",
             "label" => "Approvals"
           }
  end

  defp expected_groups(mission, active_item) do
    [
      %{
        "key" => "observe",
        "label" => "Observe",
        "class" => "px-2 pt-2 space-y-0.5",
        "items" => [
          expected_item(
            mission,
            :dashboards,
            "Dashboards",
            "hero-squares-2x2",
            "dashboards",
            active_item
          ),
          expected_item(
            mission,
            :explore,
            "Explore",
            "hero-magnifying-glass",
            "explore",
            active_item
          ),
          expected_item(mission, :alarms, "Alarms", "hero-bell-alert", "alarms", active_item),
          expected_item(mission, :timeline, "Timeline", "hero-clock", "timeline", active_item)
        ]
      },
      %{
        "key" => "act",
        "label" => "Act",
        "class" => "mt-3 border-t border-primary/20 px-2 pt-2 space-y-0.5",
        "items" => [
          expected_item(
            mission,
            :commands,
            "Commands",
            "hero-command-line",
            "commands",
            active_item
          )
        ]
      },
      %{
        "key" => "plan",
        "label" => "Plan",
        "class" => "mt-3 border-t border-primary/20 px-2 pt-2 space-y-0.5",
        "items" => [
          expected_item(
            mission,
            :planning,
            "Planning",
            "hero-chart-bar-square",
            "planning",
            active_item
          ),
          expected_item(
            mission,
            :requirements,
            "Requirements",
            "hero-clipboard-document-list",
            "requirements",
            active_item
          ),
          expected_item(
            mission,
            :contacts,
            "Contacts",
            "hero-calendar-days",
            "contacts",
            active_item
          )
        ]
      },
      %{
        "key" => "system",
        "label" => "System",
        "class" => "mt-3 border-t border-primary/20 px-2 pt-2 space-y-0.5",
        "items" => [
          expected_item(
            mission,
            :data_sources,
            "Data Sources",
            "hero-circle-stack",
            "data-sources",
            active_item
          ),
          expected_item(
            mission,
            :data_operations,
            "Data Operations",
            "hero-arrow-path-rounded-square",
            "data-operations",
            active_item
          )
        ]
      }
    ]
  end

  defp expected_item(mission, item, label, icon, path, active_item) do
    %{
      "key" => label |> String.downcase() |> String.replace(" ", "_"),
      "label" => label,
      "icon" => icon,
      "href" => "/missions/#{mission.mission_id}/ops/#{path}",
      "active" => item == active_item
    }
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops-nav", display_name: "Ops Nav")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
