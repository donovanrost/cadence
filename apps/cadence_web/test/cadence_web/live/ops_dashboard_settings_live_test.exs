defmodule CadenceWeb.OpsDashboardSettingsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Management
  alias CadenceWeb.TestFixtures

  test "settings mounts with the current dashboard subject" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Settings")

    {:ok, view, _html} = live(conn, settings_path(mission, dashboard))

    assert_surface(
      view,
      "ops-dashboard-settings-component",
      "dashboard_settings",
      mission,
      %{"dashboard_id" => dashboard.dashboard_id}
    )

    assert has_element?(view, "#ops-context-rail-component")
  end

  test "settings share action remains a durable authenticated outcome" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Share Settings")
    {:ok, view, _html} = live(conn, settings_path(mission, dashboard))

    render_hook(view, "create_share", %{
      "share" => %{"data_visibility" => "definition_only", "expires_in_hours" => "4"}
    })

    assert [share] =
             Management.list_shares(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    assert share.created_by == user.user_id
    assert share.data_visibility == "definition_only"
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}.contents")
    vue = LiveVue.Test.get_vue(view, id: id)
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "ops_console",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params,
             "surface_id" => surface_id
           }
  end

  defp settings_path(mission, dashboard),
    do: ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/settings"

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-settings")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
