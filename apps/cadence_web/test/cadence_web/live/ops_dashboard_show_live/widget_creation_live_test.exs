defmodule CadenceWeb.OpsDashboardShowLive.WidgetCreationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.Document
  alias Cadence.Telemetry.PacketDefinition
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

  defp persist_binding_set!(org, mission) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission.mission_id,
        packet_definition_id: "hk-counter",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-binding-set",
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: mission.mission_id <> "-hk-counter-instance",
            family_key: :definition_bound_telemetry,
            target_scope: :mission,
            runtime_configuration: packet_definition
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: mission.mission_id <> "-hk-counter-rule",
            capability_instance_id: mission.mission_id <> "-hk-counter-instance",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp persist_matrix_binding_set!(org, mission) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission.mission_id,
        packet_definition_id: "hk-matrix",
        packet_name: "HK",
        apid: 43,
        fields: [
          %{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint},
          %{name: "voltage", offset_bits: 16, size_bits: 16, data_type: :uint}
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-matrix-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 43,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp activate_binding_set!(org, mission, binding_set) do
    {:ok, _activation} =
      Cadence.ActivationFixtures.activate_binding_set(
        org.organization_id,
        mission.mission_id,
        binding_set.binding_set_id,
        binding_set.version,
        []
      )
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

  describe "widget creation flows" do
    test "adds a widget through the slide-over panel" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      binding_set = persist_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      await_dashboard_resolved(view)

      click_editor_action(view, "add-widget-button")
      assert has_element?(view, "#dashboard-panel")

      click_widget_point(view, "HK.counter")

      submit_widget_form(view, %{type: "value_tile", title: "Counter", mode: "context"})

      await_dashboard_resolved(view)

      refute has_element?(view, "#dashboard-panel")
      assert has_element?(view, ~s(.grid-stack-item[gs-auto-position="true"]))

      click_editor_action(view, "dashboard-editor-save")

      stop_dashboard_view(view)

      document = fetch_dashboard_document!(org, mission, dashboard)

      assert [%{layout: %{x: nil, y: nil}} = placement] = document.placements

      assert placement.widget_def.title == "Counter"
      assert Document.version(document) == 2

      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Added widget"
      assert version.created_by == user.user_id
    end

    test "adds an event timeline widget without selecting telemetry points" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      await_dashboard_resolved(view)

      click_editor_action(view, "add-widget-button")

      submit_widget_form(view, %{type: "event_timeline", title: "Mission Events"})

      await_dashboard_resolved(view)

      refute has_element?(view, "#dashboard-panel")
      assert has_dashboard_element?(view, ~s([data-event-timeline]))

      click_editor_action(view, "dashboard-editor-save")

      stop_dashboard_view(view)

      document = fetch_dashboard_document!(org, mission, dashboard)
      assert [placement] = document.placements
      assert placement.widget_def.widget_type_id == "cadence.event_timeline"

      assert Map.take(placement.widget_def.binding, [
               :source,
               :observables,
               :scope_mode,
               :data_mode,
               :value_type,
               :sampling,
               :overlays
             ]) == %{
               source: :events,
               observables: [],
               scope_mode: :context,
               data_mode: :context,
               value_type: nil,
               sampling: :event_history,
               overlays: []
             }
    end

    test "adds a state timeline widget from a selected telemetry point" do
      {conn, org, mission} = signed_in_org_and_mission()
      binding_set = persist_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      await_dashboard_resolved(view)

      click_editor_action(view, "add-widget-button")
      click_widget_point(view, "HK.counter")

      submit_widget_form(view, %{
        type: "state_timeline",
        title: "Counter State",
        mode: "context"
      })

      await_dashboard_resolved(view)

      refute has_element?(view, "#dashboard-panel")
      assert has_dashboard_element?(view, ~s([data-state-timeline]))

      click_editor_action(view, "dashboard-editor-save")

      stop_dashboard_view(view)

      document = fetch_dashboard_document!(org, mission, dashboard)
      assert [placement] = document.placements
      assert placement.widget_def.widget_type_id == "cadence.state_timeline"

      assert Map.take(placement.widget_def.binding, [
               :source,
               :observables,
               :scope_mode,
               :data_mode,
               :value_type,
               :sampling,
               :overlays
             ]) == %{
               source: :limits,
               observables: ["HK.counter"],
               scope_mode: :context,
               data_mode: :context,
               value_type: :engineering,
               sampling: :event_history,
               overlays: [:quality]
             }
    end

    test "adds a status matrix with multiple points through the slide-over panel" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      binding_set = persist_matrix_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      await_dashboard_resolved(view)

      click_editor_action(view, "add-widget-button")

      change_widget_form(view, %{
        type: "status_matrix",
        title: "HK Matrix",
        mode: "context",
        precision: "0"
      })

      click_widget_point(view, "HK.counter")
      click_widget_point(view, "HK.voltage")

      assert "HK.counter" in selected_widget_point_ids(view)
      assert "HK.voltage" in selected_widget_point_ids(view)

      submit_widget_form(view, %{
        type: "status_matrix",
        title: "HK Matrix",
        mode: "context",
        precision: "0"
      })

      await_dashboard_resolved(view)
      refute has_element?(view, "#dashboard-panel")
      click_editor_action(view, "dashboard-editor-save")
      stop_dashboard_view(view)

      document = fetch_dashboard_document!(org, mission, dashboard)

      assert [%{widget_def: widget_def}] = document.placements
      assert widget_def.widget_type_id == "cadence.status_matrix"
      assert widget_def.binding.observables == ["HK.counter", "HK.voltage"]

      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Added widget"
      assert version.created_by == user.user_id
    end

    test "adds a data table with multiple points through the slide-over panel" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      binding_set = persist_matrix_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      await_dashboard_resolved(view)

      click_editor_action(view, "add-widget-button")

      change_widget_form(view, %{
        type: "data_table",
        title: "HK Table",
        mode: "context",
        precision: "1"
      })

      click_widget_point(view, "HK.counter")
      click_widget_point(view, "HK.voltage")

      assert "HK.counter" in selected_widget_point_ids(view)
      assert "HK.voltage" in selected_widget_point_ids(view)

      submit_widget_form(view, %{
        type: "data_table",
        title: "HK Table",
        mode: "context",
        precision: "1"
      })

      await_dashboard_resolved(view)
      refute has_element?(view, "#dashboard-panel")
      click_editor_action(view, "dashboard-editor-save")
      stop_dashboard_view(view)

      document = fetch_dashboard_document!(org, mission, dashboard)

      assert [%{widget_def: widget_def}] = document.placements
      assert widget_def.widget_type_id == "cadence.data_table"
      assert widget_def.binding.observables == ["HK.counter", "HK.voltage"]

      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Added widget"
      assert version.created_by == user.user_id
    end
  end

  defp click_editor_action(view, id) do
    assert has_element?(view, "#dashboard-toolbar-component")
    presentation = dashboard_editor_actions_presentation(view)
    assert action = Enum.find(presentation["elements"], &(&1["attrs"]["id"] == id))
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
    presentation = widget_form_presentation(view)
    picker = presentation["point_widget"]["point_picker"]
    option = Enum.find(picker["list"]["options"], &(&1["point_id"] == point_id))

    assert option["attrs"]["phx-click"] == "pick_point"
    assert option["attrs"]["phx-value-point-id"] == point_id
    render_click(view, option["attrs"]["phx-click"], %{"point-id" => point_id})
  end

  defp selected_widget_point_ids(view) do
    view
    |> widget_form_presentation()
    |> get_in(["point_widget", "point_picker", "selected_points", "buttons"])
    |> Enum.map(& &1["attrs"]["data-selected-point"])
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
end
