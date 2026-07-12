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
      assert render(view) =~ "No dashboards"

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
      assert_redirect(view, show_path(mission, summary))
    end

    test "lists dashboards as navigation cards and in the rail" do
      {conn, _org, mission} = signed_in_org_and_mission()
      dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Thermal")

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

    test "requires a signed-in member" do
      {_conn, _org, mission} = signed_in_org_and_mission()

      assert {:error, {:redirect, %{to: to}}} =
               live(
                 Phoenix.ConnTest.build_conn(),
                 ~p"/missions/#{mission.mission_id}/ops/dashboards"
               )

      assert to =~ "/sign-in"
    end
  end
end
