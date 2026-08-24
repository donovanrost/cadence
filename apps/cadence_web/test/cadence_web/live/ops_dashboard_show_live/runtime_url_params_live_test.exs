defmodule CadenceWeb.OpsDashboardShowLive.RuntimeUrlParamsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.{Document, RenderItem}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Telemetry.PacketDefinition
  alias CadenceWeb.TestFixtures

  test "URL runtime params drive dashboard engine contexts" do
    {conn, org, mission} = signed_in_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Runtime")
    binding_set = persist_binding_set!(org, mission)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)
    widget = value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Runtime",
        widgets: [widget]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    runtime_item = render_item_by_title(document, "Counter")

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=archive&time_axis=generation_time&from=2026-06-17T12:00:00Z&to=2026-06-17T12:05:00Z&limit_mode=current&data_view=all_revisions&compare_data_view=canonical"
      )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="archive"][data-dashboard-time-axis="generation_time"][data-engine-time-mode="archive"][data-engine-time-axis="generation_time"][data-dashboard-data-view="all_revisions"][data-dashboard-compare-data-view="canonical"][data-engine-data-view="all_revisions"][data-compare-engine-data-view="canonical"][data-dashboard-limit-mode="current"][data-engine-limit-mode="current"])
           )

    runtime_controls = dashboard_runtime_controls(view)

    assert dashboard_runtime_option(runtime_controls, "dashboard-time-axis", "generation_time")
    assert dashboard_runtime_option(runtime_controls, "dashboard-time-axis", "receipt_time")
    assert dashboard_runtime_option(runtime_controls, "dashboard-data-view", "all_revisions")

    assert dashboard_runtime_option(
             runtime_controls,
             "dashboard-compare-data-view",
             "canonical"
           )

    warning_component_id =
      "widget-#{runtime_item.widget.widget_id}-engine-warning-0-component"

    warning =
      widget_warning_presentation(view, runtime_item.widget.widget_id, warning_component_id)

    assert warning["component_id"] == warning_component_id

    assert warning["trigger"]["badge"] == %{
             "attrs" => %{
               "data-engine-warning" => "all_revisions_view",
               "title" => "Telemetry source is showing all observation revisions"
             },
             "class" => "badge badge-xs cursor-pointer badge-warning",
             "text" => "All revisions"
           }

    header = widget_header_presentation(view, runtime_item.widget.widget_id)
    assert header["root"]["attrs"]["data-data-management-badges"] =~ "all_revisions"

    refute dashboard_runtime_option(runtime_controls, "dashboard-limit-mode", "observed")[
             "disabled"
           ]

    refute dashboard_runtime_option(runtime_controls, "dashboard-limit-mode", "current")[
             "disabled"
           ]

    refute dashboard_runtime_option(runtime_controls, "dashboard-limit-mode", "recomputed")[
             "disabled"
           ]

    refute dashboard_runtime_option(runtime_controls, "dashboard-limit-mode", "compare")[
             "disabled"
           ]

    refute runtime_controls["form"]["semantics"]["badge"]

    send(view.pid, :tick)
    render(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-runtime-status="idle"][data-runtime-decision-actions="noop"][data-runtime-resolved="true"])
           )

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-runtime-refresh-status="suppressed"][data-runtime-refresh-reason="not_live_time_mode"][data-runtime-visible-refresh-action="noop"][data-runtime-refresh-noops="live_tick:not_live_time_mode:1"][data-runtime-canceled-resolves="0"][data-runtime-failed-resolves="0"])
           )

    render_dashboard_runtime_change(view, runtime_controls, %{
      "dashboard-time-mode" => "live",
      "dashboard-data-form-from" => "2026-06-17T12:00:00Z",
      "dashboard-data-form-to" => "2026-06-17T12:05:00Z",
      "dashboard-data-realm" => "flight",
      "dashboard-data-view" => "canonical",
      "dashboard-compare-data-view" => "",
      "dashboard-limit-mode" => "observed"
    })

    assert_patch(view, show_path(mission, dashboard))

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"][data-dashboard-data-view="canonical"][data-engine-data-view="canonical"][data-engine-limit-mode="observed"])
           )

    {:ok, invalid_view, _html} =
      live(conn, show_path(mission, dashboard) <> "?data_view=unsupported")

    render_dashboard_async(invalid_view)

    assert has_element?(
             invalid_view,
             ~s(#ops-dashboard-show-page[data-dashboard-data-view="canonical"][data-engine-data-view="canonical"])
           )
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp value_tile(point_id, mode, spacecraft_id) do
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
end
