defmodule CadenceWeb.OpsDashboardActivityLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures

  test "version selection is URL-addressable and publish reads the canonical lifecycle store" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Activity")

    assert {:ok, %Document{} = updated} =
             Cadence.Dashboards.update_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %Document{dashboard | description: "Second version"},
               expected_version: 1,
               change_summary: "Added activity description"
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/activity?version=1"
      )

    assert has_element?(view, ~s(#dashboard-version-detail[data-selected-version="1"]))
    assert has_element?(view, "#dashboard-version-2", "Added activity description")

    view
    |> element("#dashboard-version-2")
    |> render_click()

    assert_patch(
      view,
      ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/activity?version=2"
    )

    view |> element("#dashboard-activity-publish") |> render_click()

    assert [%{published_version: 2, draft_version: nil}] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert Document.version(updated) == 2
  end

  test "Viewer routes page-sized workflows instead of exposing inline mutation controls" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Viewer Boundaries")

    {:ok, viewer, _html} = live(conn, viewer_path(mission, dashboard))

    assert has_element?(viewer, "#dashboard-edit-link")
    assert has_element?(viewer, "#dashboard-settings-button")
    assert has_element?(viewer, "#dashboard-versions-button")
    assert has_element?(viewer, "#dashboard-diagnostics-button")

    refute has_element?(viewer, ~s(#dashboard-menu [phx-click="publish_dashboard"]))
    refute has_element?(viewer, ~s(#dashboard-menu [phx-click="archive_dashboard"]))
    refute has_element?(viewer, ~s(#dashboard-menu [phx-click="open_rename"]))
  end

  defp viewer_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-activity")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
