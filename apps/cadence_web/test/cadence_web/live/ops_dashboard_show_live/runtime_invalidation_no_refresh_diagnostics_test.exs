defmodule CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationNoRefreshDiagnosticsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationDiagnostics

  test "summarizes relevance rows and no-refresh visibility" do
    rows = [
      %{
        context_match: "false",
        context_reason: "realm_mismatch",
        context_reason_label: "filtered by realm",
        refresh_allowed: "false",
        refresh_allowed_reason: "stale_for_context",
        refresh_allowed_reason_label: "stale before current context"
      },
      %{
        context_match: "true",
        context_reason: "matched",
        context_reason_label: "matched",
        refresh_allowed: "false",
        refresh_allowed_reason: "non_live_boundary",
        refresh_allowed_reason_label: "not refreshable in live mode"
      }
    ]

    relevance = RuntimeInvalidationDiagnostics.relevance_summary(rows)

    assert relevance == %{
             context_matches: 1,
             context_filtered: 1,
             refresh_allowed: 0,
             refresh_suppressed: 2,
             context_reasons: "realm_mismatch:1",
             refresh_reasons: "non_live_boundary:1 stale_for_context:1",
             context_reason_labels: "filtered by realm:1",
             refresh_reason_labels:
               "not refreshable in live mode:1 stale before current context:1"
           }

    assert RuntimeInvalidationDiagnostics.no_refresh_summary(
             %{event_count: 2, artifact_count: 4},
             relevance
           ) == %{
             visible?: true,
             status: "mixed_context_suppressed",
             headline: "Some invalidations were filtered; matched invalidations were suppressed.",
             context: "Context: filtered by realm:1",
             refresh: "Refresh: not refreshable in live mode:1 stale before current context:1"
           }

    blocker_rows = [
      Map.merge(Enum.at(rows, 0), %{
        id: "invalidation-2",
        boundary: "source_watermark_changed",
        refresh_action: "refresh_source_result",
        logical_source: "telemetry",
        realm: "rehearsal",
        data_source_id: "questdb-rehearsal",
        source_binding_id: "rehearsal-binding",
        observable: "HK.counter",
        replay_run_id: "replay-run-1",
        lifecycle_action: "watermark_observed",
        decision_status: "filtered",
        decision_source: "durable_projection",
        decision_event_id: "decision-event-2",
        decision_observed_at: "2026-06-24T12:01:00Z",
        affected_placement_count: "1",
        affected_placement_ids: "placement-counter",
        affected_impact_reasons: "primary_source",
        source_cache_evidence_total: "2",
        source_cache_evidence_resolved: "1",
        source_cache_evidence_context_only: "1",
        source_cache_evidence_missing: "0",
        source_cache_evidence_target_ids: "source_watermark_event:watermark-event-1",
        source_cache_evidence_request_ids: "req-telemetry",
        source_execution_retryable_count: "3",
        source_execution_actionable_count: "2",
        source_execution_degraded_count: "2",
        source_execution_status_summary: "cache_stale:1 source_degraded:1 source_unavailable:1",
        source_execution_severity_summary: "error:1 warning:2",
        source_execution_runtime_actions: "refresh_source_result:1 wait_for_source_health:2",
        source_execution_operator_actions: "inspect_source_health:2 wait_for_refresh:1",
        source_execution_degraded_identities:
          "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable",
        source_execution_degraded_actions:
          "telemetry:req-circuit:wait_for_source_health:inspect_source_health telemetry:req-unavailable:wait_for_source_health:inspect_source_health",
        source_dependency_degraded_count: "1",
        source_dependency_evidence:
          "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale",
        occurred_at: "2026-06-24T12:00:59Z"
      }),
      Map.merge(Enum.at(rows, 1), %{
        id: "invalidation-1",
        boundary: "limit_definition_changed",
        observable: "HK.voltage",
        decision_status: "refresh_suppressed",
        decision_source: "runtime_health",
        decision_event_id: "-",
        decision_observed_at: "2026-06-24T12:00:00Z",
        affected_placement_count: "1",
        affected_placement_ids: "placement-voltage",
        affected_impact_reasons: "limit_overlay",
        occurred_at: "2026-06-24T11:59:59Z"
      })
    ]

    assert %{
             blocker: %{
               id: "invalidation-2",
               boundary: "source_watermark_changed",
               refresh_action: "refresh_source_result",
               logical_source: "telemetry",
               realm: "rehearsal",
               data_source_id: "questdb-rehearsal",
               source_binding_id: "rehearsal-binding",
               observable: "HK.counter",
               replay_run_id: "replay-run-1",
               lifecycle_action: "watermark_observed",
               decision_status: "filtered",
               decision_source: "durable_projection",
               decision_event_id: "decision-event-2",
               decision_observed_at: "2026-06-24T12:01:00Z",
               context_reason: "filtered by realm",
               refresh_reason: "stale before current context",
               affected_placement_count: "1",
               affected_placement_ids: "placement-counter",
               affected_impact_reasons: "primary_source",
               source_cache_evidence_total: "2",
               source_cache_evidence_resolved: "1",
               source_cache_evidence_context_only: "1",
               source_cache_evidence_missing: "0",
               source_cache_evidence_target_ids: "source_watermark_event:watermark-event-1",
               source_cache_evidence_request_ids: "req-telemetry",
               source_execution_retryable_count: "3",
               source_execution_actionable_count: "2",
               source_execution_degraded_count: "2",
               source_execution_status_summary:
                 "cache_stale:1 source_degraded:1 source_unavailable:1",
               source_execution_runtime_actions:
                 "refresh_source_result:1 wait_for_source_health:2",
               source_execution_degraded_identities:
                 "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable",
               source_execution_degraded_actions:
                 "telemetry:req-circuit:wait_for_source_health:inspect_source_health telemetry:req-unavailable:wait_for_source_health:inspect_source_health",
               source_dependency_degraded_count: "1",
               source_dependency_evidence:
                 "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale",
               occurred_at: "2026-06-24T12:00:59Z"
             }
           } =
             RuntimeInvalidationDiagnostics.no_refresh_summary(
               %{event_count: 2, artifact_count: 4},
               relevance,
               blocker_rows
             )
  end
end
