defmodule CadenceWeb.OpsDashboardSharingLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Management
  alias CadenceWeb.TestFixtures

  test "Settings creates authenticated context shares and explicit read-only snapshots" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Shareable Power")

    {:ok, settings, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/settings?scope_kind=spacecraft&scope_id=sc-1&time_mode=archive&from=2026-08-01T00%3A00%3A00Z&to=2026-08-01T01%3A00%3A00Z&ignored_secret=never"
      )

    settings
    |> form("#dashboard-share-form",
      share: %{data_visibility: "definition_only", expires_in_hours: "4"}
    )
    |> render_submit()

    assert [share] =
             Management.list_shares(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    assert share.created_by == user.user_id
    assert share.access_policy == "mission_member"
    assert share.data_visibility == "definition_only"
    assert share.runtime_context["scope_id"] == "sc-1"
    refute Map.has_key?(share.runtime_context, "ignored_secret")

    {:ok, share_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboard-shares/#{share.dashboard_share_id}"
      )

    assert has_element?(share_view, "#ops-context-rail")
    assert has_element?(share_view, "#dashboard-share-visibility")
    assert has_element?(share_view, "#dashboard-share-open-dashboard")

    settings
    |> form("#dashboard-snapshot-form", snapshot: %{data_visibility: "authorized_runtime_data"})
    |> render_submit()

    assert [snapshot] =
             Management.list_snapshots(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    assert snapshot.dashboard_version == 1
    assert snapshot.data_semantics == "frozen_time_window"
    assert snapshot.data_visibility == "authorized_runtime_data"

    {:ok, snapshot_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboard-snapshots/#{snapshot.dashboard_snapshot_id}"
      )

    assert has_element?(snapshot_view, "#ops-context-rail")
    assert has_element?(snapshot_view, "#dashboard-snapshot-policy")
  end

  test "governed export records a digest and imports into target identity" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Portable Power")

    conn =
      get(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/export"
      )

    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") |> List.first() =~ "application/json"

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="portable-power.cadence-dashboard.json")
           ]

    assert {:ok, decoded} = Cadence.Dashboards.validate_export_bundle(conn.resp_body)
    assert decoded.dashboard_id == dashboard.dashboard_id

    assert [deployment] =
             Management.list_deployments(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    assert deployment.created_by == user.user_id
    assert deployment.environment == "portable_json"
    assert deployment.status == "exported"
    assert byte_size(deployment.artifact_digest) == 64
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-sharing")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
