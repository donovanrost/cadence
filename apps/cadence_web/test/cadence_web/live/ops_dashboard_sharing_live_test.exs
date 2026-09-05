defmodule CadenceWeb.OpsDashboardSharingLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Management
  alias CadenceWeb.TestFixtures

  test "authenticated share and snapshot routes mount exact route subjects" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Shareable Power")

    {:ok, share} =
      Management.create_share(
        org.organization_id,
        mission.mission_id,
        dashboard.dashboard_id,
        %{"scope_kind" => "mission"},
        created_by: user.user_id
      )

    {:ok, snapshot} =
      Management.create_snapshot(
        org.organization_id,
        mission.mission_id,
        dashboard,
        %{},
        created_by: user.user_id,
        data_visibility: "definition_only"
      )

    {:ok, share_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboard-shares/#{share.dashboard_share_id}"
      )

    assert_surface(
      share_view,
      "ops-dashboard-share-component",
      "dashboard_share",
      mission,
      %{"share_id" => share.dashboard_share_id},
      "h-full"
    )

    {:ok, snapshot_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboard-snapshots/#{snapshot.dashboard_snapshot_id}"
      )

    assert_surface(
      snapshot_view,
      "ops-dashboard-snapshot-component",
      "dashboard_snapshot",
      mission,
      %{"snapshot_id" => snapshot.dashboard_snapshot_id},
      "h-full"
    )
  end

  test "missing sharing records preserve the mission redirect outcome" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()

    assert {:error, {:live_redirect, %{to: path}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboard-shares/missing")

    assert path == "/missions/#{mission.mission_id}/ops/dashboards"
  end

  defp assert_surface(view, id, surface_id, mission, query_params, class \\ "contents") do
    assert has_element?(view, "##{id}.#{class}")
    vue = LiveVue.Test.get_vue(view, id: id)
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == class
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

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-sharing")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
