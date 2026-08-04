defmodule CadenceWeb.OpsDashboardEditorLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures

  test "viewer route rejects editor-only events" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Viewer Boundary")

    {:ok, viewer, _html} = live(conn, viewer_path(mission, dashboard))

    refute has_element?(viewer, "#dashboard-panel")
    render_hook(viewer, "open_add_widget", %{})
    refute has_element?(viewer, "#dashboard-panel")
  end

  test "stages multiple document changes and persists one coherent version only on Save" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Staged Editor")

    {:ok, editor, _html} = live(conn, edit_path(mission, dashboard))

    assert has_element?(
             editor,
             ~s(#ops-dashboard-show-page[data-dashboard-editor="true"][data-editor-dirty="false"])
           )

    assert has_element?(editor, "#edit-paused-note")
    assert has_element?(editor, "#dashboard-editor-save[disabled]")

    add_section(editor, "Power")
    add_section(editor, "Thermal")

    assert has_element?(
             editor,
             ~s(#ops-dashboard-show-page[data-editor-dirty="true"])
           )

    assert 1 == version_count(org, mission, dashboard)
    assert {:ok, %Document{sections: []}} = fetch_document(org, mission, dashboard)

    editor |> element("#dashboard-editor-save") |> render_click()

    assert has_element?(
             editor,
             ~s(#ops-dashboard-show-page[data-editor-dirty="false"])
           )

    assert 2 == version_count(org, mission, dashboard)

    assert {:ok, %Document{} = persisted} = fetch_document(org, mission, dashboard)
    assert Enum.map(persisted.sections, & &1.title) == ["Power", "Thermal"]

    assert [%{change_summary: summary}] =
             Cadence.Dashboards.list_versions(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )
             |> Enum.drop(1)

    assert summary == "Updated dashboard sections"
  end

  test "Discard leaves the starting document and version history untouched" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Discard Editor")

    {:ok, editor, _html} = live(conn, edit_path(mission, dashboard))
    add_section(editor, "Candidate only")

    editor |> element("#dashboard-editor-discard") |> render_click()
    assert_redirect(editor, viewer_path(mission, dashboard))

    assert 1 == version_count(org, mission, dashboard)
    assert {:ok, %Document{sections: []}} = fetch_document(org, mission, dashboard)
  end

  test "a stale starting version preserves the candidate and requires explicit reload" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()

    %Document{} =
      dashboard =
      TestFixtures.persist_dashboard_document!(mission, name: "Conflict Editor")

    {:ok, editor, _html} = live(conn, edit_path(mission, dashboard))
    add_section(editor, "Unsaved Candidate")

    assert {:ok, %Document{} = external} =
             Cadence.Dashboards.update_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %Document{dashboard | name: "External Change"},
               expected_version: 1,
               change_summary: "External update"
             )

    assert Document.version(external) == 2

    editor |> element("#dashboard-editor-save") |> render_click()

    assert has_element?(
             editor,
             ~s(#dashboard-editor-conflict[data-editor-starting-version="1"][data-editor-current-version="2"])
           )

    assert has_element?(editor, "[data-dashboard-section]")

    assert {:ok, %Document{name: "External Change", sections: []}} =
             fetch_document(org, mission, dashboard)

    editor |> element("#dashboard-editor-reload") |> render_click()

    refute has_element?(editor, "#dashboard-editor-conflict")
    refute has_element?(editor, "[data-dashboard-section]")
  end

  defp add_section(view, title) do
    view |> element("#manage-dashboard-sections") |> render_click()

    view
    |> form("#dashboard-section-form",
      section: %{title: title, description: "", collapsed_by_default: "false"}
    )
    |> render_submit()
  end

  defp version_count(org, mission, dashboard) do
    Cadence.Dashboards.list_versions(
      org.organization_id,
      mission.mission_id,
      dashboard.dashboard_id
    )
    |> length()
  end

  defp fetch_document(org, mission, dashboard) do
    Cadence.Dashboards.fetch_document(
      org.organization_id,
      mission.mission_id,
      dashboard.dashboard_id
    )
  end

  defp edit_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/edit"
  end

  defp viewer_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-editor")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
