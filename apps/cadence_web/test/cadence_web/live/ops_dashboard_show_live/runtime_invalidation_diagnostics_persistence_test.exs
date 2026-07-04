defmodule CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationDiagnosticsPersistenceTest do
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards
  alias Cadence.Dashboards.{Document, Placement, WidgetDef}
  alias Cadence.Dashboards.RuntimeInvalidation.Event
  alias CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationDiagnostics

  test "recent invalidation diagnostics prefer durable decision rows" do
    %{mission: mission} =
      persist_mission_scope("org-runtime-diagnostics", "mission-runtime-diagnostics")

    dashboard =
      persist_dashboard!(
        mission.organization_id,
        mission.mission_id,
        "dashboard-runtime-diagnostics"
      )

    invalidation =
      Event.new(
        :source_watermark_changed,
        [:source_result, :frame],
        %{
          organization_id: mission.organization_id,
          mission_id: mission.mission_id,
          logical_source: :telemetry,
          observable: "HK.counter"
        },
        %{},
        %{source_results: 1, frames: 1, total: 2},
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    assert {:ok, decision_event} =
             Cadence.record_dashboard_runtime_invalidation_decision(
               invalidation,
               %{
                 dashboard_id: dashboard.dashboard_id,
                 organization_id: mission.organization_id,
                 mission_id: mission.mission_id,
                 matches?: false,
                 dashboard_matches?: true,
                 context_matches?: false,
                 context_reason: :replay_run_mismatch,
                 refresh_allowed?: false,
                 refresh_reason: :stale_for_context,
                 affected_placement_count: 1,
                 affected_placement_ids: ["durable-placement"],
                 affected_widget_type_ids: ["cadence.value_tile"],
                 affected_impact_reasons: [:primary_source],
                 selection_state: :active,
                 selected_link_id: "telemetry-sample-link",
                 selected_target: :telemetry_sample,
                 selected_target_id: "sample-1",
                 selected_placement_id: "durable-placement",
                 selected_observable_id: "HK.counter",
                 selected_data_view: :all_revisions,
                 selection_affected?: true,
                 selection_impact_reason: :affected_placement,
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
                 source_dependency_degraded_count: 1,
                 source_dependency_evidence: [
                   "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale"
                 ],
                 decision_status: :filtered
               },
               invalidation_event_id: RuntimeInvalidationDiagnostics.event_id(invalidation),
               decision_observed_at: ~U[2026-06-24 12:00:05Z]
             )

    expected_decision_event_id =
      decision_event.dashboard_runtime_invalidation_decision_event_id

    rows =
      RuntimeInvalidationDiagnostics.recent_invalidations(
        [recent_event(invalidation)],
        %{organization_id: mission.organization_id},
        mission,
        dashboard,
        %{time_mode: "live", data_realm: "flight"}
      )

    assert [
             %{
               dashboard_id: "dashboard-runtime-diagnostics",
               mission_id: "mission-runtime-diagnostics",
               context_match: "false",
               context_reason: "replay_run_mismatch",
               refresh_allowed: "false",
               refresh_allowed_reason: "stale_for_context",
               affected_placement_count: "1",
               affected_placement_ids: "durable-placement",
               affected_widget_type_ids: "cadence.value_tile",
               affected_impact_reasons: "primary_source",
               selection_state: "active",
               selected_link_id: "telemetry-sample-link",
               selected_target: "telemetry_sample",
               selected_target_id: "sample-1",
               selected_placement_id: "durable-placement",
               selected_observable_id: "HK.counter",
               selected_data_view: "all_revisions",
               selection_affected: "true",
               selection_impact_reason: "affected_placement",
               source_cache_evidence_total: "2",
               source_cache_evidence_resolved: "1",
               source_cache_evidence_context_only: "1",
               source_cache_evidence_missing: "0",
               source_cache_evidence_target_ids:
                 "source_watermark_event:source-watermark-event-1",
               source_cache_evidence_request_ids: "req-telemetry",
               source_execution_retryable_count: "3",
               source_execution_actionable_count: "2",
               source_execution_degraded_count: "2",
               source_execution_status_summary:
                 "cache_stale:1 source_degraded:1 source_unavailable:1",
               source_execution_severity_summary: "error:1 warning:2",
               source_execution_runtime_actions:
                 "refresh_source_result:1 wait_for_source_health:2",
               source_execution_operator_actions: "inspect_source_health:2 wait_for_refresh:1",
               source_execution_degraded_identities:
                 "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable",
               source_execution_degraded_actions:
                 "telemetry:req-circuit:wait_for_source_health:inspect_source_health telemetry:req-unavailable:wait_for_source_health:inspect_source_health",
               source_dependency_degraded_count: "1",
               source_dependency_evidence:
                 "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale",
               decision_status: "filtered",
               decision_source: "durable_projection",
               decision_event_id: ^expected_decision_event_id,
               decision_observed_at: "2026-06-24T12:00:05Z"
             }
           ] = rows
  end

  defp persist_dashboard!(organization_id, mission_id, dashboard_id) do
    document = %Document{
      dashboard_id: dashboard_id,
      organization_id: organization_id,
      mission_id: mission_id,
      name: "Runtime Diagnostics",
      placements: [
        %Placement{
          placement_id: "computed-placement",
          widget_def: %WidgetDef{
            widget_type_id: "cadence.value_tile",
            binding: %{
              source: :telemetry,
              observables: ["HK.counter"],
              scope_mode: :context,
              data_mode: :context,
              sampling: :latest
            }
          }
        }
      ]
    }

    assert {:ok, %Document{} = persisted} = Dashboards.persist_document(organization_id, document)
    persisted
  end

  defp recent_event(%Event{} = event) do
    %{
      source: :dashboards_runtime_invalidation,
      event: :invalidate,
      runtime_event: event,
      observed_at: event.occurred_at,
      metadata: Event.to_telemetry_metadata(event, TestRuntimeCache),
      measurements: event.measurements
    }
  end
end
