defmodule CadenceWeb.OpsDashboardShowLive.DashboardShellLiveTest do
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.OpsNavTestSupport
  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveView.JS

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
      directory_vue = dashboard_directory_vue(view)
      assert directory_vue.props["page"]["id"] == "ops-dashboards-page"
      assert directory_vue.props["page"]["list"]["empty"]["id"] == "dashboard-directory-empty"
      assert directory_rows(directory_vue) == []

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/new")

      assert has_element?(view, "#ops-dashboard-new-component.contents")
      refute has_element?(view, "#ops-dashboard-new-page")
      refute has_element?(view, "#dashboard-form")

      new_vue = LiveVue.Test.get_vue(view, id: "ops-dashboard-new-component")

      assert new_vue.component == "OpsDashboardNew"
      assert new_vue.class == "contents"
      assert new_vue.ssr == false

      assert new_vue.handlers == %{
               "save" => JS.push("save"),
               "validate" => JS.push("validate")
             }

      assert new_vue.props == %{
               "page" => %{
                 "id" => "ops-dashboard-new-page",
                 "mode" => "new",
                 "eyebrow" => "Dashboard authoring / Create",
                 "heading" => "New Dashboard",
                 "description" =>
                   "Create a mission-shared telemetry workspace, then compose it in the staged Editor.",
                 "source" => nil,
                 "import_guidance" => nil,
                 "cancel" => %{
                   "id" => "dashboard-cancel",
                   "label" => "Cancel",
                   "href" => "/missions/#{mission.mission_id}/ops/dashboards"
                 }
               },
               "form" => %{
                 "id" => "dashboard-form",
                 "name" => %{
                   "id" => "dashboard_name",
                   "name" => "dashboard[name]",
                   "type" => "text",
                   "label" => "Name",
                   "value" => "",
                   "required" => true
                 },
                 "description" => %{
                   "id" => "dashboard_description",
                   "name" => "dashboard[description]",
                   "type" => "text",
                   "label" => "Description (what operators use this screen for)",
                   "value" => "",
                   "required" => false
                 },
                 "document_json" => nil,
                 "submit" => %{
                   "id" => "dashboard-submit",
                   "label" => "Create in Editor"
                 }
               }
             }

      assert new_vue.props == Jason.decode!(Jason.encode!(new_vue.props))

      render_hook(view, "save", %{
        "dashboard" => %{"name" => "Power Overview", "description" => "EPS"}
      })

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

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")

      [directory_row] = view |> dashboard_directory_vue() |> directory_rows()

      assert directory_row["open"]["href"] == show_path(mission, dashboard)
      assert directory_row["name"] == "Thermal"
      assert directory_row["widget_version_label"] == "0 widgets · v1"

      assert ops_dashboard_nav_item(
               ops_nav_vue(view),
               "starred",
               dashboard.dashboard_id
             ) == %{
               "active" => false,
               "dashboard_id" => dashboard.dashboard_id,
               "href" => show_path(mission, dashboard),
               "label" => "Thermal"
             }

      assert has_element?(view, "#ops-status-bar-component.contents")

      status_bar = LiveVue.Test.get_vue(view, id: "ops-status-bar-component")
      presentation = status_bar.props["presentation"]
      notifications_bell = presentation["account"]["notifications_bell"]
      user_menu = presentation["account"]["user_menu"]

      assert status_bar.component == "OpsStatusBar"
      assert status_bar.class == "contents"
      refute status_bar.ssr

      assert presentation["clock"]["component"] == "UtcClock"

      assert presentation["clock"]["class"] ==
               "font-mono text-xs text-base-content/70 tabular-nums"

      refute Map.has_key?(presentation["clock"], "ssr")

      assert notifications_bell["component"] == "NotificationsBell"
      assert notifications_bell["class"] == "contents"
      refute Map.has_key?(notifications_bell, "ssr")
      assert user_menu["component"] == "UserMenu"
      assert user_menu["class"] == "contents"
      refute Map.has_key?(user_menu, "ssr")

      assert user_menu["presentation"]["menu"]["sign_out"]["attrs"]["action"] ==
               "/session"
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
        vue = LiveVue.Test.get_vue(view, id: "ops-context-rail-component")

        assert vue.props["rail"]["id"] == "ops-context-rail"

        assert vue.props["rail"]["storage_key"] == "cadence-ops-context-rail"

        assert Enum.map(vue.props["sections"], & &1["key"]) == [
                 "alarms",
                 "commands",
                 "fleet_health"
               ]
      end
    end
  end

  defp dashboard_directory_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-dashboard-directory-component")
  end

  defp directory_rows(vue) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", "/dashboard_directory/" <> _index, _row] -> true
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, row] -> row end)
  end
end
