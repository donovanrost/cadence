defmodule CadenceWeb.OpsDashboardShowLive.WidgetCreationLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

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
      Cadence.activate_binding_set(
        org.organization_id,
        mission.mission_id,
        binding_set.binding_set_id,
        binding_set.version,
        []
      )
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

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views = Process.get(:ops_dashboard_live_test_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_live_test_views, MapSet.put(tracked_views, pid))

      on_exit({:ops_dashboard_live_view, pid}, fn ->
        stop_dashboard_view(view)
      end)
    end
  end

  defp stop_dashboard_view(view) do
    if Process.alive?(view.pid) do
      drain_dashboard_view(view)

      ref = Process.monitor(view.pid)
      {_proxy_ref, _topic, proxy_pid} = view.proxy
      ClientProxy.stop(proxy_pid, {:shutdown, :dashboard_test_cleanup})

      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 1_000
    end

    :ok
  end

  defp drain_dashboard_view(view) do
    render_async(view, 5_000)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp enable_dashboard_engine_inline_resolves! do
    previous_inline? = Application.get_env(:cadence_web, :dashboard_engine_resolve_inline?)
    Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, true)

    on_exit(fn ->
      case previous_inline? do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_resolve_inline?)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, value)
      end
    end)
  end

  describe "widget creation flows" do
    test "adds a widget through the slide-over panel" do
      enable_dashboard_engine_inline_resolves!()

      {conn, user, org, mission} = signed_in_user_org_and_mission()
      binding_set = persist_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()
      assert has_element?(view, "#dashboard-panel")

      view |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()

      view
      |> form("#widget-form", widget: %{type: "value_tile", title: "Counter", mode: "context"})
      |> render_submit()

      render_dashboard_async(view)

      refute has_element?(view, "#dashboard-panel")
      assert has_element?(view, ~s(.grid-stack-item[gs-auto-position="true"]))

      view |> element("#dashboard-versions-button") |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-version-2 [data-version-field="Summary"]),
               "Added widget"
             )

      assert has_element?(
               view,
               ~s(#dashboard-version-2 [data-version-field="Author"]),
               user.user_id
             )

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
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()

      view
      |> form("#widget-form", widget: %{type: "event_timeline", title: "Mission Events"})
      |> render_submit()

      render_dashboard_async(view)

      refute has_element?(view, "#dashboard-panel")
      assert has_element?(view, ~s([data-event-timeline]))

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
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()
      binding_set = persist_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()
      view |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()

      view
      |> form("#widget-form",
        widget: %{type: "state_timeline", title: "Counter State", mode: "context"}
      )
      |> render_submit()

      render_dashboard_async(view)

      refute has_element?(view, "#dashboard-panel")
      assert has_element?(view, ~s([data-state-timeline]))

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
      enable_dashboard_engine_inline_resolves!()

      {conn, user, org, mission} = signed_in_user_org_and_mission()
      binding_set = persist_matrix_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()

      view
      |> form("#widget-form",
        widget: %{
          type: "status_matrix",
          title: "HK Matrix",
          mode: "context",
          precision: "0"
        }
      )
      |> render_change()

      view |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()
      view |> element(~s(button[phx-value-point-id="HK.voltage"])) |> render_click()

      assert has_element?(view, ~s([data-selected-point="HK.counter"]))
      assert has_element?(view, ~s([data-selected-point="HK.voltage"]))

      view
      |> form("#widget-form",
        widget: %{
          type: "status_matrix",
          title: "HK Matrix",
          mode: "context",
          precision: "0"
        }
      )
      |> render_submit()

      render_dashboard_async(view)
      refute has_element?(view, "#dashboard-panel")
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
      enable_dashboard_engine_inline_resolves!()

      {conn, user, org, mission} = signed_in_user_org_and_mission()
      binding_set = persist_matrix_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()

      view
      |> form("#widget-form",
        widget: %{
          type: "data_table",
          title: "HK Table",
          mode: "context",
          precision: "1"
        }
      )
      |> render_change()

      view |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()
      view |> element(~s(button[phx-value-point-id="HK.voltage"])) |> render_click()

      assert has_element?(view, ~s([data-selected-point="HK.counter"]))
      assert has_element?(view, ~s([data-selected-point="HK.voltage"]))

      view
      |> form("#widget-form",
        widget: %{
          type: "data_table",
          title: "HK Table",
          mode: "context",
          precision: "1"
        }
      )
      |> render_submit()

      render_dashboard_async(view)
      refute has_element?(view, "#dashboard-panel")
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
end
