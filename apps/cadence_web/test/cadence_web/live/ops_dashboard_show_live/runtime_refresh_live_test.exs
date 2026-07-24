defmodule CadenceWeb.OpsDashboardShowLive.RuntimeRefreshLiveTest do
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

  defp ingest!(mission, binding_set, spacecraft_id, value, unix_seconds, opts) do
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

  describe "dashboard runtime refresh" do
    test "ticks push chart appends for new samples only" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Beta")
      binding_set = persist_binding_set!(org, mission)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100,
        dashboard_runtime_invalidation?: false
      )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Trend",
          widgets: [
            %{
              type: :time_series,
              title: "Counter Trend",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_id: "HK.counter"
              }
            }
          ]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert {:ok, document} =
               Cadence.Dashboards.fetch_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )

      assert [%{placement_id: placement_id}] = document.placements

      # The mount-time sample is already in the chart backfill, so the first
      # tick must not re-append it as a duplicate point.
      send(view.pid, :tick)
      render_dashboard_async(view)
      refute_push_event(view, "tlm:append", %{"series" => %{^placement_id => _data}})

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 7, 1_700_000_110,
        dashboard_runtime_invalidation?: false
      )

      send(view.pid, :tick)
      render_dashboard_async(view)

      assert_push_event(
        view,
        "tlm:append",
        %{
          "series" => %{
            ^placement_id => %{
              version: 1,
              series: [
                %{
                  id: "HK.counter",
                  observable_id: "HK.counter",
                  points: [[_ts, 7, %{sample_id: sample_id, link_id: link_id}]]
                }
              ]
            }
          }
        },
        1_000
      )

      assert is_binary(sample_id)
      assert is_binary(link_id)

      send(view.pid, :tick)
      render_dashboard_async(view)
      refute_push_event(view, "tlm:append", %{"series" => %{^placement_id => _data}})
    end

    test "ticks run conservative dashboard engine live refresh" do
      disable_telemetry_storage_runtime_invalidation!()
      enable_dashboard_runtime_cache!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Engine")
      binding_set = persist_binding_set!(org, mission)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100,
        dashboard_runtime_invalidation?: false
      )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Engine Tick",
          widgets: [
            value_tile("HK.counter", :fixed, spacecraft.spacecraft_id),
            %{
              type: :time_series,
              title: "Counter Trend",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_id: "HK.counter"
              }
            }
          ]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="initial"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-status="idle"][data-runtime-decision-actions="start_resolve accept_result"][data-runtime-resolved="true"])
             )

      assert has_element?(view, ~s([data-engine-backed="true"]))

      assert has_element?(
               view,
               ~s([phx-hook="TelemetryChart"][data-engine-backed="true"])
             )

      assert render(view) =~ "5"

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 9, 1_700_000_110,
        dashboard_runtime_invalidation?: false
      )

      send(view.pid, :tick)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="live_tick"][data-engine-source-requests="3"][data-engine-executed-source-requests="2"][data-engine-skipped-source-requests="1"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-refresh-status="settled"][data-runtime-refresh-reason="accepted"][data-runtime-visible-refresh-action="accept_result"][data-runtime-refresh-starts="live_tick:tick:1"][data-runtime-canceled-resolves="0"][data-runtime-failed-resolves="0"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-last-refresh-duration-ms])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-source-cache-statuses*="stale"][data-engine-frame-cache-statuses*="refresh"])
             )

      refute has_element?(view, "#dashboard-source-health")

      view
      |> element("#dashboard-diagnostics-button")
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-cache-summary[data-cache-classification="stale"][data-cache-source*="stale"][data-cache-frame*="refresh"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-cache-summary [data-cache-field="Source"]),
               "stale"
             )

      assert has_element?(
               view,
               ~s(#dashboard-cache-evidence[data-cache-evidence-count][data-cache-evidence-resolved][data-cache-evidence-context-only][data-cache-evidence-missing])
             )

      assert has_element?(
               view,
               ~s(#dashboard-cache-evidence [data-cache-evidence-state-field="Resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-cache-evidence [data-cache-evidence-layer="source"][data-cache-evidence-status="stale"][data-cache-evidence-state="resolved"][data-cache-evidence-request-id][data-cache-evidence-source-binding-id][data-cache-evidence-data-source-id])
             )

      assert has_element?(
               view,
               ~s(#dashboard-cache-evidence [data-cache-evidence-layer="source"][data-cache-evidence-status="stale"][data-cache-evidence-incident-status="cache_stale"][data-cache-evidence-incident-severity="warning"][data-cache-evidence-incident-action="wait_for_refresh"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-cache-evidence [data-cache-evidence-field="Action"]),
               "wait_for_refresh"
             )

      assert has_element?(
               view,
               ~s(#dashboard-cache-evidence [data-cache-evidence-layer="frame"][data-cache-evidence-status="refresh"][data-cache-evidence-request-id][data-cache-evidence-placement-id])
             )

      view
      |> element(
        ~s(#dashboard-cache-evidence [data-cache-evidence-layer="source"][data-cache-evidence-status="stale"][data-cache-evidence-source="limits"] [data-cache-evidence-open])
      )
      |> render_click()

      source_evidence_path = assert_patch(view)
      assert source_evidence_path =~ "panel=evidence"
      assert source_evidence_path =~ "selected_evidence_kind=source"
      assert source_evidence_path =~ "selected_source_evidence_mode=execution"
      assert source_evidence_path =~ "selected_source_request="
      assert source_evidence_path =~ "selected_logical_source=limits"
      assert source_evidence_path =~ "selected_requested_data_source="
      refute source_evidence_path =~ "selected_target="

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="source"][data-evidence-status="cache_stale"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Execution status"]),
               "cache_stale"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=source"][data-clipboard-text*="selected_source_request="])
             )

      {:ok, context_only_view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?panel=evidence&selected_evidence_kind=source&selected_source_evidence_mode=health&selected_source_evidence_state=context_only&selected_cache_evidence_layer=source&selected_cache_evidence_status=hit&selected_cache_evidence_reasons=operator_requested&selected_source_request=missing-cache-source&selected_logical_source=telemetry&selected_realm=flight&selected_data_source=managed_questdb_primary&selected_source_binding=default_flight_telemetry"
        )

      render_dashboard_async(context_only_view)

      assert has_element?(
               context_only_view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="source"][data-evidence-status="context_only"])
             )

      assert has_element?(
               context_only_view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Source request"]),
               "missing-cache-source"
             )

      assert has_element?(
               context_only_view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Cache evidence status"]),
               "hit"
             )

      assert has_element?(
               context_only_view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="selected_source_evidence_state=context_only"][data-clipboard-text*="selected_cache_evidence_status=hit"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-source-execution-actions="refresh_source_result:2"][data-runtime-source-execution-retryable="2"][data-runtime-source-execution-actionable="0"][data-runtime-source-execution-degraded="0"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-status="idle"][data-runtime-decision-actions="start_resolve accept_result"][data-runtime-resolved="true"])
             )

      assert has_element?(view, ~s([data-engine-backed="true"]))
      assert render(view) =~ "9"
    end
  end
end
