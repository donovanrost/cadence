defmodule CadenceWeb.OpsDashboardShowLive.DashboardLifecycleConflictLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias Cadence.Dashboards.DocumentStore.DashboardRow, as: OpsDashboardRow
  alias Cadence.Repo
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

  defp bump_dashboard_row_latest_version!(org, mission, dashboard, version)
       when is_integer(version) and version > 0 do
    row =
      Repo.get_by!(OpsDashboardRow,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: dashboard.dashboard_id
      )

    row
    |> Ecto.Changeset.change(%{latest_version: version, draft_version: version})
    |> Repo.update!()
  end

  test "refreshes archived dashboard list when a stale restore conflicts" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Restore Conflict")

    assert :ok =
             Cadence.Dashboards.archive_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               expected_version: 1
             )

    {:ok, list_view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards?lifecycle=archived")

    [archived_row] = directory_rows(list_view)

    assert archived_row["restore"] == %{
             "id" => "restore-dashboard-#{dashboard.dashboard_id}",
             "label" => "Restore",
             "icon" => "hero-arrow-uturn-left",
             "payload" => %{
               "dashboard-id" => dashboard.dashboard_id,
               "expected-version" => "1"
             },
             "disabled" => false,
             "lifecycle_action" => "restore",
             "action_available" => "true"
           }

    bump_dashboard_row_latest_version!(org, mission, dashboard, 2)

    html = render_hook(list_view, "restore_dashboard", archived_row["restore"]["payload"])

    assert html =~ "Dashboard changed in another session. Reloaded version 2"

    assert [%{"lifecycle" => %{"state" => "archived"}}] = directory_rows(list_view)

    assert [] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert [%Cadence.Dashboards.DashboardSummary{} = archived_summary] =
             Cadence.Dashboards.list_archived_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert archived_summary.lifecycle_state == "archived"
    assert archived_summary.latest_version == 2

    assert [%Cadence.Dashboards.LifecycleEvent{event_type: :archived}] =
             Cadence.Dashboards.list_lifecycle_events(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )
  end

  test "reloads the latest dashboard when a stale publish conflicts" do
    {conn, org, mission} = signed_in_org_and_mission()
    %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/activity"
      )

    assert {:ok, %Document{} = _updated} =
             Cadence.Dashboards.update_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %Document{dashboard | name: "Power Updated"},
               expected_version: Document.version(dashboard)
             )

    html = render_hook(view, "publish_version", %{"version" => "1"})

    assert html =~ "Failed to publish dashboard"

    assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert summary.latest_version == 2
    assert summary.draft_version == 2
    assert summary.published_version == nil

    assert [] =
             Cadence.Dashboards.list_lifecycle_events(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )
  end

  test "reloads the latest dashboard when a stale archive conflicts" do
    {conn, org, mission} = signed_in_org_and_mission()
    %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/settings"
      )

    assert {:ok, %Document{} = _updated} =
             Cadence.Dashboards.update_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %Document{dashboard | name: "Power Updated"},
               expected_version: Document.version(dashboard)
             )

    html = render_hook(view, "archive_dashboard", %{})

    assert html =~ "Failed to archive dashboard"

    assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert summary.latest_version == 2
    assert summary.lifecycle_state == "active"

    assert [] =
             Cadence.Dashboards.list_lifecycle_events(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )
  end

  defp directory_rows(view) do
    view
    |> LiveVue.Test.get_vue(id: "ops-dashboard-directory-component")
    |> Map.fetch!(:streams_diff)
    |> Enum.filter(fn
      ["upsert", "/dashboard_directory/" <> _index, _row] -> true
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, row] -> row end)
  end
end
