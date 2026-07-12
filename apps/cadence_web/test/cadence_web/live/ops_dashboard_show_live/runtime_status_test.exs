defmodule CadenceWeb.OpsDashboardShowLive.RuntimeStatusTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.RuntimeCoordinator
  alias CadenceWeb.OpsDashboardShowLive.Runtime

  test "decision summary captures refresh and failure provenance" do
    decisions = [
      %{action: :start_resolve, resolve_mode: :live_tick, reason: :tick},
      %{action: :start_resolve, resolve_mode: :context_change, reason: :runtime_invalidation},
      %{action: :cancel_obsolete, resolve_mode: :context_change, reason: :runtime_invalidation},
      %{action: :coalesce_tick, resolve_mode: :live_tick, reason: :tick},
      %{action: :noop, resolve_mode: :live_tick, reason: :edit_mode},
      %{action: :noop, resolve_mode: :live_tick, reason: :not_live_time_mode},
      %{action: :accept_result, resolve_mode: :context_change, reason: :accepted},
      %{action: :record_degradation, reason: :resolve_failed},
      %{action: :ignore_result, resolve_id: "obsolete-1", reason: :obsolete_resolve}
    ]

    assert Runtime.decision_summary(decisions) == %{
             actions:
               "start_resolve start_resolve cancel_obsolete coalesce_tick noop noop accept_result record_degradation ignore_result",
             refresh_starts: "context_change:runtime_invalidation:1 live_tick:tick:1",
             refresh_cancellations: "context_change:runtime_invalidation:1",
             refresh_coalesced: "live_tick:tick:1",
             refresh_noops: "live_tick:edit_mode:1 live_tick:not_live_time_mode:1",
             refresh_failures: "resolve_failed:1",
             refresh_ignored: "obsolete_resolve:1",
             refresh_ignored_resolve_ids: "obsolete-1",
             last_refresh_started_at: nil,
             last_refresh_finished_at: nil,
             last_refresh_duration_ms: nil,
             canceled_resolve_count: 1,
             failed_resolve_count: 1
           }
  end

  test "refresh status reports active resolving work" do
    coordinator = RuntimeCoordinator.new(status: :resolving, active_mode: :live_tick)

    assert Runtime.refresh_status(coordinator, [], false) == %{
             status: "refreshing",
             reason: "live_tick",
             active_mode: "live_tick",
             active_started_at: nil,
             visible_action: nil
           }
  end

  test "refresh status follows the latest visible freshness decision" do
    coordinator = RuntimeCoordinator.new()

    assert Runtime.refresh_status(
             coordinator,
             [
               %{action: :start_resolve, resolve_mode: :initial},
               %{action: :accept_result, resolve_id: 1},
               %{action: :ignore_result, resolve_id: 0, reason: :obsolete_resolve}
             ],
             true
           ) == %{
             status: "settled",
             reason: "accepted",
             active_mode: nil,
             active_started_at: nil,
             visible_action: "accept_result"
           }

    assert Runtime.refresh_status(
             coordinator,
             [%{action: :record_degradation, reason: :resolve_failed}],
             true
           ) == %{
             status: "degraded",
             reason: "resolve_failed",
             active_mode: nil,
             active_started_at: nil,
             visible_action: "record_degradation"
           }

    assert Runtime.refresh_status(
             coordinator,
             [%{action: :noop, reason: :not_live_time_mode}],
             true
           ) == %{
             status: "suppressed",
             reason: "not_live_time_mode",
             active_mode: nil,
             active_started_at: nil,
             visible_action: "noop"
           }
  end
end
