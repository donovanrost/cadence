defmodule CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationOperatorDiagnosticsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.{DataSources, RuntimeInvalidation}
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

  defp seed_runtime_invalidation_diagnostics!(mission, dashboard, affected_placement_id) do
    reset_runtime_health!()

    occurred_at = ~U[2026-06-24 12:00:00Z]
    source_watermark_measurements = %{plans: 0, source_results: 2, frames: 2, total: 4}

    source_watermark_metadata = %{
      boundary: :source_watermark_changed,
      domain_fact: :source_watermark_changed,
      layers: [:source_result, :frame],
      occurred_at: occurred_at,
      filters: %{
        organization_id: mission.organization_id,
        mission_id: mission.mission_id,
        logical_source: :telemetry,
        realm: :flight,
        data_source_id: DataSources.default_managed_data_source().data_source_id,
        source_binding_id: "default_flight_telemetry",
        observable: "HK.counter"
      }
    }

    emit_runtime_invalidation!(source_watermark_measurements, source_watermark_metadata)

    source_watermark_event_id =
      runtime_invalidation_test_event_id(
        :source_watermark_changed,
        mission.mission_id,
        "HK.counter",
        4,
        occurred_at
      )

    source_watermark_event =
      RuntimeInvalidation.Event.new(
        :source_watermark_changed,
        [:source_result, :frame],
        source_watermark_metadata.filters,
        %{},
        source_watermark_measurements,
        occurred_at: occurred_at
      )

    assert {:ok, persisted_decision_event} =
             Cadence.record_dashboard_runtime_invalidation_decision(
               source_watermark_event,
               %{
                 dashboard_id: dashboard.dashboard_id,
                 organization_id: mission.organization_id,
                 mission_id: mission.mission_id,
                 affected_placement_count: 1,
                 affected_placement_ids: [affected_placement_id],
                 affected_widget_type_ids: ["cadence.value_tile"],
                 affected_impact_reasons: [:primary_source],
                 source_cache_evidence_state_summary: %{
                   total: 2,
                   resolved: 1,
                   context_only: 1,
                   missing: 0
                 },
                 source_cache_evidence_target_ids: [
                   "source_watermark_event:source-watermark-event-1"
                 ],
                 source_cache_evidence_request_ids: ["req-telemetry"],
                 source_execution_retryable_count: 3,
                 source_execution_actionable_count: 2,
                 source_execution_degraded_count: 2,
                 source_execution_status_summary: %{
                   cache_stale: 1,
                   source_unavailable: 1,
                   source_degraded: 1
                 },
                 source_execution_severity_summary: %{warning: 2, error: 1},
                 source_execution_runtime_action_summary: %{
                   refresh_source_result: 1,
                   wait_for_source_health: 2
                 },
                 source_execution_operator_action_summary: %{
                   wait_for_refresh: 1,
                   inspect_source_health: 2
                 },
                 source_execution_degraded_identities: [
                   "telemetry:req-circuit:source_degraded",
                   "telemetry:req-unavailable:source_unavailable"
                 ],
                 source_execution_degraded_actions: [
                   "telemetry:req-circuit:wait_for_source_health:inspect_source_health",
                   "telemetry:req-unavailable:wait_for_source_health:inspect_source_health"
                 ],
                 matches?: true,
                 dashboard_matches?: true,
                 context_matches?: true,
                 context_reason: :matched,
                 refresh_allowed?: false,
                 refresh_reason: :stale_for_context,
                 decision_status: :refresh_suppressed
               },
               invalidation_event_id: source_watermark_event_id,
               decision_observed_at: ~U[2026-06-24 12:00:05Z]
             )

    emit_runtime_invalidation!(
      %{plans: 0, source_results: 5, frames: 5, total: 10},
      %{
        boundary: :source_watermark_changed,
        domain_fact: :source_watermark_changed,
        layers: [:source_result, :frame],
        filters: %{
          organization_id: mission.organization_id,
          mission_id: "other-mission",
          logical_source: :telemetry
        }
      }
    )

    persisted_decision_event
  end

  describe "runtime invalidation operator diagnostics" do
    test "operator surface exposes scoped runtime invalidation diagnostics" do
      {conn, _org, mission} = signed_in_org_and_mission()

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Invalidation Health",
          widgets: [value_tile("HK.counter")]
        )

      assert [%{placement_id: affected_placement_id}] = dashboard.placements

      persisted_decision_event =
        seed_runtime_invalidation_diagnostics!(mission, dashboard, affected_placement_id)

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-invalidation-events="1"][data-runtime-invalidation-artifacts="4"][data-runtime-invalidation-boundaries*="source_watermark_changed:1"][data-runtime-invalidation-context-matches="1"][data-runtime-invalidation-context-filtered="0"][data-runtime-invalidation-context-filter-reasons="-"][data-runtime-invalidation-refresh-allowed="0"][data-runtime-invalidation-refresh-suppressed="1"][data-runtime-invalidation-refresh-suppress-reasons*="stale_for_context:1"])
             )

      view
      |> element("#dashboard-diagnostics-button")
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel[data-runtime-invalidation-events="1"][data-runtime-invalidation-artifacts="4"][data-runtime-invalidation-boundaries*="source_watermark_changed:1"][data-runtime-invalidation-context-matches="1"][data-runtime-invalidation-context-filtered="0"][data-runtime-invalidation-context-filter-reasons="-"][data-runtime-invalidation-refresh-allowed="0"][data-runtime-invalidation-refresh-suppressed="1"][data-runtime-invalidation-refresh-suppress-reasons*="stale_for_context:1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-summary[data-no-refresh-status="refresh_suppressed"][data-no-refresh-context="Context: all recent invalidations matched"][data-no-refresh-refresh="Refresh: stale before current context:1"]),
               "Invalidations matched, but refresh was suppressed."
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-summary[data-no-refresh-blocking-boundary="source_watermark_changed"][data-no-refresh-blocking-source="durable_projection"][data-no-refresh-blocking-decision-id="#{persisted_decision_event.dashboard_runtime_invalidation_decision_event_id}"][data-no-refresh-blocking-observable="HK.counter"][data-no-refresh-blocking-context="matched"][data-no-refresh-blocking-refresh="stale before current context"][data-no-refresh-blocking-placements="#{affected_placement_id}"][data-no-refresh-blocking-impact="primary_source"][data-no-refresh-blocking-source-cache-evidence-total="2"][data-no-refresh-blocking-source-cache-evidence-resolved="1"][data-no-refresh-blocking-source-cache-evidence-context-only="1"][data-no-refresh-blocking-source-cache-evidence-missing="0"][data-no-refresh-blocking-source-cache-evidence-targets="source_watermark_event:source-watermark-event-1"][data-no-refresh-blocking-source-cache-evidence-requests="req-telemetry"][data-no-refresh-blocking-source-execution-statuses="cache_stale:1 source_degraded:1 source_unavailable:1"][data-no-refresh-blocking-source-execution-actions="refresh_source_result:1 wait_for_source_health:2"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Placements"]),
               affected_placement_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Refresh"]),
               "stale before current context"
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Source cache evidence"]),
               "total:2 resolved:1 context:1 missing:0"
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Source cache evidence targets"]),
               "source_watermark_event:source-watermark-event-1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Source execution"]),
               "cache_stale:1 source_degraded:1 source_unavailable:1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Source execution actions"]),
               "refresh_source_result:1 wait_for_source_health:2"
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Source execution degraded"]),
               "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Invalidation events"]),
               "1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Invalidated artifacts"]),
               "4"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Boundaries"]),
               "source_watermark_changed:1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Context matches"]),
               "1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Refresh suppressed"]),
               "1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Refresh suppress reasons"]),
               "stale before current context:1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"][data-runtime-invalidation-source="telemetry"][data-runtime-invalidation-realm="flight"][data-runtime-invalidation-data-source="#{DataSources.default_managed_data_source().data_source_id}"][data-runtime-invalidation-binding="default_flight_telemetry"][data-runtime-invalidation-observable="HK.counter"][data-runtime-invalidation-context-match="true"][data-runtime-invalidation-context-reason="matched"][data-runtime-invalidation-refresh-allowed="false"][data-runtime-invalidation-refresh-allowed-reason="stale_for_context"][data-runtime-invalidation-refresh-reason="runtime_invalidation"][data-runtime-invalidation-refresh-action="refresh_source_result"][data-runtime-invalidation-decision-status="refresh_suppressed"][data-runtime-invalidation-decision-source="durable_projection"][data-runtime-invalidation-decision-event-id="#{persisted_decision_event.dashboard_runtime_invalidation_decision_event_id}"][data-runtime-invalidation-affected-placement-count="1"][data-runtime-invalidation-affected-placement-ids="#{affected_placement_id}"][data-runtime-invalidation-affected-widget-types="cadence.value_tile"][data-runtime-invalidation-affected-impact-reasons="primary_source"][data-runtime-invalidation-source-cache-evidence-total="2"][data-runtime-invalidation-source-cache-evidence-resolved="1"][data-runtime-invalidation-source-cache-evidence-context-only="1"][data-runtime-invalidation-source-cache-evidence-missing="0"][data-runtime-invalidation-source-cache-evidence-targets="source_watermark_event:source-watermark-event-1"][data-runtime-invalidation-source-cache-evidence-requests="req-telemetry"][data-runtime-invalidation-source-execution-statuses="cache_stale:1 source_degraded:1 source_unavailable:1"][data-runtime-invalidation-source-execution-actions="refresh_source_result:1 wait_for_source_health:2"][data-runtime-invalidation-artifacts="4"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Refresh"]),
               "refresh_source_result"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Allowed reason"]),
               "stale before current context"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Impacted"]),
               "1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Placements"]),
               affected_placement_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Widgets"]),
               "cadence.value_tile"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Impact"]),
               "primary_source"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Source cache evidence"]),
               "total:2 resolved:1 context:1 missing:0"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Source cache evidence targets"]),
               "source_watermark_event:source-watermark-event-1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Source execution"]),
               "cache_stale:1 source_degraded:1 source_unavailable:1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Source execution actions"]),
               "refresh_source_result:1 wait_for_source_health:2"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Source execution degraded"]),
               "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable"
             )
    end
  end
end
