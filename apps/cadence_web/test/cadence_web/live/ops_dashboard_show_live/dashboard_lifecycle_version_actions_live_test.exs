defmodule CadenceWeb.OpsDashboardShowLive.DashboardLifecycleVersionActionsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp fetch_dashboard_document!(org, mission, dashboard) do
    assert {:ok, document} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    document
  end

  defp fetch_dashboard_version!(org, mission, dashboard, version_number) do
    assert {:ok, dashboard_version} =
             Cadence.Dashboards.fetch_version(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               version_number
             )

    dashboard_version
  end

  test "renames the dashboard from the toolbar menu without exposing hard delete" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/settings"
      )

    render_hook(view, "save_settings", %{
      "settings" => %{
        "name" => "Power North",
        "description" => "EPS",
        "tags" => "",
        "defaults_json" => "{}"
      }
    })

    renamed = fetch_dashboard_document!(org, mission, dashboard)

    assert renamed.name == "Power North"
    version = fetch_dashboard_version!(org, mission, dashboard, 2)
    assert version.change_summary == "Updated dashboard settings"
    assert version.created_by == user.user_id

    settings_vue = LiveVue.Test.get_vue(view, id: "ops-dashboard-settings-component")

    assert settings_vue.props["settings_form"]["fields"]["name"]["value"] == "Power North"

    assert settings_vue.props["page"]["lifecycle"]["archive"]["id"] ==
             "dashboard-settings-archive"

    refute Map.has_key?(settings_vue.handlers, "delete_dashboard")
  end

  test "publishes a historical version from the versions panel without discarding the newer draft" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()

    %Document{} =
      dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Original Power")

    assert {:ok, %Document{} = updated} =
             Cadence.Dashboards.update_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %Document{dashboard | name: "Published Power"},
               expected_version: 1
             )

    assert {:ok, %Cadence.Dashboards.Version{}} =
             Cadence.Dashboards.publish_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               Document.version(updated),
               expected_version: Document.version(updated)
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/activity"
      )

    activity_path =
      ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/activity"

    render_patch(view, activity_path <> "?version=1")
    render_hook(view, "publish_version", %{"version" => "1"})

    assert "published" in activity_event_types(view)

    {:ok, viewer, _html} = live(conn, show_path(mission, dashboard))
    render_dashboard_async(viewer)

    assert has_element?(
             viewer,
             ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"][data-dashboard-publication-state="draft_ahead"][data-dashboard-publishable-version="2"])
           )

    assert has_element?(viewer, "h1", "Original Power")

    assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert summary.latest_version == 2
    assert summary.draft_version == 2
    assert summary.published_version == 1

    assert %Cadence.Dashboards.LifecycleEvent{} =
             published =
             org.organization_id
             |> Cadence.Dashboards.list_lifecycle_events(
               mission.mission_id,
               dashboard.dashboard_id
             )
             |> List.last()

    assert published.event_type == :published
    assert published.dashboard_version == 1
    assert published.actor_id == user.user_id
  end

  defp activity_event_types(view) do
    view
    |> LiveVue.Test.get_vue(id: "dashboard-activity-events-component")
    |> Map.fetch!(:streams_diff)
    |> Enum.flat_map(fn
      ["upsert", "/dashboard_activity/" <> _index, event] -> [event["event_type"]]
      _operation -> []
    end)
  end
end
