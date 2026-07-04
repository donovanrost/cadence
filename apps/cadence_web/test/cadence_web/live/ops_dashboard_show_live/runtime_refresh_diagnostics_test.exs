defmodule CadenceWeb.OpsDashboardShowLive.RuntimeRefreshDiagnosticsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.RuntimeCoordinator
  alias CadenceWeb.OpsDashboardShowLive.Runtime
  alias CadenceWeb.OpsDashboardShowLive.RuntimeRefreshDiagnostics
  alias CadenceWeb.OpsDashboardShowLive.RuntimeSourceExecutionDiagnostics

  test "build formats refresh attrs and rows from runtime decisions" do
    decisions = [
      %{action: :start_resolve, resolve_mode: :live_tick, reason: :tick},
      %{action: :start_resolve, resolve_mode: :context_change, reason: :runtime_invalidation},
      %{action: :cancel_obsolete, resolve_mode: :context_change, reason: :runtime_invalidation},
      %{action: :coalesce_tick, resolve_mode: :live_tick, reason: :tick},
      %{action: :noop, resolve_mode: :live_tick, reason: :edit_mode},
      %{action: :record_degradation, reason: :resolve_failed},
      %{action: :ignore_result, resolve_id: "obsolete-1", reason: :obsolete_resolve},
      %{action: :accept_result, resolve_id: 1}
    ]

    diagnostics =
      RuntimeRefreshDiagnostics.build(
        RuntimeCoordinator.new(status: :idle),
        decisions,
        true,
        source_summary(degraded?: false)
      )

    assert diagnostics.attrs == %{
             refresh_status: "settled",
             refresh_reason: "accepted",
             active_refresh_mode: "-",
             active_refresh_started_at: "-",
             visible_refresh_action: "accept_result",
             last_refresh_started_at: "-",
             last_refresh_finished_at: "-",
             last_refresh_duration_ms: "-",
             refresh_starts: "context_change:runtime_invalidation:1 live_tick:tick:1",
             refresh_cancellations: "context_change:runtime_invalidation:1",
             refresh_coalesced: "live_tick:tick:1",
             refresh_noops: "live_tick:edit_mode:1",
             refresh_failures: "resolve_failed:1",
             refresh_ignored: "obsolete_resolve:1",
             refresh_ignored_resolve_ids: "obsolete-1",
             canceled_resolve_count: 1,
             failed_resolve_count: 1
           }

    assert %{label: "Status", value: "idle"} =
             Enum.find(diagnostics.rows, &(&1.label == "Status"))

    assert %{
             label: "Refresh starts",
             value: "context_change:runtime_invalidation:1 live_tick:tick:1"
           } =
             Enum.find(diagnostics.rows, &(&1.label == "Refresh starts"))

    assert %{label: "Source runtime actions", value: "refresh_source_result:2"} =
             Enum.find(diagnostics.rows, &(&1.label == "Source runtime actions"))

    assert %{label: "Degraded source identities", value: "-"} =
             Enum.find(diagnostics.rows, &(&1.label == "Degraded source identities"))
  end

  test "build marks refresh degraded when source execution is degraded" do
    diagnostics =
      RuntimeRefreshDiagnostics.build(
        RuntimeCoordinator.new(status: :idle),
        [%{action: :accept_result, resolve_id: 1}],
        true,
        source_summary()
      )

    assert diagnostics.attrs.refresh_status == "degraded"
    assert diagnostics.attrs.refresh_reason == "source_execution_degraded"

    assert %{label: "Refresh status", value: "degraded"} =
             Enum.find(diagnostics.rows, &(&1.label == "Refresh status"))
  end

  test "rows accepts already-built source execution diagnostics" do
    decisions = [%{action: :accept_result, resolve_id: 1}]
    decision_summary = Runtime.decision_summary(decisions)
    source_execution = RuntimeSourceExecutionDiagnostics.build(source_summary())

    rows =
      RuntimeRefreshDiagnostics.rows(
        RuntimeCoordinator.new(status: :idle),
        decision_summary,
        Runtime.refresh_status(%{}, decisions, true),
        true,
        source_execution
      )

    assert %{label: "Source runtime actions", value: "refresh_source_result:2"} =
             Enum.find(rows, &(&1.label == "Source runtime actions"))
  end

  test "status and decision actions are stable for root attributes" do
    assert RuntimeRefreshDiagnostics.status(RuntimeCoordinator.new(status: :idle)) == "idle"
    assert RuntimeRefreshDiagnostics.status(%{}) == nil

    assert RuntimeRefreshDiagnostics.decision_actions([
             %{action: :start_resolve},
             %{action: :accept_result}
           ]) == "start_resolve accept_result"

    assert RuntimeRefreshDiagnostics.decision_actions(:not_decisions) == nil
  end

  defp source_summary(opts \\ []) do
    source_summary = %{
      runtime_actions: %{nil => 0, refresh_source_result: 2},
      retryable_count: 1,
      actionable_count: 2,
      degraded_count: 1,
      degraded_incidents: []
    }

    if Keyword.get(opts, :degraded?, true) do
      %{
        source_summary
        | degraded_incidents: [
            %{
              logical_source: :telemetry,
              request_id: "req-1",
              status: :unsupported_capability,
              runtime_action: :requires_configuration_change,
              operator_action: :inspect_source_capability,
              realm: :flight,
              data_source_id: "questdb-flight",
              source_binding_id: "flight-binding"
            }
          ]
      }
    else
      source_summary
    end
  end
end
