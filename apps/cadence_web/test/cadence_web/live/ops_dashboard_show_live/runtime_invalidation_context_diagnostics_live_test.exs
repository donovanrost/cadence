defmodule CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationContextDiagnosticsLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}

  alias Cadence.Dashboards.RuntimeCache

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

  describe "runtime invalidation context and diagnostics surfaces" do
    test "runtime context resolves reuse source result and frame caches" do
      enable_dashboard_runtime_cache!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Cache")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Runtime Cache",
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
               ~s(#ops-dashboard-show-page[data-engine-source-cache-statuses*="miss"][data-engine-frame-cache-statuses*="miss"])
             )

      refute has_element?(view, "#dashboard-source-health")

      view
      |> element("#runtime-context-form")
      |> render_change(%{
        "time_mode" => "live",
        "from" => from,
        "to" => to,
        "realm" => "flight",
        "limit_mode" => "observed"
      })

      assert_patch(view, show_path(mission, dashboard))
      render_dashboard_async(view)

      view
      |> element("#runtime-context-form")
      |> render_change(%{
        "time_mode" => "archive",
        "from" => from,
        "to" => to,
        "realm" => "flight",
        "limit_mode" => "current"
      })

      patched_path = assert_patch(view)
      assert patched_path =~ "time_mode=archive"
      assert patched_path =~ "limit_mode=current"

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-source-cache-statuses*="hit"][data-engine-frame-cache-statuses*="hit"])
             )

      refute has_element?(view, "#dashboard-source-health")
    end
  end
end
