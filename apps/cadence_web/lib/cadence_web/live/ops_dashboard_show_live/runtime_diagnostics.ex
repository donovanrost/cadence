defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDiagnostics do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RuntimeCacheDiagnostics
  alias CadenceWeb.OpsDashboardShowLive.RuntimeEngineDiagnostics
  alias CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationDiagnostics
  alias CadenceWeb.OpsDashboardShowLive.RuntimeRefreshDiagnostics
  alias CadenceWeb.OpsDashboardShowLive.RuntimeSourceExecutionDiagnostics
  alias CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummary

  def build(%{
        engine_result: engine_result,
        runtime_coordinator: runtime_coordinator,
        decisions: decisions,
        resolved?: resolved?,
        invalidation: invalidation,
        last_invalidation: last_invalidation,
        runtime_invalidation_events: runtime_invalidation_events,
        current_scope: current_scope,
        mission: mission,
        document: document,
        runtime_context: runtime_context
      }) do
    source_execution_summary = SourceExecutionRuntimeSummary.build(engine_result)
    source_execution = RuntimeSourceExecutionDiagnostics.build(source_execution_summary)

    refresh_diagnostics =
      RuntimeRefreshDiagnostics.build(
        runtime_coordinator,
        decisions,
        resolved?,
        source_execution
      )

    recent_invalidations =
      RuntimeInvalidationDiagnostics.recent_invalidations(
        runtime_invalidation_events,
        current_scope,
        mission,
        document,
        runtime_context
      )

    invalidation_relevance =
      RuntimeInvalidationDiagnostics.relevance_summary(recent_invalidations)

    no_refresh_summary =
      RuntimeInvalidationDiagnostics.no_refresh_summary(
        invalidation,
        invalidation_relevance,
        recent_invalidations
      )

    %{
      engine_rows: RuntimeEngineDiagnostics.rows(engine_result),
      cache_summary:
        RuntimeCacheDiagnostics.summary(engine_result, source_execution_summary.source_incidents),
      runtime_rows: refresh_diagnostics.rows,
      invalidation_rows:
        RuntimeInvalidationDiagnostics.rows(
          invalidation,
          invalidation_relevance,
          last_invalidation
        ),
      recent_invalidations: recent_invalidations,
      no_refresh_summary: no_refresh_summary,
      source_execution_runtime_actions: source_execution.runtime_actions_text,
      source_execution_retryable_count: source_execution.retryable_count,
      source_execution_actionable_count: source_execution.actionable_count,
      source_execution_degraded_count: source_execution.degraded_count,
      source_execution_degraded_identities: source_execution.degraded_identities_text,
      source_execution_degraded_actions: source_execution.degraded_actions_text,
      source_execution_degraded_summary: source_execution.degraded_summary,
      source_execution_degraded_drilldowns: source_execution.degraded_drilldowns,
      source_capability_statuses: source_execution.capability_statuses,
      source_capability_statuses_text: source_execution.capability_statuses_text,
      source_capability_postures: source_execution.capability_postures,
      source_capability_posture_text: source_execution.capability_posture_text,
      source_dependency_evidence: source_execution.dependency_evidence,
      source_dependency_evidence_text: source_execution.dependency_evidence_text,
      source_dependency_degraded_count: source_execution.dependency_degraded_count
    }
    |> Map.merge(refresh_diagnostics.attrs)
    |> Map.merge(RuntimeInvalidationDiagnostics.attrs(invalidation, invalidation_relevance))
  end
end
