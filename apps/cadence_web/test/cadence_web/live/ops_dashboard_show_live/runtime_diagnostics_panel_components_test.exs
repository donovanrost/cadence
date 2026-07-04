defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticsPanelComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticsPanelComponents

  test "diagnostics_panel renders runtime attributes and row sections" do
    html =
      render_component(&RuntimeDiagnosticsPanelComponents.diagnostics_panel/1,
        diagnostics: diagnostics()
      )

    document = LazyHTML.from_fragment(html)

    assert ["3"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-invalidation-events")

    assert ["settled"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-status")

    assert ["obsolete-1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-ignored-resolve-ids")

    assert ["live_tick:tick:1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-coalesced")

    assert ["live_tick:edit_mode:1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-noops")

    assert ["resolve_failed:1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-failures")

    assert ["telemetry:request-1:source_degraded"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-source-execution-degraded-identities")

    assert ["fallback:1 native:1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-source-capability-statuses")

    assert ["telemetry:request-1:fallback:generation_time->receipt_time"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-source-capability-postures")

    assert "context_change" =
             document
             |> LazyHTML.query(
               ~s([data-diagnostics-section="Engine"] [data-diagnostics-field="Resolve"])
             )
             |> selected_text()

    assert "accept_result" =
             document
             |> LazyHTML.query(
               ~s([data-diagnostics-section="Runtime"] [data-diagnostics-field="Visible action"])
             )
             |> selected_text()

    assert "live_tick:tick:1" =
             document
             |> LazyHTML.query(
               ~s([data-diagnostics-section="Runtime"] [data-diagnostics-field="Refresh coalesced"])
             )
             |> selected_text()

    assert "resolve_failed:1" =
             document
             |> LazyHTML.query(
               ~s([data-diagnostics-section="Runtime"] [data-diagnostics-field="Refresh failures"])
             )
             |> selected_text()

    assert "source:2" =
             document
             |> LazyHTML.query(
               ~s([data-diagnostics-section="Invalidation"] [data-diagnostics-field="Boundaries"])
             )
             |> selected_text()
  end

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

  defp diagnostics(overrides \\ %{}) do
    Map.merge(
      %{
        invalidation_event_count: 3,
        invalidation_artifact_count: 4,
        invalidation_boundary_summary: "source:2",
        invalidation_context_match_count: 2,
        invalidation_context_filtered_count: 1,
        invalidation_context_filter_reasons: "scope_mismatch:1",
        invalidation_refresh_allowed_count: 1,
        invalidation_refresh_suppressed_count: 2,
        invalidation_refresh_suppress_reasons: "scope_mismatch:2",
        refresh_status: "settled",
        refresh_reason: "accepted",
        active_refresh_mode: "-",
        active_refresh_started_at: "-",
        visible_refresh_action: "accept_result",
        last_refresh_started_at: "2026-06-26T17:00:00Z",
        last_refresh_finished_at: "2026-06-26T17:00:01Z",
        last_refresh_duration_ms: "12",
        refresh_starts: "live_tick:1",
        refresh_cancellations: "-",
        refresh_coalesced: "live_tick:tick:1",
        refresh_noops: "live_tick:edit_mode:1",
        refresh_failures: "resolve_failed:1",
        refresh_ignored: "obsolete_resolve:1",
        refresh_ignored_resolve_ids: "obsolete-1",
        canceled_resolve_count: "0",
        failed_resolve_count: "0",
        source_execution_degraded_identities: "telemetry:request-1:source_degraded",
        source_execution_degraded_actions: "telemetry:request-1:wait_for_refresh:inspect_source",
        source_capability_statuses_text: "fallback:1 native:1",
        source_capability_posture_text:
          "telemetry:request-1:fallback:generation_time->receipt_time",
        source_capability_postures: [],
        engine_rows: [
          %{label: "Resolve", value: "context_change"},
          %{label: "Source requests", value: "3"}
        ],
        runtime_rows: [
          %{label: "Visible action", value: "accept_result"},
          %{label: "Refresh coalesced", value: "live_tick:tick:1"},
          %{label: "Refresh failures", value: "resolve_failed:1"},
          %{label: "Source runtime actions", value: "refresh_source_result:2"}
        ],
        invalidation_rows: [
          %{label: "Boundaries", value: "source:2"},
          %{label: "Context matches", value: "2"}
        ],
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

  defp selected_text(document) do
    document
    |> LazyHTML.text()
    |> String.trim()
  end
end
