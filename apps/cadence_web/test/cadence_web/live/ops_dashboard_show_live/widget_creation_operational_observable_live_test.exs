defmodule CadenceWeb.OpsDashboardShowLive.WidgetCreationOperationalObservableLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  alias Cadence.Dashboards.{Document, RenderItem}
  alias CadenceWeb.TestFixtures

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  describe "operational observable widget creation flows" do
    test "adds an operational observable status matrix through the slide-over panel" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Ops")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      await_dashboard_resolved(view)

      click_editor_action(view, "add-widget-button")

      change_widget_form(view, %{
        type: "status_matrix",
        title: "Contact Phase",
        mode: "context",
        precision: "0"
      })

      change_widget_form(view, %{
        type: "status_matrix",
        title: "Contact Phase",
        binding_source: "operational_observables",
        precision: "0"
      })

      option_ids = operational_observable_option_ids(view)
      assert "contacts.phase" in option_ids
      assert "comms.transport.connection_state" in option_ids
      assert "ground.station.connection_state" in option_ids
      assert "comms.transport.downlink_bitrate" in option_ids

      click_widget_point(view, "contacts.phase")

      assert "contacts.phase" in selected_operational_observable_ids(view)

      submit_widget_form(view, %{
        type: "status_matrix",
        title: "Contact Phase",
        binding_source: "operational_observables",
        precision: "0"
      })

      await_dashboard_resolved(view)
      refute has_element?(view, "#dashboard-panel")
      click_editor_action(view, "dashboard-editor-save")
      stop_dashboard_view(view)

      document = fetch_dashboard_document!(org, mission, dashboard)

      assert [%{placement_id: placement_id, widget_def: widget_def}] = document.placements
      assert widget_def.widget_type_id == "cadence.status_matrix"
      assert widget_def.binding.source == :operational_observables
      assert widget_def.binding.observables == ["contacts.phase"]
      assert widget_def.binding.overlays == []

      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Added widget"
      assert version.created_by == user.user_id

      assert [
               %{
                 placement_id: ^placement_id,
                 widget: %{binding: %{source: :operational_observables, point_ids: point_ids}}
               }
             ] = RenderItem.from_document(document)

      assert point_ids == ["contacts.phase"]
    end
  end

  defp click_editor_action(view, id) do
    assert has_element?(view, "#dashboard-editor-actions-component")
    vue = LiveVue.Test.get_vue(view, id: "dashboard-editor-actions-component")
    assert vue.component == "DashboardEditorActions"
    assert action = Enum.find(vue.props["presentation"]["elements"], &(&1["attrs"]["id"] == id))
    attrs = action["attrs"]

    render_click(
      view,
      Map.fetch!(attrs, "phx-click"),
      Enum.reduce(attrs, %{}, fn
        {"phx-value-" <> key, value}, params -> Map.put(params, key, value)
        {_attribute, _value}, params -> params
      end)
    )
  end

  defp change_widget_form(view, overrides) do
    {root, params} = widget_form_event_contract(view, overrides)
    render_change(view, root["attrs"]["phx-change"], %{root["param"] => params})
  end

  defp submit_widget_form(view, overrides) do
    {root, params} = widget_form_event_contract(view, overrides)
    render_submit(view, root["attrs"]["phx-submit"], %{root["param"] => params})
  end

  defp widget_form_event_contract(view, overrides) do
    presentation = widget_form_presentation(view)
    root = presentation["root"]
    assert root["id"] == "widget-form"
    assert root["attrs"]["phx-change"] == "validate_widget"
    assert root["attrs"]["phx-submit"] == "save_widget"
    assert root["param"] == "widget"
    params = Map.merge(root["params"], stringify_keys(overrides))
    assert params == Jason.decode!(Jason.encode!(params))
    {root, params}
  end

  defp click_widget_point(view, point_id) do
    option =
      view
      |> operational_observable_options()
      |> Enum.find(&(&1["observable_id"] == point_id))

    assert option["attrs"]["phx-click"] == "pick_point"
    assert option["attrs"]["phx-value-point-id"] == point_id
    render_click(view, option["attrs"]["phx-click"], %{"point-id" => point_id})
  end

  defp operational_observable_option_ids(view) do
    view |> operational_observable_options() |> Enum.map(& &1["observable_id"])
  end

  defp operational_observable_options(view) do
    view
    |> widget_form_presentation()
    |> get_in(["point_widget", "operational_observable_picker", "list", "groups"])
    |> Enum.flat_map(& &1["options"])
  end

  defp selected_operational_observable_ids(view) do
    view
    |> widget_form_presentation()
    |> get_in(["point_widget", "operational_observable_picker", "selected", "buttons"])
    |> Enum.map(& &1["attrs"]["data-selected-operational-observable"])
  end

  defp widget_form_presentation(view) do
    assert has_element?(view, "#widget-form-component")
    vue = LiveVue.Test.get_vue(view, id: "widget-form-component")
    assert vue.component == "WidgetForm"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    Map.fetch!(vue.props, "presentation")
  end

  defp stringify_keys(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/edit"
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
end
