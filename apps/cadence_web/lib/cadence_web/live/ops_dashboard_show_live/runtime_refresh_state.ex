defmodule CadenceWeb.OpsDashboardShowLive.RuntimeRefreshState do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RuntimeInvalidations
  alias CadenceWeb.OpsDashboardShowLive.RuntimeRefreshDiagnostics

  @spec build(map(), map(), map() | nil) :: map()
  def build(context, runtime_diagnostics, runtime_invalidation \\ %{})
      when is_map(context) and is_map(runtime_diagnostics) do
    runtime_invalidation = runtime_invalidation || %{}
    last_invalidation = Map.get(context, :last_runtime_invalidation)

    %{
      runtime: %{
        status: RuntimeRefreshDiagnostics.status(Map.get(context, :runtime_coordinator)),
        decision_actions:
          RuntimeRefreshDiagnostics.decision_actions(Map.get(context, :runtime_decisions, [])),
        resolved?: Map.get(context, :runtime_resolved?),
        refresh_status: Map.get(runtime_diagnostics, :refresh_status),
        refresh_reason: Map.get(runtime_diagnostics, :refresh_reason),
        active_refresh_mode: Map.get(runtime_diagnostics, :active_refresh_mode),
        active_refresh_started_at: Map.get(runtime_diagnostics, :active_refresh_started_at),
        visible_refresh_action: Map.get(runtime_diagnostics, :visible_refresh_action),
        last_refresh_started_at: Map.get(runtime_diagnostics, :last_refresh_started_at),
        last_refresh_finished_at: Map.get(runtime_diagnostics, :last_refresh_finished_at),
        last_refresh_duration_ms: Map.get(runtime_diagnostics, :last_refresh_duration_ms),
        refresh_starts: Map.get(runtime_diagnostics, :refresh_starts),
        refresh_cancellations: Map.get(runtime_diagnostics, :refresh_cancellations),
        refresh_coalesced: Map.get(runtime_diagnostics, :refresh_coalesced),
        refresh_noops: Map.get(runtime_diagnostics, :refresh_noops),
        refresh_failures: Map.get(runtime_diagnostics, :refresh_failures),
        refresh_ignored: Map.get(runtime_diagnostics, :refresh_ignored),
        refresh_ignored_resolve_ids: Map.get(runtime_diagnostics, :refresh_ignored_resolve_ids),
        canceled_resolve_count: Map.get(runtime_diagnostics, :canceled_resolve_count),
        failed_resolve_count: Map.get(runtime_diagnostics, :failed_resolve_count)
      },
      invalidation: %{
        event_count: Map.get(runtime_invalidation, :event_count),
        artifact_count: Map.get(runtime_invalidation, :artifact_count),
        boundary_summary: RuntimeInvalidations.boundary_summary(runtime_invalidation),
        context_match_count: Map.get(runtime_diagnostics, :invalidation_context_match_count),
        context_filtered_count:
          Map.get(runtime_diagnostics, :invalidation_context_filtered_count),
        context_filter_reasons:
          Map.get(runtime_diagnostics, :invalidation_context_filter_reasons),
        refresh_allowed_count: Map.get(runtime_diagnostics, :invalidation_refresh_allowed_count),
        refresh_suppressed_count:
          Map.get(runtime_diagnostics, :invalidation_refresh_suppressed_count),
        refresh_suppress_reasons:
          Map.get(runtime_diagnostics, :invalidation_refresh_suppress_reasons),
        last_boundary: RuntimeInvalidations.notice_boundary(last_invalidation),
        last_refresh_reason: RuntimeInvalidations.notice_refresh_reason(last_invalidation),
        last_refresh_action: RuntimeInvalidations.notice_refresh_action(last_invalidation)
      },
      source_execution: %{
        runtime_actions: Map.get(runtime_diagnostics, :source_execution_runtime_actions),
        retryable_count: Map.get(runtime_diagnostics, :source_execution_retryable_count),
        actionable_count: Map.get(runtime_diagnostics, :source_execution_actionable_count),
        degraded_count: Map.get(runtime_diagnostics, :source_execution_degraded_count),
        degraded_identities: Map.get(runtime_diagnostics, :source_execution_degraded_identities),
        degraded_actions: Map.get(runtime_diagnostics, :source_execution_degraded_actions)
      }
    }
  end

  @spec runtime_root_attrs(map()) :: map()
  def runtime_root_attrs(%{runtime: runtime}) when is_map(runtime) do
    %{
      "data-runtime-status" => runtime.status,
      "data-runtime-decision-actions" => runtime.decision_actions,
      "data-runtime-refresh-status" => runtime.refresh_status,
      "data-runtime-refresh-reason" => runtime.refresh_reason,
      "data-runtime-active-refresh-mode" => runtime.active_refresh_mode,
      "data-runtime-active-refresh-started-at" => runtime.active_refresh_started_at,
      "data-runtime-visible-refresh-action" => runtime.visible_refresh_action,
      "data-runtime-last-refresh-started-at" => runtime.last_refresh_started_at,
      "data-runtime-last-refresh-finished-at" => runtime.last_refresh_finished_at,
      "data-runtime-last-refresh-duration-ms" => runtime.last_refresh_duration_ms,
      "data-runtime-refresh-starts" => runtime.refresh_starts,
      "data-runtime-refresh-cancellations" => runtime.refresh_cancellations,
      "data-runtime-refresh-coalesced" => runtime.refresh_coalesced,
      "data-runtime-refresh-noops" => runtime.refresh_noops,
      "data-runtime-refresh-failures" => runtime.refresh_failures,
      "data-runtime-refresh-ignored" => runtime.refresh_ignored,
      "data-runtime-refresh-ignored-resolve-ids" => runtime.refresh_ignored_resolve_ids,
      "data-runtime-canceled-resolves" => runtime.canceled_resolve_count,
      "data-runtime-failed-resolves" => runtime.failed_resolve_count,
      "data-runtime-resolved" => to_string(runtime.resolved?)
    }
  end

  @spec invalidation_root_attrs(map()) :: map()
  def invalidation_root_attrs(%{invalidation: invalidation, source_execution: source_execution})
      when is_map(invalidation) and is_map(source_execution) do
    %{
      "data-runtime-invalidation-events" => invalidation.event_count,
      "data-runtime-invalidation-artifacts" => invalidation.artifact_count,
      "data-runtime-invalidation-boundaries" => invalidation.boundary_summary,
      "data-runtime-invalidation-context-matches" => invalidation.context_match_count,
      "data-runtime-invalidation-context-filtered" => invalidation.context_filtered_count,
      "data-runtime-invalidation-context-filter-reasons" => invalidation.context_filter_reasons,
      "data-runtime-invalidation-refresh-allowed" => invalidation.refresh_allowed_count,
      "data-runtime-invalidation-refresh-suppressed" => invalidation.refresh_suppressed_count,
      "data-runtime-invalidation-refresh-suppress-reasons" =>
        invalidation.refresh_suppress_reasons,
      "data-runtime-source-execution-actions" => source_execution.runtime_actions,
      "data-runtime-source-execution-retryable" => source_execution.retryable_count,
      "data-runtime-source-execution-actionable" => source_execution.actionable_count,
      "data-runtime-source-execution-degraded" => source_execution.degraded_count,
      "data-runtime-source-execution-degraded-identities" => source_execution.degraded_identities,
      "data-runtime-source-execution-degraded-actions" => source_execution.degraded_actions,
      "data-runtime-last-invalidation-boundary" => invalidation.last_boundary,
      "data-runtime-last-invalidation-refresh-reason" => invalidation.last_refresh_reason,
      "data-runtime-last-invalidation-refresh-action" => invalidation.last_refresh_action
    }
  end

  @spec root_attrs(map()) :: map()
  def root_attrs(state) when is_map(state) do
    state
    |> runtime_root_attrs()
    |> Map.merge(invalidation_root_attrs(state))
  end
end
