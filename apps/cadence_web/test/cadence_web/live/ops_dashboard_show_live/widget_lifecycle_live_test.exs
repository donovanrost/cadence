defmodule CadenceWeb.OpsDashboardShowLive.WidgetLifecycleLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.Document
  alias Cadence.Ingress.RawEvidence
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

  defp value_tile(point_id, mode \\ :context, spacecraft_id \\ nil) do
    %{
      type: :value_tile,
      title: "Counter",
      binding: %{mode: mode, spacecraft_id: spacecraft_id, point_id: point_id}
    }
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

    {:ok, persisted} = Cadence.persist_binding_set(org.organization_id, binding_set)
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

  defp ingest!(mission, binding_set, spacecraft_id, value, unix_seconds, opts \\ []) do
    evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: DateTime.from_unix!(unix_seconds, :second),
        raw: build_space_packet(42, 1, <<value::16>>)
      })

    with {:ok, result} <-
           Cadence.process_telemetry_ingress(
             evidence,
             binding_set.binding_set_id,
             binding_set.version
           ) do
      Cadence.Persistence.persist_processing_result(result, opts)
    end
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
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

  defp placement_by_title(%Document{} = document, title) do
    Enum.find(document.placements, &(&1.widget_def.title == title))
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

  describe "widget lifecycle flows" do
    test "reloads the latest dashboard when a stale widget edit conflicts" do
      {conn, org, mission} = signed_in_org_and_mission()
      binding_set = persist_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert {:ok, %Document{} = _current} =
               Cadence.Dashboards.update_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %Document{dashboard | name: "Power Updated"},
                 expected_version: Document.version(dashboard)
               )

      view |> element("#add-widget-button") |> render_click()
      view |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()

      html =
        view
        |> form("#widget-form", widget: %{type: "value_tile", title: "Counter", mode: "context"})
        |> render_submit()

      assert html =~ "Dashboard changed in another session"
      assert has_element?(view, "h1", "Power Updated")

      document = fetch_dashboard_document!(org, mission, dashboard)

      assert document.name == "Power Updated"
      assert document.placements == []
      assert Document.version(document) == 2
    end

    test "edit mode persists layout changes and pauses live data" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Gamma")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 1234, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Power",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      initial_document = fetch_dashboard_document!(org, mission, dashboard)
      widget_id = placement_by_title(initial_document, "Counter").placement_id
      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)
      assert has_element?(view, "#widget-#{widget_id} [data-widget-value]", "1234")

      view |> element("#edit-layout-toggle") |> render_click()
      assert has_element?(view, "#edit-paused-note")

      # Layout changes autosave while editing.
      view
      |> element("#dashboard-grid-#{dashboard.dashboard_id}")
      |> render_hook("layout_changed", %{
        "layouts" => [%{"widget_id" => widget_id, "x" => 2, "y" => 1, "w" => 6, "h" => 3}]
      })

      document = fetch_dashboard_document!(org, mission, dashboard)

      assert [%{placement_id: ^widget_id, layout: %{x: 2, y: 1, w: 6, h: 3}}] =
               document.placements

      assert Document.version(document) == 2
      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Updated layout"
      assert version.created_by == user.user_id

      assert has_element?(view, ~s(.grid-stack-item[gs-x="2"][gs-y="1"][gs-w="6"][gs-h="3"]))

      # Live data is frozen while editing…
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5678, 1_700_000_110)
      send(view.pid, :tick)
      render_dashboard_async(view)
      assert has_element?(view, "#widget-#{widget_id} [data-widget-value]", "1234")
      refute has_element?(view, "#widget-#{widget_id} [data-widget-value]", "5678")

      # …and resumes when editing ends.
      view |> element("#edit-layout-toggle") |> render_click()
      render_dashboard_async(view)
      refute has_element?(view, "#edit-paused-note")
      assert has_element?(view, "#widget-#{widget_id} [data-widget-value]", "5678")
    end

    test "removes and reconfigures widgets in edit mode" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      binding_set = persist_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Power",
          widgets: [
            Map.put(value_tile("HK.counter"), :layout, %{x: 0, y: 0, w: 4, h: 2}),
            %{type: :constellation_health, title: "Fleet", binding: %{mode: :constellation}}
          ]
        )

      initial_document = fetch_dashboard_document!(org, mission, dashboard)

      tile = placement_by_title(initial_document, "Counter")
      fleet = placement_by_title(initial_document, "Fleet")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#edit-layout-toggle") |> render_click()

      # Reconfigure: prefilled form, save preserves placement identity and layout.
      view
      |> element(
        ~s(button[phx-click="open_widget_config"][phx-value-widget-id="#{tile.placement_id}"])
      )
      |> render_click()

      assert has_element?(view, ~s(#widget-form input[name="widget[title]"][value="Counter"]))

      view
      |> form("#widget-form",
        widget: %{type: "value_tile", title: "Renamed Tile", mode: "context"}
      )
      |> render_submit()

      render_dashboard_async(view)

      document = fetch_dashboard_document!(org, mission, dashboard)

      renamed = placement_by_title(document, "Renamed Tile")
      assert renamed.placement_id == tile.placement_id
      assert Map.take(renamed.layout, [:x, :y, :w, :h]) == %{x: 0, y: 0, w: 4, h: 2}

      assert Document.version(document) == 2
      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Updated widget"
      assert version.created_by == user.user_id

      # Remove the constellation widget.
      view
      |> element(
        ~s(button[phx-click="remove_widget"][phx-value-widget-id="#{fleet.placement_id}"])
      )
      |> render_click()

      render_dashboard_async(view)

      document = fetch_dashboard_document!(org, mission, dashboard)
      widget_id = tile.placement_id

      assert [%{placement_id: ^widget_id}] = document.placements
      assert Document.version(document) == 3
      version = fetch_dashboard_version!(org, mission, dashboard, 3)
      assert version.change_summary == "Removed widget"
      assert version.created_by == user.user_id
    end
  end
end
