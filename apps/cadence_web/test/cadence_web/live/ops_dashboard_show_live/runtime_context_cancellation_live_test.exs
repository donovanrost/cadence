defmodule CadenceWeb.OpsDashboardShowLive.RuntimeContextCancellationLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
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

  defp delay_dashboard_engine_resolves!(delay_ms) do
    previous_delay = Application.get_env(:cadence_web, :dashboard_engine_resolve_test_delay_ms)
    previous_inline? = Application.get_env(:cadence_web, :dashboard_engine_resolve_inline?)

    Application.put_env(:cadence_web, :dashboard_engine_resolve_test_delay_ms, delay_ms)
    Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, false)

    on_exit(fn ->
      case previous_delay do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_resolve_test_delay_ms)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_resolve_test_delay_ms, value)
      end

      case previous_inline? do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_resolve_inline?)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, value)
      end
    end)
  end

  describe "runtime context cancellation diagnostics" do
    test "context changes cancel obsolete in-flight dashboard resolves" do
      delay_dashboard_engine_resolves!(100)

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Cancel")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Runtime Cancel",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))

      view
      |> element("#runtime-context-form")
      |> render_change(%{
        "time_mode" => "archive",
        "from" => "2026-06-17T12:00:00Z",
        "to" => "2026-06-17T12:05:00Z",
        "realm" => "flight",
        "limit_mode" => "current"
      })

      patched_path = assert_patch(view)
      assert patched_path =~ "time_mode=archive"
      assert patched_path =~ "limit_mode=current"

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-decision-actions*="cancel_obsolete"][data-runtime-decision-actions*="start_resolve"][data-runtime-decision-actions*="accept_result"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-refresh-status="settled"][data-runtime-refresh-reason="accepted"][data-runtime-visible-refresh-action="accept_result"][data-runtime-refresh-starts*="runtime_context_changed:1"][data-runtime-refresh-cancellations*="runtime_context_changed:1"][data-runtime-canceled-resolves="1"][data-runtime-failed-resolves="0"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="archive"][data-engine-time-mode="archive"][data-dashboard-limit-mode="current"][data-engine-limit-mode="current"])
             )

      view
      |> element("#dashboard-diagnostics-button")
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel[data-runtime-refresh-status="settled"][data-runtime-refresh-reason="accepted"][data-runtime-visible-refresh-action="accept_result"][data-runtime-refresh-starts*="runtime_context_changed:1"][data-runtime-refresh-cancellations*="runtime_context_changed:1"][data-runtime-canceled-resolves="1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel[data-runtime-last-refresh-duration-ms])
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Refresh status"]),
               "settled"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Last refresh duration ms"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Refresh cancellations"]),
               "runtime_context_changed:1"
             )
    end
  end
end
