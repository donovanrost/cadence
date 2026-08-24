defmodule CadenceWeb.OpsDashboardShowLive.LiveWidgetLimitEventNavigationLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest
  use CadenceWeb.OpsDashboardShowLive.ViewTestSupport, data_link_selectors_only: true

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Dashboards.{Document, RenderItem}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.Definition
  alias Cadence.Telemetry.PacketDefinition
  alias CadenceWeb.TestFixtures

  defp assert_widget_data_link_item(rendered, component_id, expected_attrs) do
    presentation = widget_data_link_presentation(rendered, component_id)
    assert presentation
    assert presentation["component_id"] == component_id

    item =
      Enum.find(presentation["items"], fn item ->
        Enum.all?(expected_attrs, fn {name, value} -> item["attrs"][name] == value end)
      end)

    assert item
    item
  end

  defp click_widget_data_link(view, component_id, expected_attrs) do
    item = assert_widget_data_link_item(view, component_id, expected_attrs)

    payload =
      item["attrs"]
      |> Enum.flat_map(fn
        {"phx-value-" <> name, value} -> [{name, value}]
        {_name, _value} -> []
      end)
      |> Map.new()

    render_hook(view, item["attrs"]["phx-click"], payload)
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp persist_binding_set!(org, mission) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission.mission_id,
        packet_definition_id: "hk-limit-event",
        packet_name: "HK",
        apid: 46,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-limit-event-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 46,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp ingest!(mission, binding_set, spacecraft_id, value, unix_seconds) do
    evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: DateTime.from_unix!(unix_seconds, :second),
        raw: build_space_packet(46, 1, <<value::16>>)
      })

    {:ok, _result} =
      Cadence.process_and_persist_telemetry_ingress(
        evidence,
        binding_set.binding_set_id,
        binding_set.version
      )
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
  end

  defp evaluate_limits!(mission) do
    limit_definition =
      Definition.new(%{
        mission_id: mission.mission_id,
        limit_definition_id: "counter-limits",
        point_id: "HK.counter",
        thresholds: %{"yellow_high" => 10, "red_high" => 20}
      })

    {:ok, _definition} = Cadence.Limits.persist_limit_definition(limit_definition)
    {:ok, _run} = Cadence.Limits.evaluate(mission.mission_id)
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

  defp render_item_by_title(%Document{} = document, title) do
    document
    |> RenderItem.from_document()
    |> Enum.find(&(&1.widget.title == title))
  end

  defp disable_telemetry_storage_runtime_invalidation! do
    previous_config = Application.get_env(:cadence, :telemetry_storage, [])

    Application.put_env(
      :cadence,
      :telemetry_storage,
      Keyword.put(previous_config, :dashboard_runtime_invalidation?, false)
    )

    on_exit(fn ->
      Application.put_env(:cadence, :telemetry_storage, previous_config)
    end)
  end

  describe "live widget limit event navigation" do
    test "opens a value-tile limit event and navigates to its definition" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 25, 1_700_000_500)
      evaluate_limits!(mission)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Power",
          widgets: [
            %{
              type: :value_tile,
              title: "Counter",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_id: "HK.counter"
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      value_widget = render_item_by_title(document, "Counter").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      html = render_dashboard_async(view)

      assert html =~ "25"
      assert html =~ "Red"

      component_id = "widget-data-links-#{value_widget.widget_id}-component"
      assert widget_data_link_presentation(view, component_id)

      assert_widget_data_link_item(view, component_id, %{
        "data-widget-data-link-target" => "limit event"
      })

      click_widget_data_link(view, component_id, %{
        "data-widget-data-link-target" => "limit event"
      })

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="limit_event"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Normalized state"]),
               "red"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-related-target="limit definition"])
             )

      click_data_link_inspector_element(
        view,
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="limit definition"])
      )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="limit_definition"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Definition"]),
               "counter-limits"
             )
    end
  end
end
