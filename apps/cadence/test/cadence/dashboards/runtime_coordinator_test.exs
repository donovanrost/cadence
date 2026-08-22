defmodule Cadence.Dashboards.RuntimeCoordinatorTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.RuntimeCoordinator

  test "starts a live tick resolve when idle" do
    {state, decisions} =
      RuntimeCoordinator.new()
      |> RuntimeCoordinator.request_resolve(:live_tick)

    assert state.status == :resolving
    assert state.active_mode == :live_tick
    assert state.active_resolve_id == 1

    assert [
             %{
               action: :start_resolve,
               resolve_mode: :live_tick,
               resolve_id: 1
             }
           ] = decisions
  end

  test "coalesces repeated live ticks while a resolve is active" do
    {state, _decisions} =
      RuntimeCoordinator.new()
      |> RuntimeCoordinator.request_resolve(:live_tick)

    {state, decisions} = RuntimeCoordinator.request_resolve(state, :live_tick)

    assert state.status == :resolving
    assert state.active_resolve_id == 1
    assert state.pending_mode == :live_tick
    assert state.coalesced_tick_count == 1

    assert [
             %{
               action: :coalesce_tick,
               resolve_mode: :live_tick,
               resolve_id: 1,
               details: %{coalesced_tick_count: 1}
             }
           ] = decisions

    {state, decisions} = RuntimeCoordinator.request_resolve(state, :live_tick)

    assert state.pending_mode == :live_tick
    assert state.coalesced_tick_count == 2

    assert [
             %{
               action: :coalesce_tick,
               details: %{coalesced_tick_count: 2}
             }
           ] = decisions
  end

  test "starts one replacement live tick after an active resolve finishes" do
    {state, _decisions} =
      RuntimeCoordinator.new()
      |> RuntimeCoordinator.request_resolve(:live_tick)

    {state, _decisions} = RuntimeCoordinator.request_resolve(state, :live_tick)
    {state, decisions} = RuntimeCoordinator.resolve_finished(state, 1)

    assert state.status == :resolving
    assert state.active_mode == :live_tick
    assert state.active_resolve_id == 2
    assert state.pending_mode == nil

    assert [
             %{action: :accept_result, resolve_id: 1},
             %{action: :start_resolve, resolve_mode: :live_tick, resolve_id: 2}
           ] = decisions
  end

  test "records start finish and duration timing on refresh decisions" do
    started_at = ~U[2026-06-24 12:00:00Z]
    finished_at = ~U[2026-06-24 12:00:01Z]

    {state, decisions} =
      RuntimeCoordinator.new()
      |> RuntimeCoordinator.request_resolve(:live_tick,
        started_at: started_at,
        started_monotonic_ms: 1_000
      )

    assert state.active_started_at == started_at
    assert state.active_started_monotonic_ms == 1_000

    assert [
             %{
               action: :start_resolve,
               details: %{
                 started_at: ^started_at,
                 started_monotonic_ms: 1_000
               }
             }
           ] = decisions

    {_state, decisions} =
      RuntimeCoordinator.resolve_finished(state, 1,
        finished_at: finished_at,
        finished_monotonic_ms: 1_075
      )

    assert [
             %{
               action: :accept_result,
               details: %{
                 started_at: ^started_at,
                 started_monotonic_ms: 1_000,
                 finished_at: ^finished_at,
                 finished_monotonic_ms: 1_075,
                 duration_ms: 75
               }
             }
           ] = decisions
  end

  test "context change supersedes an active live tick resolve" do
    {state, _decisions} =
      RuntimeCoordinator.new()
      |> RuntimeCoordinator.request_resolve(:live_tick)

    {state, decisions} =
      RuntimeCoordinator.request_resolve(state, :context_change, reason: :runtime_context_changed)

    assert state.status == :resolving
    assert state.active_mode == :context_change
    assert state.active_resolve_id == 2

    assert [
             %{
               action: :cancel_obsolete,
               resolve_mode: :context_change,
               superseded_resolve_id: 1,
               resolve_id: 2,
               reason: :runtime_context_changed
             },
             %{
               action: :start_resolve,
               resolve_mode: :context_change,
               resolve_id: 2,
               reason: :runtime_context_changed
             }
           ] = decisions

    {state, decisions} = RuntimeCoordinator.resolve_finished(state, 1)

    assert state.active_resolve_id == 2
    assert [%{action: :ignore_result, resolve_id: 1, reason: :obsolete_resolve}] = decisions
  end

  test "suppresses refresh modes when runtime refresh is not allowed" do
    state = RuntimeCoordinator.new()

    assert {^state, [%{action: :noop, resolve_mode: :live_tick, reason: :edit_mode}]} =
             RuntimeCoordinator.request_resolve(state, :live_tick,
               refresh_allowed?: false,
               reason: :edit_mode
             )
  end

  test "records source failure and backoff inputs on failed active resolve" do
    failed_at = ~U[2026-06-20 18:00:00Z]
    cooldown_until = DateTime.add(failed_at, 5_000, :millisecond)

    {state, _decisions} =
      RuntimeCoordinator.new(failure_threshold: 2)
      |> RuntimeCoordinator.request_resolve(:live_tick)

    {state, decisions} =
      RuntimeCoordinator.resolve_failed(state, 1,
        logical_source: :telemetry,
        reason: :timeout,
        failed_at: failed_at,
        cooldown_ms: 5_000
      )

    assert state.status == :idle

    assert state.source_failures.telemetry == %{
             count: 1,
             degraded?: false,
             last_reason: :timeout,
             failed_at: failed_at,
             cooldown_until: cooldown_until
           }

    assert [
             %{
               action: :record_degradation,
               resolve_id: 1,
               reason: :timeout,
               details: %{
                 logical_source: :telemetry,
                 count: 1,
                 degraded?: false,
                 failed_at: ^failed_at,
                 cooldown_until: ^cooldown_until
               }
             }
           ] = decisions

    {state, _decisions} = RuntimeCoordinator.request_resolve(state, :live_tick)

    {state, _decisions} =
      RuntimeCoordinator.resolve_failed(state, 2,
        logical_source: :telemetry,
        reason: :timeout,
        failed_at: failed_at,
        cooldown_ms: 5_000
      )

    assert state.source_failures.telemetry.degraded?
  end

  test "clears source failure state after recovery" do
    {state, _decisions} =
      RuntimeCoordinator.new()
      |> RuntimeCoordinator.request_resolve(:live_tick)

    {state, _decisions} =
      RuntimeCoordinator.resolve_failed(state, 1,
        logical_source: :limits,
        reason: :source_degraded
      )

    assert Map.has_key?(state.source_failures, :limits)

    state = RuntimeCoordinator.source_recovered(state, :limits)

    refute Map.has_key?(state.source_failures, :limits)
  end
end
