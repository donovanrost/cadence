defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticsPanelDetailComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticsPanelComponents

  test "diagnostics_panel composes runtime detail sections" do
    html =
      render_component(&RuntimeDiagnosticsPanelComponents.diagnostics_panel/1,
        diagnostics:
          diagnostics(%{
            cache_summary: %{
              visible?: true,
              classification: "reused",
              plan: "hit",
              source: "hit",
              frame: "miss",
              headline: "Dashboard reused part of the runtime cache.",
              drilldowns: []
            },
            no_refresh_summary: %{
              visible?: true,
              status: "suppressed",
              context: "matched",
              refresh: "blocked",
              headline:
                "Runtime invalidation matched the dashboard context but refresh was blocked."
            },
            source_dependency_evidence: [
              %{
                request_id: "req-limits",
                request_logical_source: "limits",
                logical_source: "telemetry",
                upstream_request_id: "req-telemetry",
                upstream_status: "source_degraded",
                upstream_runtime_action: "wait_for_source_health",
                upstream_operator_action: "inspect_source_health",
                upstream_source_binding_id: "binding-flight",
                upstream_data_source_id: "questdb-flight",
                upstream_realm: "flight",
                upstream_watermark_freshness_state: "stale"
              }
            ],
            source_capability_postures: [
              %{
                request_id: "req-telemetry",
                logical_source: "telemetry",
                status: "fallback",
                requested_sampling: "latest",
                supported_sampling: "latest",
                requested_time_axis: "generation_time",
                executed_time_axis: "receipt_time",
                supported_time_axes: "receipt_time",
                fallbacks: "time_axis:generation_time:receipt_time:unsupported_time_axis",
                source_binding_id: "binding-flight",
                data_source_id: "questdb-flight",
                realm: "flight"
              }
            ],
            recent_invalidations: [
              %{
                id: "invalidation-1",
                boundary: "source",
                logical_source: "telemetry",
                realm: "flight",
                data_source_id: "questdb-flight",
                source_binding_id: "binding-flight",
                replay_run_id: "-",
                observable: "HK.counter",
                lifecycle_action: "refresh",
                source_version: "source-v1",
                document_version: "3",
                context_match: "true",
                context_reason: "matched",
                context_reason_label: "matched",
                refresh_allowed: "false",
                refresh_allowed_reason: "scope_mismatch",
                refresh_allowed_reason_label: "scope_mismatch",
                refresh_reason: "runtime_invalidation",
                refresh_action: "refresh_visible_widgets",
                decision_status: "suppressed",
                decision_source: "runtime_health",
                decision_event_id: "decision-1",
                decision_observed_at: "2026-06-26T17:00:00Z",
                affected_placement_count: "1",
                affected_placement_ids: "placement-1",
                affected_widget_type_ids: "cadence.value_tile",
                affected_impact_reasons: "source_stale",
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
                source_cache_evidence_target_ids: "source_health_event:source-health-event-1",
                source_cache_evidence_request_ids: "req-telemetry",
                artifacts: "1",
                occurred_at: "2026-06-26T17:00:01Z"
              }
            ]
          })
      )

    document = LazyHTML.from_fragment(html)

    assert ["reused"] =
             document
             |> LazyHTML.query("#dashboard-cache-summary")
             |> LazyHTML.attribute("data-cache-classification")

    assert ["suppressed"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-status")

    assert ["source"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-boundary")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-selection-affected")

    assert ["affected_placement"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-selection-impact-reason")

    assert "telemetry_sample" =
             document
             |> LazyHTML.query(~s([data-invalidation-field="Selection target"]))
             |> LazyHTML.text()
             |> String.trim()

    assert "sample-1" =
             document
             |> LazyHTML.query(~s([data-invalidation-field="Selection ID"]))
             |> LazyHTML.text()
             |> String.trim()

    assert "total:2 resolved:1 context:1 missing:0" =
             document
             |> LazyHTML.query(~s([data-invalidation-field="Source cache evidence"]))
             |> LazyHTML.text()
             |> String.trim()

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-source-dependency-causes")
             |> LazyHTML.attribute("data-source-dependency-cause-count")

    assert "Limits waiting on telemetry input" =
             document
             |> LazyHTML.query("#dashboard-source-dependency-causes .font-medium")
             |> LazyHTML.text()
             |> String.trim()

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-source-capability-postures")
             |> LazyHTML.attribute("data-source-capability-posture-count")

    assert ["fallback"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("data-source-capability-status")

    assert ["open_evidence"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("phx-click")

    assert ["source"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("phx-value-kind")

    assert ["fallback"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("phx-value-source-capability-status")

    assert ["generation_time"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("phx-value-requested-time-axis")

    assert "generation_time -> receipt_time" =
             document
             |> LazyHTML.query(~s([data-source-capability-field="Clock"]))
             |> LazyHTML.text()
             |> String.trim()
  end

  defp diagnostics(overrides) do
    Map.merge(
      %{
        invalidation_event_count: 0,
        invalidation_artifact_count: 0,
        invalidation_boundary_summary: "-",
        invalidation_context_match_count: 0,
        invalidation_context_filtered_count: 0,
        invalidation_context_filter_reasons: "-",
        invalidation_refresh_allowed_count: 0,
        invalidation_refresh_suppressed_count: 0,
        invalidation_refresh_suppress_reasons: "-",
        refresh_status: "settled",
        refresh_reason: "accepted",
        active_refresh_mode: "-",
        active_refresh_started_at: "-",
        visible_refresh_action: "accept_result",
        last_refresh_started_at: "-",
        last_refresh_finished_at: "-",
        last_refresh_duration_ms: "-",
        refresh_starts: "-",
        refresh_cancellations: "-",
        refresh_coalesced: "-",
        refresh_noops: "-",
        refresh_failures: "-",
        refresh_ignored: "-",
        refresh_ignored_resolve_ids: "-",
        canceled_resolve_count: "0",
        failed_resolve_count: "0",
        source_execution_degraded_identities: "-",
        source_execution_degraded_actions: "-",
        source_capability_statuses_text: "-",
        source_capability_posture_text: "-",
        source_capability_postures: [],
        engine_rows: [],
        runtime_rows: [],
        invalidation_rows: [],
        cache_summary: %{visible?: false},
        source_execution_degraded_summary: %{visible?: false},
        source_execution_degraded_drilldowns: [],
        source_dependency_evidence: [],
        source_dependency_evidence_text: "-",
        source_dependency_degraded_count: 0,
        no_refresh_summary: %{visible?: false},
        recent_invalidations: []
      },
      overrides
    )
  end
end
