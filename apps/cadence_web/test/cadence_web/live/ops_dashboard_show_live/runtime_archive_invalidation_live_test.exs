defmodule CadenceWeb.OpsDashboardShowLive.RuntimeArchiveInvalidationLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.{RuntimeCache, RuntimeInvalidation}
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

  defp enable_dashboard_runtime_cache! do
    previous_config = Application.get_env(:cadence, :dashboard_runtime_cache)
    Application.put_env(:cadence, :dashboard_runtime_cache, enabled?: true)

    if is_nil(Process.whereis(RuntimeCache)) do
      start_supervised!(RuntimeCache)
    end

    RuntimeCache.reset()

    on_exit(fn ->
      RuntimeCache.reset()

      case previous_config do
        nil -> Application.delete_env(:cadence, :dashboard_runtime_cache)
        value -> Application.put_env(:cadence, :dashboard_runtime_cache, value)
      end
    end)
  end

  test "archive dashboard resolves when scoped runtime invalidation broadcasts" do
    enable_dashboard_runtime_cache!()

    {conn, org, mission} = signed_in_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Invalidation")
    binding_set = persist_binding_set!(org, mission)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Runtime Invalidation",
        widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
      )

    from = DateTime.from_unix!(1_700_000_095, :second) |> DateTime.to_iso8601()
    to = DateTime.from_unix!(1_700_000_105, :second) |> DateTime.to_iso8601()

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=archive&from=#{from}&to=#{to}&limit_mode=current"
      )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="archive"][data-engine-time-mode="archive"])
           )

    assert %{plans: 0, source_results: _source_results, frames: _frames} =
             RuntimeInvalidation.historical_data_changed(
               %{
                 organization_id: mission.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 time_range: %{from: from, to: to}
               },
               runtime_cache: RuntimeCache
             )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="historical_data_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
           )
  end

  test "live dashboard refreshes when dashboard version invalidation broadcasts lifecycle action" do
    enable_dashboard_runtime_cache!()

    {conn, org, mission} = signed_in_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Version")
    binding_set = persist_binding_set!(org, mission)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Version Invalidation",
        widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
      )

    {:ok, view, _html} = live(conn, show_path(mission, dashboard))
    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"])
           )

    assert %{plans: _plans, source_results: 0, frames: 0} =
             RuntimeInvalidation.dashboard_version_changed(
               %{
                 organization_id: mission.organization_id,
                 mission_id: mission.mission_id,
                 dashboard_id: dashboard.dashboard_id,
                 document_version: 2,
                 lifecycle_action: :published
               },
               runtime_cache: RuntimeCache
             )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="dashboard_version_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
           )

    assert has_element?(view, ~s(#dashboard-diagnostics-button[href*="/diagnostics"]))
  end
end
