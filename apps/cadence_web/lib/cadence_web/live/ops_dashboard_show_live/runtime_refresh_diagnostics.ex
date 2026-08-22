defmodule CadenceWeb.OpsDashboardShowLive.RuntimeRefreshDiagnostics do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.Runtime
  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticFormatter
  alias CadenceWeb.OpsDashboardShowLive.RuntimeSourceExecutionDiagnostics

  def build(runtime_coordinator, decisions, resolved?, source_execution_summary) do
    source_execution = RuntimeSourceExecutionDiagnostics.normalize(source_execution_summary)
    decision_summary = Runtime.decision_summary(decisions)

    refresh_status =
      runtime_coordinator
      |> Runtime.refresh_status(decisions, resolved?)
      |> RuntimeSourceExecutionDiagnostics.maybe_degrade_refresh_status(source_execution)

    %{
      decision_summary: decision_summary,
      refresh_status_summary: refresh_status,
      rows:
        rows(
          runtime_coordinator,
          decision_summary,
          refresh_status,
          resolved?,
          source_execution
        ),
      attrs: attrs(decision_summary, refresh_status)
    }
  end

  def attrs(decision_summary, refresh_status) do
    %{
      refresh_status: RuntimeDiagnosticFormatter.value(refresh_status.status),
      refresh_reason: RuntimeDiagnosticFormatter.value(refresh_status.reason),
      active_refresh_mode: RuntimeDiagnosticFormatter.value(refresh_status.active_mode),
      active_refresh_started_at:
        RuntimeDiagnosticFormatter.value(refresh_status.active_started_at),
      visible_refresh_action: RuntimeDiagnosticFormatter.value(refresh_status.visible_action),
      last_refresh_started_at:
        RuntimeDiagnosticFormatter.value(decision_summary.last_refresh_started_at),
      last_refresh_finished_at:
        RuntimeDiagnosticFormatter.value(decision_summary.last_refresh_finished_at),
      last_refresh_duration_ms:
        RuntimeDiagnosticFormatter.value(decision_summary.last_refresh_duration_ms),
      refresh_starts: RuntimeDiagnosticFormatter.value(decision_summary.refresh_starts),
      refresh_cancellations:
        RuntimeDiagnosticFormatter.value(decision_summary.refresh_cancellations),
      refresh_coalesced: RuntimeDiagnosticFormatter.value(decision_summary.refresh_coalesced),
      refresh_noops: RuntimeDiagnosticFormatter.value(decision_summary.refresh_noops),
      refresh_failures: RuntimeDiagnosticFormatter.value(decision_summary.refresh_failures),
      refresh_ignored: RuntimeDiagnosticFormatter.value(decision_summary.refresh_ignored),
      refresh_ignored_resolve_ids:
        RuntimeDiagnosticFormatter.value(decision_summary.refresh_ignored_resolve_ids),
      canceled_resolve_count: decision_summary.canceled_resolve_count,
      failed_resolve_count: decision_summary.failed_resolve_count
    }
  end

  def rows(
        runtime_coordinator,
        decision_summary,
        refresh_status,
        resolved?,
        source_execution_summary
      ) do
    source_execution_summary =
      RuntimeSourceExecutionDiagnostics.normalize(source_execution_summary)

    [
      RuntimeDiagnosticFormatter.row("Status", status(runtime_coordinator)),
      RuntimeDiagnosticFormatter.row("Refresh status", refresh_status.status),
      RuntimeDiagnosticFormatter.row("Refresh reason", refresh_status.reason),
      RuntimeDiagnosticFormatter.row("Active refresh", refresh_status.active_mode),
      RuntimeDiagnosticFormatter.row("Active refresh started", refresh_status.active_started_at),
      RuntimeDiagnosticFormatter.row(
        "Last refresh started",
        decision_summary.last_refresh_started_at
      ),
      RuntimeDiagnosticFormatter.row(
        "Last refresh finished",
        decision_summary.last_refresh_finished_at
      ),
      RuntimeDiagnosticFormatter.row(
        "Last refresh duration ms",
        decision_summary.last_refresh_duration_ms
      ),
      RuntimeDiagnosticFormatter.row("Visible refresh", refresh_status.visible_action),
      RuntimeDiagnosticFormatter.row("Resolved", resolved?),
      RuntimeDiagnosticFormatter.row("Decisions", decision_summary.actions),
      RuntimeDiagnosticFormatter.row("Refresh starts", decision_summary.refresh_starts),
      RuntimeDiagnosticFormatter.row(
        "Refresh cancellations",
        decision_summary.refresh_cancellations
      ),
      RuntimeDiagnosticFormatter.row("Refresh coalesced", decision_summary.refresh_coalesced),
      RuntimeDiagnosticFormatter.row("Refresh noops", decision_summary.refresh_noops),
      RuntimeDiagnosticFormatter.row("Refresh failures", decision_summary.refresh_failures),
      RuntimeDiagnosticFormatter.row("Ignored results", decision_summary.refresh_ignored),
      RuntimeDiagnosticFormatter.row(
        "Ignored result resolve ids",
        decision_summary.refresh_ignored_resolve_ids
      ),
      RuntimeDiagnosticFormatter.row(
        "Source runtime actions",
        source_execution_summary.runtime_actions_text
      ),
      RuntimeDiagnosticFormatter.row(
        "Retryable source requests",
        source_execution_summary.retryable_count
      ),
      RuntimeDiagnosticFormatter.row(
        "Actionable source requests",
        source_execution_summary.actionable_count
      ),
      RuntimeDiagnosticFormatter.row(
        "Degraded source requests",
        source_execution_summary.degraded_count
      ),
      RuntimeDiagnosticFormatter.row(
        "Degraded source identities",
        source_execution_summary.degraded_identities_text
      ),
      RuntimeDiagnosticFormatter.row(
        "Degraded source actions",
        source_execution_summary.degraded_actions_text
      )
    ]
  end

  def status(%{status: status}) when is_atom(status), do: Atom.to_string(status)
  def status(%{status: status}) when is_binary(status), do: status
  def status(_coordinator), do: nil

  def decision_actions(decisions) when is_list(decisions) do
    decisions
    |> Runtime.decision_summary()
    |> Map.get(:actions)
  end

  def decision_actions(_decisions), do: nil
end
