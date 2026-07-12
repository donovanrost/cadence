defmodule CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationReplayDiagnosticsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.{DataBinding, DataSource, DataSources, RuntimeInvalidation}
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

  defp persist_dashboard_realm!(
         mission,
         realm,
         capabilities \\ %{range_scan?: true, latest?: true}
       ) do
    data_source_id = "test-#{realm}-questdb-#{System.unique_integer([:positive])}"

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: capabilities
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "test-#{realm}-binding-#{System.unique_integer([:positive])}",
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               realm: realm,
               logical_source: :telemetry,
               data_source_id: data_source_id,
               dataset: to_string(realm),
               priority: 0
             })

    %{data_source_id: data_source_id}
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

  defp reset_runtime_health! do
    Cadence.reset_runtime_health()

    on_exit(fn ->
      Cadence.reset_runtime_health()
    end)
  end

  defp emit_runtime_invalidation!(measurements, metadata) do
    :telemetry.execute(RuntimeInvalidation.telemetry_event(), measurements, metadata)

    # The runtime-health telemetry handler casts into the supervised process.
    # A snapshot call from the same process is ordered after that cast.
    Cadence.runtime_health_snapshot()
  end

  defp emit_runtime_invalidation_decision!(metadata, decision) do
    metadata =
      metadata
      |> Map.put(:decision, decision)
      |> Map.merge(Map.take(decision, runtime_invalidation_decision_keys()))

    :telemetry.execute(RuntimeInvalidation.decision_telemetry_event(), %{total: 1}, metadata)

    Cadence.runtime_health_snapshot()
  end

  defp runtime_invalidation_decision_keys do
    [
      :dashboard_id,
      :organization_id,
      :mission_id,
      :matches?,
      :dashboard_matches?,
      :context_matches?,
      :context_reason,
      :refresh_allowed?,
      :refresh_reason,
      :affected_placement_count,
      :affected_placement_ids,
      :affected_widget_type_ids,
      :affected_impact_reasons,
      :decision_status
    ]
  end

  defp runtime_invalidation_test_event_id(boundary, mission_id, observable, total, occurred_at) do
    [
      boundary,
      mission_id,
      observable,
      total,
      DateTime.to_iso8601(occurred_at)
    ]
    |> Enum.map_join("-", &runtime_invalidation_test_value/1)
    |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")
  end

  defp runtime_invalidation_test_value(nil), do: "-"
  defp runtime_invalidation_test_value(value) when is_atom(value), do: Atom.to_string(value)
  defp runtime_invalidation_test_value(value) when is_integer(value), do: Integer.to_string(value)
  defp runtime_invalidation_test_value(value) when is_binary(value), do: value

  describe "replay runtime invalidation diagnostics" do
    test "operator surface exposes replay invalidation context matching" do
      {conn, _org, mission} = signed_in_org_and_mission()

      spacecraft =
        TestFixtures.persist_spacecraft!(mission, display_name: "SC Replay Diagnostics")

      _source = persist_dashboard_realm!(mission, :replay)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Replay Invalidation Diagnostics",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      reset_runtime_health!()

      emit_runtime_invalidation!(
        %{plans: 0, source_results: 1, frames: 1, total: 2},
        %{
          boundary: :historical_data_changed,
          domain_fact: :historical_data_changed,
          layers: [:source_result, :frame],
          filters: %{
            organization_id: mission.organization_id,
            mission_id: mission.mission_id,
            logical_source: :telemetry,
            observable: "HK.counter",
            replay_run_id: "replay_run_001"
          }
        }
      )

      emit_runtime_invalidation!(
        %{plans: 0, source_results: 3, frames: 3, total: 6},
        %{
          boundary: :historical_data_changed,
          domain_fact: :historical_data_changed,
          layers: [:source_result, :frame],
          filters: %{
            organization_id: mission.organization_id,
            mission_id: mission.mission_id,
            logical_source: :telemetry,
            observable: "HK.counter",
            replay_run_id: "replay_run_002"
          }
        }
      )

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?time_mode=replay_run&replay_run_id=replay_run_001"
        )

      render_dashboard_async(view)

      view
      |> element("#dashboard-diagnostics-button")
      |> render_click()

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-invalidation-events="2"][data-runtime-invalidation-artifacts="8"][data-runtime-invalidation-boundaries*="historical_data_changed:2"][data-runtime-invalidation-context-matches="1"][data-runtime-invalidation-context-filtered="1"][data-runtime-invalidation-context-filter-reasons*="replay_run_mismatch:1"][data-runtime-invalidation-refresh-allowed="0"][data-runtime-invalidation-refresh-suppressed="2"][data-runtime-invalidation-refresh-suppress-reasons*="stale_for_context:2"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel[data-runtime-invalidation-events="2"][data-runtime-invalidation-artifacts="8"][data-runtime-invalidation-boundaries*="historical_data_changed:2"][data-runtime-invalidation-context-matches="1"][data-runtime-invalidation-context-filtered="1"][data-runtime-invalidation-context-filter-reasons*="replay_run_mismatch:1"][data-runtime-invalidation-refresh-allowed="0"][data-runtime-invalidation-refresh-suppressed="2"][data-runtime-invalidation-refresh-suppress-reasons*="stale_for_context:2"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-summary[data-no-refresh-status="mixed_context_suppressed"][data-no-refresh-context="Context: filtered by replay run:1"][data-no-refresh-refresh="Refresh: stale before current context:2"]),
               "Some invalidations were filtered; matched invalidations were suppressed."
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="historical_data_changed"][data-runtime-invalidation-replay-run-id="replay_run_001"][data-runtime-invalidation-context-match="true"][data-runtime-invalidation-context-reason="matched"][data-runtime-invalidation-refresh-allowed="false"][data-runtime-invalidation-refresh-allowed-reason="stale_for_context"][data-runtime-invalidation-artifacts="2"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="historical_data_changed"][data-runtime-invalidation-replay-run-id="replay_run_002"][data-runtime-invalidation-context-match="false"][data-runtime-invalidation-context-reason="replay_run_mismatch"][data-runtime-invalidation-refresh-allowed="false"][data-runtime-invalidation-refresh-allowed-reason="stale_for_context"][data-runtime-invalidation-artifacts="6"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_001"] [data-invalidation-field="Replay"]),
               "replay_run_001"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_002"] [data-invalidation-field="Context"]),
               "false"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Context filtered"]),
               "1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Context filter reasons"]),
               "filtered by replay run:1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Refresh suppressed"]),
               "2"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Refresh suppress reasons"]),
               "stale before current context:2"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_002"] [data-invalidation-field="Context reason"]),
               "filtered by replay run"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_001"] [data-invalidation-field="Allowed reason"]),
               "stale before current context"
             )
    end

    test "operator diagnostics surface persisted runtime invalidation decisions" do
      {conn, _org, mission} = signed_in_org_and_mission()

      spacecraft =
        TestFixtures.persist_spacecraft!(mission, display_name: "SC Persisted Decision")

      _source = persist_dashboard_realm!(mission, :replay)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Persisted Invalidation Decision",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      reset_runtime_health!()

      occurred_at = ~U[2026-06-24 12:00:00Z]

      invalidation_metadata = %{
        boundary: :historical_data_changed,
        domain_fact: :historical_data_changed,
        layers: [:source_result, :frame],
        occurred_at: occurred_at,
        filters: %{
          organization_id: mission.organization_id,
          mission_id: mission.mission_id,
          logical_source: :telemetry,
          observable: "HK.counter",
          replay_run_id: "replay_run_001"
        }
      }

      emit_runtime_invalidation!(
        %{plans: 0, source_results: 1, frames: 1, total: 2},
        invalidation_metadata
      )

      invalidation_event_id =
        runtime_invalidation_test_event_id(
          :historical_data_changed,
          mission.mission_id,
          "HK.counter",
          2,
          occurred_at
        )

      persisted_decision = %{
        dashboard_id: dashboard.dashboard_id,
        organization_id: mission.organization_id,
        mission_id: mission.mission_id,
        affected_placement_count: 1,
        affected_placement_ids: ["placement-persisted-decision"],
        affected_widget_type_ids: ["cadence.value_tile"],
        affected_impact_reasons: [:primary_source],
        matches?: false,
        dashboard_matches?: true,
        context_matches?: false,
        context_reason: :replay_run_mismatch,
        refresh_allowed?: false,
        refresh_reason: :stale_for_context,
        decision_status: :filtered
      }

      persisted_invalidation =
        RuntimeInvalidation.Event.new(
          :historical_data_changed,
          [:source_result, :frame],
          invalidation_metadata.filters,
          %{},
          %{plans: 0, source_results: 1, frames: 1, total: 2},
          occurred_at: occurred_at
        )

      assert {:ok, persisted_decision_event} =
               Cadence.record_dashboard_runtime_invalidation_decision(
                 persisted_invalidation,
                 persisted_decision,
                 invalidation_event_id: invalidation_event_id,
                 decision_observed_at: ~U[2026-06-24 12:00:05Z]
               )

      emit_runtime_invalidation_decision!(
        Map.put(invalidation_metadata, :invalidation_event_id, "runtime-health-decision-ignored"),
        %{
          dashboard_id: dashboard.dashboard_id,
          organization_id: mission.organization_id,
          mission_id: mission.mission_id,
          affected_placement_count: 1,
          affected_placement_ids: ["placement-persisted-decision"],
          affected_widget_type_ids: ["cadence.value_tile"],
          affected_impact_reasons: [:primary_source],
          matches?: false,
          dashboard_matches?: true,
          context_matches?: false,
          context_reason: :replay_run_mismatch,
          refresh_allowed?: false,
          refresh_reason: :stale_for_context,
          decision_status: :filtered
        }
      )

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?time_mode=replay_run&replay_run_id=replay_run_001"
        )

      render_dashboard_async(view)

      view
      |> element("#dashboard-diagnostics-button")
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel[data-runtime-invalidation-events="1"][data-runtime-invalidation-context-matches="0"][data-runtime-invalidation-context-filtered="1"][data-runtime-invalidation-context-filter-reasons*="replay_run_mismatch:1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="historical_data_changed"][data-runtime-invalidation-replay-run-id="replay_run_001"][data-runtime-invalidation-context-match="false"][data-runtime-invalidation-context-reason="replay_run_mismatch"][data-runtime-invalidation-refresh-allowed="false"][data-runtime-invalidation-refresh-allowed-reason="stale_for_context"][data-runtime-invalidation-decision-status="filtered"][data-runtime-invalidation-decision-source="durable_projection"][data-runtime-invalidation-decision-event-id="#{persisted_decision_event.dashboard_runtime_invalidation_decision_event_id}"][data-runtime-invalidation-decision-observed-at="2026-06-24T12:00:05Z"][data-runtime-invalidation-affected-placement-count="1"][data-runtime-invalidation-affected-placement-ids="placement-persisted-decision"][data-runtime-invalidation-affected-widget-types="cadence.value_tile"][data-runtime-invalidation-affected-impact-reasons="primary_source"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-summary[data-no-refresh-blocking-source="durable_projection"][data-no-refresh-blocking-decision-id="#{persisted_decision_event.dashboard_runtime_invalidation_decision_event_id}"][data-no-refresh-blocking-boundary="historical_data_changed"][data-no-refresh-blocking-observable="HK.counter"][data-no-refresh-blocking-context="filtered by replay run"][data-no-refresh-blocking-refresh="stale before current context"][data-no-refresh-blocking-placements="placement-persisted-decision"][data-no-refresh-blocking-impact="primary_source"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Decision ID"]),
               persisted_decision_event.dashboard_runtime_invalidation_decision_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-summary [data-no-refresh-admin-decision-link-action][href*="/admin/runtime"][href*="decision=#{persisted_decision_event.dashboard_runtime_invalidation_decision_event_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_001"] [data-invalidation-field="Decision source"]),
               "durable_projection"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_001"] [data-invalidation-field="Decision ID"]),
               persisted_decision_event.dashboard_runtime_invalidation_decision_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_001"] [data-invalidation-field="Decision observed"]),
               "2026-06-24T12:00:05Z"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_001"] [data-invalidation-field="Placements"]),
               "placement-persisted-decision"
             )
    end
  end
end
