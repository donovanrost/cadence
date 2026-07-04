defmodule CadenceWeb.OpsDashboardShowLive.RuntimeRefreshStateTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RuntimeRefreshState

  test "build names runtime, invalidation, and source execution state" do
    state =
      RuntimeRefreshState.build(
        context(),
        diagnostics(),
        %{event_count: 4, artifact_count: 5, boundaries: %{dashboard_version_changed: 2}}
      )

    assert state.runtime == %{
             status: "idle",
             decision_actions: "start_resolve",
             resolved?: true,
             refresh_status: "settled",
             refresh_reason: "accepted",
             active_refresh_mode: "context_change",
             active_refresh_started_at: "2026-06-26T12:00:00Z",
             visible_refresh_action: "accept_result",
             last_refresh_started_at: "2026-06-26T11:59:58Z",
             last_refresh_finished_at: "2026-06-26T12:00:02Z",
             last_refresh_duration_ms: 4000,
             refresh_starts: "context_change:runtime_invalidation:1",
             refresh_cancellations: "live_tick:obsolete:1",
             refresh_coalesced: "live_tick:tick:1",
             refresh_noops: "live_tick:edit_mode:1",
             refresh_failures: "resolve_failed:1",
             refresh_ignored: "obsolete_resolve:1",
             refresh_ignored_resolve_ids: "resolve-1",
             canceled_resolve_count: 1,
             failed_resolve_count: 2
           }

    assert state.invalidation == %{
             event_count: 4,
             artifact_count: 5,
             boundary_summary: "dashboard_version_changed:2",
             context_match_count: 2,
             context_filtered_count: 1,
             context_filter_reasons: "scope_mismatch:1",
             refresh_allowed_count: 1,
             refresh_suppressed_count: 1,
             refresh_suppress_reasons: "edit_mode:1",
             last_boundary: "dashboard_version_changed",
             last_refresh_reason: "runtime_invalidation",
             last_refresh_action: "remount_charts"
           }

    assert state.source_execution == %{
             runtime_actions: "refresh_source_result:2",
             retryable_count: 1,
             actionable_count: 2,
             degraded_count: 3,
             degraded_identities: "telemetry:req-1:timeout",
             degraded_actions: "telemetry:req-1:retry:inspect"
           }
  end

  test "root attrs expose runtime refresh state without engine or dashboard attrs" do
    attrs =
      context()
      |> RuntimeRefreshState.build(diagnostics(), %{
        event_count: 4,
        artifact_count: 5,
        boundaries: %{dashboard_version_changed: 2}
      })
      |> RuntimeRefreshState.root_attrs()

    assert attrs["data-runtime-status"] == "idle"
    assert attrs["data-runtime-refresh-status"] == "settled"
    assert attrs["data-runtime-refresh-reason"] == "accepted"
    assert attrs["data-runtime-visible-refresh-action"] == "accept_result"
    assert attrs["data-runtime-refresh-starts"] == "context_change:runtime_invalidation:1"
    assert attrs["data-runtime-canceled-resolves"] == 1
    assert attrs["data-runtime-failed-resolves"] == 2
    assert attrs["data-runtime-resolved"] == "true"
    assert attrs["data-runtime-invalidation-events"] == 4
    assert attrs["data-runtime-invalidation-boundaries"] == "dashboard_version_changed:2"
    assert attrs["data-runtime-source-execution-actions"] == "refresh_source_result:2"
    assert attrs["data-runtime-last-invalidation-refresh-action"] == "remount_charts"
    refute Map.has_key?(attrs, "data-engine-resolve-mode")
    refute Map.has_key?(attrs, "data-dashboard-time-mode")
  end

  defp context do
    %{
      runtime_coordinator: %{status: :idle},
      runtime_decisions: [
        %{action: :start_resolve, resolve_mode: :live_tick, reason: :tick}
      ],
      runtime_resolved?: true,
      last_runtime_invalidation: %{
        boundary: :dashboard_version_changed,
        refresh_reason: :runtime_invalidation,
        refresh_action: :remount_charts
      }
    }
  end

  defp diagnostics do
    %{
      refresh_status: "settled",
      refresh_reason: "accepted",
      active_refresh_mode: "context_change",
      active_refresh_started_at: "2026-06-26T12:00:00Z",
      visible_refresh_action: "accept_result",
      last_refresh_started_at: "2026-06-26T11:59:58Z",
      last_refresh_finished_at: "2026-06-26T12:00:02Z",
      last_refresh_duration_ms: 4000,
      refresh_starts: "context_change:runtime_invalidation:1",
      refresh_cancellations: "live_tick:obsolete:1",
      refresh_coalesced: "live_tick:tick:1",
      refresh_noops: "live_tick:edit_mode:1",
      refresh_failures: "resolve_failed:1",
      refresh_ignored: "obsolete_resolve:1",
      refresh_ignored_resolve_ids: "resolve-1",
      canceled_resolve_count: 1,
      failed_resolve_count: 2,
      invalidation_context_match_count: 2,
      invalidation_context_filtered_count: 1,
      invalidation_context_filter_reasons: "scope_mismatch:1",
      invalidation_refresh_allowed_count: 1,
      invalidation_refresh_suppressed_count: 1,
      invalidation_refresh_suppress_reasons: "edit_mode:1",
      source_execution_runtime_actions: "refresh_source_result:2",
      source_execution_retryable_count: 1,
      source_execution_actionable_count: 2,
      source_execution_degraded_count: 3,
      source_execution_degraded_identities: "telemetry:req-1:timeout",
      source_execution_degraded_actions: "telemetry:req-1:retry:inspect"
    }
  end
end
