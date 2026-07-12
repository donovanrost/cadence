defmodule CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationDiagnosticsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Document, Placement, WidgetDef}
  alias Cadence.Dashboards.RuntimeInvalidation
  alias CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationDiagnostics

  test "projects recent invalidation rows with runtime-health decisions over computed relevance" do
    event =
      runtime_event(
        :source_watermark_changed,
        %{total: 4},
        %{
          logical_source: :telemetry,
          realm: :flight,
          data_source_id: "questdb-flight",
          source_binding_id: "flight-binding",
          observable: "HK.counter"
        }
      )

    decision = %{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      matches?: false,
      dashboard_matches?: true,
      context_matches?: false,
      context_reason: :realm_mismatch,
      refresh_allowed?: false,
      refresh_reason: :stale_for_context,
      affected_placement_count: 1,
      affected_placement_ids: ["placement-1"],
      affected_widget_type_ids: ["cadence.value_tile"],
      affected_impact_reasons: [:primary_source],
      selection_state: :active,
      selected_link_id: "telemetry-sample-link",
      selected_target: :telemetry_sample,
      selected_target_id: "sample-1",
      selected_placement_id: "placement-1",
      selected_observable_id: "HK.counter",
      selected_data_view: :all_revisions,
      selection_affected?: true,
      selection_impact_reason: :affected_placement,
      source_cache_evidence_state_summary: %{total: 2, resolved: 1, context_only: 1, missing: 0},
      source_cache_evidence_target_ids: ["source_watermark_event:watermark-event-1"],
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
    }

    rows =
      RuntimeInvalidationDiagnostics.recent_invalidations(
        [recent_event(event), decision_event(event, decision)],
        scope(),
        mission(),
        document(),
        runtime_context()
      )

    assert [
             %{
               id: id,
               dashboard_id: "dashboard-1",
               mission_id: "mission-1",
               boundary: "source_watermark_changed",
               refresh_reason: "runtime_invalidation",
               refresh_action: "refresh_source_result",
               context_match: "false",
               context_reason: "realm_mismatch",
               context_reason_label: "filtered by realm",
               refresh_allowed: "false",
               refresh_allowed_reason: "stale_for_context",
               refresh_allowed_reason_label: "stale before current context",
               affected_placement_count: "1",
               affected_placement_ids: "placement-1",
               affected_widget_type_ids: "cadence.value_tile",
               affected_impact_reasons: "primary_source",
               selection_state: "active",
               selected_link_id: "telemetry-sample-link",
               selected_target: "telemetry_sample",
               selected_target_id: "sample-1",
               selected_placement_id: "placement-1",
               selected_observable_id: "HK.counter",
               selected_data_view: "all_revisions",
               selection_affected: "true",
               selection_impact_reason: "affected_placement",
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
               decision_source: "runtime_health",
               logical_source: "telemetry",
               realm: "flight",
               data_source_id: "questdb-flight",
               source_binding_id: "flight-binding",
               observable: "HK.counter",
               artifacts: "4",
               occurred_at: "2026-06-17T12:00:00Z"
             }
           ] = rows

    assert id == RuntimeInvalidationDiagnostics.event_id(event)
  end

  test "projects lifecycle correlation for dashboard version invalidations" do
    event =
      runtime_event(
        :dashboard_version_changed,
        %{total: 1},
        %{
          dashboard_id: "dashboard-1",
          document_version: 3,
          lifecycle_action: :reverted,
          source_version: 1
        }
      )

    assert [
             %{
               boundary: "dashboard_version_changed",
               lifecycle_action: "reverted",
               lifecycle_correlation_state: "restored_as_draft",
               lifecycle_correlation_label: "Restored v1 as v3 invalidated dashboard plan",
               lifecycle_correlation_target_version: "3",
               lifecycle_correlation_source_version: "1",
               source_version: "1",
               document_version: "3"
             }
           ] =
             RuntimeInvalidationDiagnostics.recent_invalidations(
               [recent_event(event)],
               scope(),
               mission(),
               document(),
               runtime_context()
             )
  end

  test "formats invalidation rows and root attrs" do
    invalidation = %{
      event_count: 3,
      artifact_count: 7,
      boundaries: %{source_watermark_changed: 2, limit_definition_changed: 1}
    }

    relevance = %{
      context_matches: 2,
      context_filtered: 1,
      context_reasons: %{realm_mismatch: 1},
      context_reason_labels: "filtered by realm:1",
      refresh_allowed: 1,
      refresh_suppressed: 2,
      refresh_reasons: %{edit_mode: 2},
      refresh_reason_labels: "editing dashboard:2"
    }

    last_invalidation = %{
      boundary: :source_watermark_changed,
      refresh_reason: :runtime_invalidation,
      refresh_action: :refresh_source_result
    }

    assert RuntimeInvalidationDiagnostics.rows(invalidation, relevance, last_invalidation) == [
             %{label: "Invalidation events", value: "3"},
             %{label: "Invalidated artifacts", value: "7"},
             %{
               label: "Boundaries",
               value: "limit_definition_changed:1 source_watermark_changed:2"
             },
             %{label: "Context matches", value: "2"},
             %{label: "Context filtered", value: "1"},
             %{label: "Context filter reasons", value: "filtered by realm:1"},
             %{label: "Refresh allowed", value: "1"},
             %{label: "Refresh suppressed", value: "2"},
             %{label: "Refresh suppress reasons", value: "editing dashboard:2"},
             %{label: "Last invalidation", value: "source_watermark_changed"},
             %{label: "Last refresh reason", value: "runtime_invalidation"},
             %{label: "Last refresh action", value: "refresh_source_result"}
           ]

    assert RuntimeInvalidationDiagnostics.attrs(invalidation, relevance) == %{
             invalidation_event_count: 3,
             invalidation_artifact_count: 7,
             invalidation_boundary_summary:
               "limit_definition_changed:1 source_watermark_changed:2",
             invalidation_context_match_count: 2,
             invalidation_context_filtered_count: 1,
             invalidation_context_filter_reasons: "%{realm_mismatch: 1}",
             invalidation_refresh_allowed_count: 1,
             invalidation_refresh_suppressed_count: 2,
             invalidation_refresh_suppress_reasons: "%{edit_mode: 2}"
           }
  end

  test "summarizes dashboard-relevant events" do
    matching =
      runtime_event(
        :source_watermark_changed,
        %{total: 3},
        %{
          logical_source: :telemetry,
          realm: :flight,
          data_source_id: "questdb-flight",
          source_binding_id: "flight-binding",
          observable: "HK.counter"
        }
      )

    unrelated =
      runtime_event(
        :source_watermark_changed,
        %{total: 9},
        %{
          logical_source: :telemetry,
          realm: :flight,
          data_source_id: "questdb-flight",
          source_binding_id: "flight-binding",
          observable: "HK.voltage"
        }
      )

    assert RuntimeInvalidationDiagnostics.summary(
             [recent_event(matching), recent_event(unrelated)],
             scope(),
             mission(),
             document()
           ) == %{
             event_count: 1,
             artifact_count: 3,
             boundaries: %{source_watermark_changed: 1}
           }
  end

  test "reports decision status from relevance pair" do
    assert RuntimeInvalidationDiagnostics.decision_status(
             %{matches?: false},
             %{allowed?: true}
           ) == :filtered

    assert RuntimeInvalidationDiagnostics.decision_status(
             %{matches?: true},
             %{allowed?: true}
           ) == :refresh_allowed

    assert RuntimeInvalidationDiagnostics.decision_status(
             %{matches?: true},
             %{allowed?: false}
           ) == :refresh_suppressed
  end

  defp runtime_event(boundary, measurements, filters) do
    RuntimeInvalidation.Event.new(
      boundary,
      [:source_result, :frame],
      Map.merge(
        %{
          organization_id: "org-1",
          mission_id: "mission-1"
        },
        filters
      ),
      %{},
      measurements,
      occurred_at: ~U[2026-06-17 12:00:00Z]
    )
  end

  defp recent_event(event) do
    %{
      source: :dashboards_runtime_invalidation,
      event: :invalidate,
      runtime_event: event,
      observed_at: event.occurred_at,
      metadata: RuntimeInvalidation.Event.to_telemetry_metadata(event, TestRuntimeCache),
      measurements: event.measurements
    }
  end

  defp decision_event(event, decision) do
    metadata =
      event
      |> RuntimeInvalidation.Event.to_telemetry_metadata(TestRuntimeCache)
      |> Map.put(:invalidation_event_id, RuntimeInvalidationDiagnostics.event_id(event))
      |> Map.put(:decision, decision)
      |> Map.merge(decision)

    %{
      source: :dashboards_runtime_invalidation,
      event: :decision,
      observed_at: event.occurred_at,
      metadata: metadata,
      measurements: %{total: 1}
    }
  end

  defp runtime_context do
    %{
      data_realm: "flight",
      time_mode: "live",
      replay_run_id: nil,
      engine_result: %{
        watermarks: [
          %{data_source_id: "questdb-flight", source_binding_id: "flight-binding"}
        ]
      }
    }
  end

  defp document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      placements: [
        %Placement{
          placement_id: "placement-1",
          widget_def: %WidgetDef{
            widget_type_id: "cadence.value_tile",
            binding: %{source: :telemetry, observables: ["HK.counter"]}
          }
        }
      ]
    }
  end

  defp scope, do: %{organization_id: "org-1"}
  defp mission, do: %{mission_id: "mission-1"}
end
