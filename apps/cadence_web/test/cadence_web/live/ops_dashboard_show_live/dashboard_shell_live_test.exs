defmodule CadenceWeb.OpsDashboardShowLive.DashboardShellLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp signed_in_org_and_mission do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    {conn, org, mission}
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  describe "ops landing" do
    test "shows the empty state, creates a dashboard, and lands on the console" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")
      assert has_element?(view, "#ops-dashboards-page")
      assert has_element?(view, "#dashboard-directory-empty")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/new")

      view
      |> form("#dashboard-form", dashboard: %{name: "Power Overview", description: "EPS"})
      |> render_submit()

      assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 mission.organization_id,
                 mission.mission_id
               )

      assert summary.name == "Power Overview"
      assert summary.widget_count == 0

      assert {:ok, document} =
               Cadence.Dashboards.fetch_document(
                 mission.organization_id,
                 mission.mission_id,
                 summary.dashboard_id
               )

      assert document.name == "Power Overview"
      assert document.placements == []
      assert_redirect(view, show_path(mission, summary) <> "/edit")
    end

    test "lists dashboards as navigation cards and in the rail" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Thermal")

      assert {:ok, _preference} =
               Cadence.Dashboards.set_dashboard_starred(
                 org.organization_id,
                 mission.mission_id,
                 user.user_id,
                 dashboard.dashboard_id,
                 true
               )

      {:ok, view, html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")

      assert has_element?(
               view,
               ~s(#ops-dashboards-page a[href="#{show_path(mission, dashboard)}"])
             )

      assert has_element?(view, ~s(#ops-nav-rail a[href="#{show_path(mission, dashboard)}"]))
      assert html =~ "Thermal"
      assert html =~ "0 widgets"
      assert has_element?(view, "#ops-utc-clock")
    end

    test "the shared Ops shell renders exactly one context rail across representative routes" do
      {conn, _org, mission} = signed_in_org_and_mission()

      paths = [
        ~p"/missions/#{mission.mission_id}/ops/dashboards",
        ~p"/missions/#{mission.mission_id}/ops/planning",
        ~p"/missions/#{mission.mission_id}/ops/contacts",
        ~p"/missions/#{mission.mission_id}/ops/data-sources"
      ]

      for path <- paths do
        {:ok, view, _html} = live(conn, path)
        document = view |> render() |> LazyHTML.from_fragment()

        assert ["ops-context-rail"] =
                 document
                 |> LazyHTML.query("#ops-context-rail")
                 |> LazyHTML.attribute("id")

        assert ["cadence-ops-context-rail"] =
                 document
                 |> LazyHTML.query("#ops-context-rail")
                 |> LazyHTML.attribute("data-storage-key")

        assert ["alarms", "commands", "fleet_health"] =
                 document
                 |> LazyHTML.query("[data-ops-context-collapsed-section]")
                 |> LazyHTML.attribute("data-ops-context-collapsed-section")
      end
    end
  end
end
