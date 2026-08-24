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

    render_hook(settings, "create_share", %{
      "share" => %{"data_visibility" => "definition_only", "expires_in_hours" => "4"}
    })

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
    assert has_element?(share_view, "#ops-dashboard-share-component")

    share_vue = dashboard_share_vue(share_view)

    assert share_vue.props == Jason.decode!(Jason.encode!(share_vue.props))

    assert share_vue.props == %{
             "share" => %{
               "id" => "dashboard-share-page",
               "eyebrow" => "Authenticated mission share",
               "title" => "Dashboard context is ready",
               "restriction" => %{
                 "prefix" =>
                   "This link is restricted to members of #{mission.display_name}. It declares",
                 "visibility_id" => "dashboard-share-visibility",
                 "visibility" => "definition_only",
                 "suffix" => "and opens the dashboard with the captured operational selectors."
               },
               "context" => %{
                 "id" => "dashboard-share-context",
                 "entries" => [
                   %{"key" => "from", "value" => "2026-08-01T00:00:00Z"},
                   %{"key" => "scope_id", "value" => "sc-1"},
                   %{"key" => "scope_kind", "value" => "spacecraft"},
                   %{"key" => "time_mode", "value" => "archive"},
                   %{"key" => "to", "value" => "2026-08-01T01:00:00Z"}
                 ]
               },
               "action" => %{
                 "id" => "dashboard-share-open-dashboard",
                 "label" => "Open live dashboard",
                 "href" =>
                   "/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?from=2026-08-01T00%3A00%3A00Z&scope_id=sc-1&scope_kind=spacecraft&time_mode=archive&to=2026-08-01T01%3A00%3A00Z"
               }
             }
           }

    refute has_element?(share_view, "#dashboard-share-page")
    refute has_element?(share_view, "#dashboard-share-visibility")
    refute has_element?(share_view, "#dashboard-share-context")
    refute has_element?(share_view, "#dashboard-share-open-dashboard")

    render_hook(settings, "create_snapshot", %{
      "snapshot" => %{"data_visibility" => "authorized_runtime_data"}
    })

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
    assert has_element?(snapshot_view, "#ops-dashboard-snapshot-component")

    snapshot_vue = dashboard_snapshot_vue(snapshot_view)

    assert snapshot_vue.props == Jason.decode!(Jason.encode!(snapshot_vue.props))

    assert snapshot_vue.props == %{
             "snapshot" => %{
               "id" => "dashboard-snapshot-page",
               "eyebrow" => "Read-only snapshot",
               "name" => "Shareable Power",
               "policy" => %{
                 "id" => "dashboard-snapshot-policy",
                 "text" => "Definition version 1 · frozen_time_window · authorized_runtime_data"
               },
               "warning" =>
                 "The definition and selectors are immutable. Runtime values are only visible through the declared data policy and may still reflect current data when the time window was not frozen.",
               "definition" => %{
                 "id" => "dashboard-snapshot-definition",
                 "items" => [
                   %{"label" => "Widgets", "value" => 0},
                   %{"label" => "Captured selectors", "value" => 5},
                   %{"label" => "Schema", "value" => "v1"}
                 ]
               },
               "action" => %{
                 "id" => "dashboard-snapshot-open-current",
                 "label" => "Open current dashboard",
                 "href" =>
                   "/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
               }
             }
           }

    refute has_element?(snapshot_view, "#dashboard-snapshot-page")
    refute has_element?(snapshot_view, "#dashboard-snapshot-policy")
    refute has_element?(snapshot_view, "#dashboard-snapshot-definition")
    refute has_element?(snapshot_view, "#dashboard-snapshot-open-current")
  end

  test "missing dashboard sharing records preserve unavailable redirects and flashes" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    dashboards_path = ~p"/missions/#{mission.mission_id}/ops/dashboards"

    missing_routes = [
      {
        ~p"/missions/#{mission.mission_id}/ops/dashboard-shares/missing-share",
        "Dashboard share is unavailable: :dashboard_share_not_found"
      },
      {
        ~p"/missions/#{mission.mission_id}/ops/dashboard-snapshots/missing-snapshot",
        "Dashboard snapshot is unavailable: :dashboard_snapshot_not_found"
      }
    ]

    for {path, message} <- missing_routes do
      assert {:error,
              {:live_redirect,
               %{
                 to: ^dashboards_path,
                 flash: %{"error" => ^message}
               }}} = live(conn, path)
    end
  end

  test "does not expose dashboard shares or snapshots outside the current mission or organization" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()

    other_mission = TestFixtures.persist_mission!(org, slug: "other-dashboard-sharing")
    other_dashboard = TestFixtures.persist_dashboard_document!(other_mission)

    other_org = TestFixtures.persist_org!(slug: "other-dashboard-sharing-org")
    remote_mission = TestFixtures.persist_mission!(other_org, slug: "remote-dashboard-sharing")
    remote_dashboard = TestFixtures.persist_dashboard_document!(remote_mission)

    foreign_records =
      for {foreign_org, foreign_mission, foreign_dashboard} <- [
            {org, other_mission, other_dashboard},
            {other_org, remote_mission, remote_dashboard}
          ],
          kind <- [:share, :snapshot] do
        case kind do
          :share ->
            assert {:ok, share} =
                     Management.create_share(
                       foreign_org.organization_id,
                       foreign_mission.mission_id,
                       foreign_dashboard.dashboard_id,
                       %{},
                       created_by: user.user_id
                     )

            {:share, share.dashboard_share_id}

          :snapshot ->
            assert {:ok, snapshot} =
                     Management.create_snapshot(
                       foreign_org.organization_id,
                       foreign_mission.mission_id,
                       foreign_dashboard,
                       %{},
                       created_by: user.user_id,
                       data_visibility: "definition_only"
                     )

            {:snapshot, snapshot.dashboard_snapshot_id}
        end
      end

    dashboards_path = ~p"/missions/#{mission.mission_id}/ops/dashboards"

    for {kind, record_id} <- foreign_records do
      {path, message} =
        case kind do
          :share ->
            {
              "/missions/#{mission.mission_id}/ops/dashboard-shares/#{record_id}",
              "Dashboard share is unavailable: :dashboard_share_not_found"
            }

          :snapshot ->
            {
              "/missions/#{mission.mission_id}/ops/dashboard-snapshots/#{record_id}",
              "Dashboard snapshot is unavailable: :dashboard_snapshot_not_found"
            }
        end

      assert {:error,
              {:live_redirect,
               %{
                 to: ^dashboards_path,
                 flash: %{"error" => ^message}
               }}} = live(conn, path)
    end
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

  defp dashboard_share_vue(view) do
    vue = LiveVue.Test.get_vue(view, id: "ops-dashboard-share-component")

    assert vue.component == "OpsDashboardShare"
    assert vue.ssr == false
    assert vue.class == "h-full"

    vue
  end

  defp dashboard_snapshot_vue(view) do
    vue = LiveVue.Test.get_vue(view, id: "ops-dashboard-snapshot-component")

    assert vue.component == "OpsDashboardSnapshot"
    assert vue.ssr == false
    assert vue.class == "h-full"

    vue
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-sharing")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
