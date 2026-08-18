defmodule CadenceWeb.OpsDashboardShowLive.WidgetLifecycleLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

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

    on_exit({:ops_dashboard_mission_runtime, mission.mission_id}, fn ->
      _ = Cadence.Runtime.stop_mission(mission.mission_id)
    end)

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
      RuntimePersistence.persist_processing_result(result, opts)
    end
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
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

  defp placement_by_title(%Document{} = document, title) do
    Enum.find(document.placements, &(&1.widget_def.title == title))
  end

  describe "widget lifecycle flows" do
    test "reloads the latest dashboard when a stale widget edit conflicts" do
      {conn, org, mission} = signed_in_org_and_mission()
      binding_set = persist_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      await_dashboard_resolved(view)

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

      view
      |> form("#widget-form", widget: %{type: "value_tile", title: "Counter", mode: "context"})
      |> render_submit()

      await_dashboard_resolved(view)

      view |> element("#dashboard-editor-save") |> render_click()
      await_dashboard_resolved(view)

      assert has_element?(
               view,
               ~s(#dashboard-editor-conflict[data-editor-starting-version="1"][data-editor-current-version="2"])
             )

      assert has_element?(view, ~s(.grid-stack-item[gs-auto-position="true"]))

      document = fetch_dashboard_document!(org, mission, dashboard)

      assert document.name == "Power Updated"
      assert document.placements == []
      assert Document.version(document) == 2

      stop_dashboard_view(view)
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
      await_dashboard_resolved(view)
      assert has_element?(view, "#widget-#{widget_id} [data-widget-value]", "1234")

      assert has_element?(view, "#edit-paused-note")

      # Layout changes remain local until the staged Editor transaction is saved.
      view
      |> element("#dashboard-grid-#{dashboard.dashboard_id}")
      |> render_hook("layout_changed", %{
        "layouts" => [%{"widget_id" => widget_id, "x" => 2, "y" => 1, "w" => 6, "h" => 3}]
      })

      unchanged = fetch_dashboard_document!(org, mission, dashboard)
      assert Document.version(unchanged) == 1
      assert [%{placement_id: ^widget_id, layout: %{x: nil, y: nil}}] = unchanged.placements

      assert has_element?(view, ~s(.grid-stack-item[gs-x="2"][gs-y="1"][gs-w="6"][gs-h="3"]))

      view |> element("#dashboard-editor-save") |> render_click()

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
      await_dashboard_resolved(view)
      assert has_element?(view, "#widget-#{widget_id} [data-widget-value]", "1234")
      refute has_element?(view, "#widget-#{widget_id} [data-widget-value]", "5678")

      # The Editor remains paused after Save; the Viewer resumes live telemetry.
      {:ok, viewer, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
        )

      await_dashboard_resolved(viewer)
      refute has_element?(viewer, "#edit-paused-note")
      assert has_element?(viewer, "#widget-#{widget_id} [data-widget-value]", "5678")

      stop_dashboard_view(viewer)
      stop_dashboard_view(view)
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
      await_dashboard_resolved(view)

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

      await_dashboard_resolved(view)

      assert has_element?(view, ~s(button[aria-label="Configure Renamed Tile"]))
      assert Document.version(fetch_dashboard_document!(org, mission, dashboard)) == 1

      # Remove the constellation widget.
      view
      |> element(
        ~s(button[phx-click="remove_widget"][phx-value-widget-id="#{fleet.placement_id}"])
      )
      |> render_click()

      await_dashboard_resolved(view)

      view |> element("#dashboard-editor-save") |> render_click()
      document = fetch_dashboard_document!(org, mission, dashboard)
      widget_id = tile.placement_id

      assert [%{placement_id: ^widget_id}] = document.placements
      assert Document.version(document) == 2
      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Updated widget; Removed widget"
      assert version.created_by == user.user_id

      stop_dashboard_view(view)
    end
  end
end
