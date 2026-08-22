defmodule CadenceWeb.OpsDashboardShowLive.RuntimeComparisonPresetLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Telemetry.PacketDefinition
  alias CadenceWeb.TestFixtures

  test "comparison investigation presets can be saved loaded and deleted" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Preset")
    binding_set = persist_binding_set!(org, mission)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Runtime Presets",
        widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
      )

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?data_view=all_revisions&compare_data_view=canonical"
      )

    render_dashboard_async(view)

    view
    |> element("#dashboard-comparison-toggle")
    |> render_click()

    assert has_element?(view, "#dashboard-comparison-inspector")
    assert has_element?(view, "#dashboard-comparison-preset-form")

    view
    |> form("#dashboard-comparison-preset-form", %{
      "preset" => %{"name" => "All revisions vs canonical"}
    })
    |> render_submit()

    [preset] =
      Cadence.Dashboards.list_dashboard_investigation_presets(
        org.organization_id,
        mission.mission_id,
        dashboard.dashboard_id
      )

    assert preset.created_by == user.user_id
    assert preset.name == "All revisions vs canonical"
    assert preset.runtime_query["data_view"] == "all_revisions"
    assert preset.runtime_query["compare_data_view"] == "canonical"

    assert has_element?(
             view,
             ~s([data-dashboard-comparison-saved-preset="#{preset.dashboard_investigation_preset_id}"])
           )

    view
    |> element("#runtime-context-form")
    |> render_change(%{
      "time_mode" => "live",
      "from" => "",
      "to" => "",
      "realm" => "flight",
      "data_view" => "canonical",
      "compare_data_view" => "",
      "limit_mode" => "observed"
    })

    assert_patch(view, show_path(mission, dashboard))
    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s([data-dashboard-comparison-saved-preset-apply="#{preset.dashboard_investigation_preset_id}"])
           )

    view
    |> element(
      ~s([data-dashboard-comparison-saved-preset-apply="#{preset.dashboard_investigation_preset_id}"])
    )
    |> render_click()

    patched_path = assert_patch(view)
    assert patched_path =~ "data_view=all_revisions"
    assert patched_path =~ "compare_data_view=canonical"

    render_dashboard_async(view)

    view
    |> element(
      ~s([data-dashboard-comparison-saved-preset-delete="#{preset.dashboard_investigation_preset_id}"])
    )
    |> render_click()

    assert [] =
             Cadence.Dashboards.list_dashboard_investigation_presets(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
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
end
