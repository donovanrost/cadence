defmodule CadenceWeb.OpsDashboardEditorLiveTest do
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveView.JS

  test "viewer route rejects editor-only events" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Viewer Boundary")

    {:ok, viewer, _html} =
      await_live_result(live(conn, viewer_path(mission, dashboard)))

    grid_controller =
      LiveVue.Test.get_vue(viewer, id: "dashboard-grid-#{dashboard.dashboard_id}-controller")

    assert grid_controller.component == "DashboardGrid"
    assert grid_controller.props["target_id"] == "dashboard-grid-#{dashboard.dashboard_id}"
    assert grid_controller.props["edit_mode"] == false
    assert grid_controller.props["item_ids"] == []
    assert grid_controller.handlers["layout_changed"] == JS.push("layout_changed")
    refute has_element?(viewer, "#dashboard-editor-guard-controller")
    refute has_element?(viewer, "#dashboard-panel-component")
    render_hook(viewer, "open_add_widget", %{})
    refute has_element?(viewer, "#dashboard-panel-component")
  end

  test "stages multiple document changes and persists one coherent version only on Save" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Staged Editor")

    {:ok, editor, _html} =
      await_live_result(live(conn, edit_path(mission, dashboard)))

    assert has_element?(
             editor,
             ~s(#ops-dashboard-show-page[data-dashboard-editor="true"][data-editor-dirty="false"])
           )

    guard = LiveVue.Test.get_vue(editor, id: "dashboard-editor-guard-controller")
    assert guard.component == "DashboardEditorGuard"
    assert guard.props["editor_dirty"] == false
    assert guard.handlers == %{}
    assert guard.ssr == false

    assert editor_action(editor, "edit-paused-note")["text"] ==
             "Live updates paused while editing"

    assert editor_action(editor, "dashboard-editor-save")["attrs"]["disabled"] == ""

    add_section(editor, "Power")
    add_section(editor, "Thermal")

    assert has_element?(
             editor,
             ~s(#ops-dashboard-show-page[data-editor-dirty="true"])
           )

    assert LiveVue.Test.get_vue(editor, id: "dashboard-editor-guard-controller").props[
             "editor_dirty"
           ] == true

    assert 1 == version_count(org, mission, dashboard)
    assert {:ok, %Document{sections: []}} = fetch_document(org, mission, dashboard)

    click_editor_action(editor, "dashboard-editor-save")

    assert has_element?(
             editor,
             ~s(#ops-dashboard-show-page[data-editor-dirty="false"])
           )

    assert LiveVue.Test.get_vue(editor, id: "dashboard-editor-guard-controller").props[
             "editor_dirty"
           ] == false

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

  test "presented section actions dispatch move, edit, and remove events" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Section Actions")

    {:ok, editor, _html} =
      await_live_result(live(conn, edit_path(mission, dashboard)))

    add_section(editor, "Power")
    add_section(editor, "Thermal")

    click_dashboard_section_action(editor, "Thermal", "move-up")

    assert Enum.map(dashboard_section_list(editor), & &1["content"]["title"]["text"]) ==
             ["Thermal", "Power"]

    click_dashboard_section_action(editor, "Thermal", "edit")

    assert dashboard_section_form(editor)["heading"]["text"] == "Edit section"

    update_section(editor, %{
      "section_id" => section_id(editor, "Thermal"),
      "title" => "Thermal Operations",
      "description" => "",
      "collapsed_by_default" => "false"
    })

    click_dashboard_section_action(editor, "Power", "remove")

    assert Enum.map(dashboard_section_list(editor), & &1["content"]["title"]["text"]) ==
             ["Thermal Operations"]
  end

  test "Discard leaves the starting document and version history untouched" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Discard Editor")

    {:ok, editor, _html} =
      await_live_result(live(conn, edit_path(mission, dashboard)))

    add_section(editor, "Candidate only")

    click_editor_action(editor, "dashboard-editor-discard")
    assert_redirect(editor, viewer_path(mission, dashboard))

    assert 1 == version_count(org, mission, dashboard)
    assert {:ok, %Document{sections: []}} = fetch_document(org, mission, dashboard)
  end

  test "a stale starting version preserves the candidate and requires explicit reload" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()

    %Document{} =
      dashboard =
      TestFixtures.persist_dashboard_document!(mission, name: "Conflict Editor")

    {:ok, editor, _html} =
      await_live_result(live(conn, edit_path(mission, dashboard)))

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

    click_editor_action(editor, "dashboard-editor-save")

    assert has_element?(
             editor,
             ~s(#dashboard-editor-conflict[data-editor-starting-version="1"][data-editor-current-version="2"])
           )

    assert [_section] = dashboard_section_list(editor)

    assert {:ok, %Document{name: "External Change", sections: []}} =
             fetch_document(org, mission, dashboard)

    editor |> element("#dashboard-editor-reload") |> render_click()

    refute has_element?(editor, "#dashboard-editor-conflict")
    refute has_element?(editor, "[data-dashboard-section]")
  end

  defp add_section(view, title) do
    click_editor_action(view, "manage-dashboard-sections")

    params = %{
      "section_id" => "",
      "title" => title,
      "description" => "",
      "collapsed_by_default" => "false"
    }

    change_dashboard_section_form(view, params)
    assert dashboard_section_form(view)["root"]["params"] == params
    submit_dashboard_section_form(view, params)
  end

  defp update_section(view, params) do
    change_dashboard_section_form(view, params)
    assert dashboard_section_form(view)["root"]["params"] == params
    submit_dashboard_section_form(view, params)
  end

  defp dashboard_section_list(view) do
    view
    |> dashboard_section_manager()
    |> Map.fetch!("sections")
  end

  defp dashboard_section_form(view) do
    view
    |> dashboard_section_manager_presentation()
    |> Map.fetch!("form")
  end

  defp dashboard_section_manager(view) do
    view
    |> dashboard_section_manager_presentation()
    |> Map.fetch!("section_list")
  end

  defp dashboard_section_manager_presentation(view) do
    assert has_element?(view, "#dashboard-panel-component")
    refute has_element?(view, "#dashboard-section-manager-component")
    vue = LiveVue.Test.get_vue(view, id: "dashboard-panel-component")
    assert vue.component == "DashboardPanel"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    child = vue.props["presentation"]["child"]
    assert child["kind"] == "dashboard_section_manager"

    assert child["wrapper"]["attrs"] == %{
             "class" => "contents",
             "id" => "dashboard-section-manager-component"
           }

    assert child["outer_wrapper"] == nil
    child["presentation"]
  end

  defp change_dashboard_section_form(view, params) do
    form = dashboard_section_form(view)

    render_change(
      view,
      form["root"]["attrs"]["phx-change"],
      %{form["root"]["param"] => params}
    )
  end

  defp submit_dashboard_section_form(view, params) do
    form = dashboard_section_form(view)

    render_submit(
      view,
      form["root"]["attrs"]["phx-submit"],
      %{form["root"]["param"] => params}
    )
  end

  defp click_dashboard_section_action(view, title, key) do
    assert section =
             Enum.find(
               dashboard_section_list(view),
               &(&1["content"]["title"]["text"] == title)
             )

    assert action = Enum.find(section["actions"]["buttons"], &(&1["key"] == key))
    attrs = action["attrs"]

    render_click(view, Map.fetch!(attrs, "phx-click"), event_params(attrs))
  end

  defp section_id(view, title) do
    assert section =
             Enum.find(
               dashboard_section_list(view),
               &(&1["content"]["title"]["text"] == title)
             )

    section["attrs"]["data-dashboard-section"]
  end

  defp click_editor_action(view, id) do
    attrs = editor_action(view, id)["attrs"]

    render_click(
      view,
      Map.fetch!(attrs, "phx-click"),
      event_params(attrs)
    )
  end

  defp event_params(attrs) do
    Enum.reduce(attrs, %{}, fn
      {"phx-value-" <> key, value}, params -> Map.put(params, key, value)
      {_attribute, _value}, params -> params
    end)
  end

  defp editor_action(view, id) do
    assert has_element?(view, "#dashboard-toolbar-component")
    presentation = dashboard_editor_actions_presentation(view)
    assert action = Enum.find(presentation["elements"], &(&1["attrs"]["id"] == id))
    action
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
