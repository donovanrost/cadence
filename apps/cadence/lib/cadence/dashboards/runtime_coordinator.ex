defmodule Cadence.Dashboards.RuntimeCoordinator do
  @moduledoc """
  Pure dashboard runtime coordination state.

  The coordinator owns refresh/backpressure policy decisions, but does not
  execute resolves or manage processes. Callers apply returned decisions in the
  LiveView/session process or a future supervised runtime process.
  """

  alias Cadence.Dashboards.DashboardResolveRequest

  @type status :: :idle | :resolving
  @type resolve_mode :: DashboardResolveRequest.resolve_mode()
  @type decision_action ::
          :start_resolve
          | :coalesce_tick
          | :cancel_obsolete
          | :accept_result
          | :ignore_result
          | :record_degradation
          | :noop

  @type decision :: %{
          required(:action) => decision_action(),
          optional(:resolve_mode) => resolve_mode(),
          optional(:resolve_id) => term(),
          optional(:superseded_resolve_id) => term(),
          optional(:reason) => atom(),
          optional(:details) => map()
        }

  @type source_failure :: %{
          required(:count) => pos_integer(),
          required(:degraded?) => boolean(),
          required(:last_reason) => term(),
          required(:failed_at) => DateTime.t() | nil,
          required(:cooldown_until) => DateTime.t() | nil
        }

  @type t :: %__MODULE__{
          status: status(),
          generation: non_neg_integer(),
          active_resolve_id: term(),
          active_mode: resolve_mode() | nil,
          active_started_at: DateTime.t() | nil,
          active_started_monotonic_ms: integer() | nil,
          pending_mode: resolve_mode() | nil,
          pending_reason: atom() | nil,
          coalesced_tick_count: non_neg_integer(),
          failure_threshold: pos_integer(),
          source_failures: %{optional(atom() | binary()) => source_failure()},
          last_failure: map() | nil
        }

  defstruct status: :idle,
            generation: 0,
            active_resolve_id: nil,
            active_mode: nil,
            active_started_at: nil,
            active_started_monotonic_ms: nil,
            pending_mode: nil,
            pending_reason: nil,
            coalesced_tick_count: 0,
            failure_threshold: 3,
            source_failures: %{},
            last_failure: nil

  @resolve_modes [:initial, :context_change, :live_tick, :stream_append]
  @refresh_modes [:live_tick, :stream_append]
  @superseding_modes [:initial, :context_change]

  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []) when is_list(attrs) or is_map(attrs) do
    attrs
    |> Map.new()
    |> then(&struct!(__MODULE__, &1))
  end

  @doc """
  Request that the runtime begin or schedule a dashboard resolve.

  Returns the updated coordinator state and decisions for the caller to apply.
  Live refresh modes can be suppressed with `refresh_allowed?: false`, which is
  how edit/archive/non-live modes avoid unnecessary work.
  """
  @spec request_resolve(t(), resolve_mode(), keyword()) :: {t(), [decision()]}
  def request_resolve(%__MODULE__{} = state, mode, opts \\ [])
      when mode in @resolve_modes and is_list(opts) do
    cond do
      refresh_suppressed?(mode, opts) ->
        {state, [noop_decision(mode, Keyword.get(opts, :reason, :refresh_suppressed))]}

      state.status == :idle ->
        start_resolve(state, mode, opts)

      mode in @refresh_modes ->
        coalesce_refresh(state, mode, opts)

      mode in @superseding_modes ->
        supersede_active_resolve(state, mode, opts)
    end
  end

  @doc """
  Complete the active resolve successfully.

  Stale completions are ignored. If a live tick was coalesced while the active
  resolve was running, the coordinator starts one replacement resolve after
  accepting the completed result.
  """
  @spec resolve_finished(t(), term(), keyword()) :: {t(), [decision()]}
  def resolve_finished(%__MODULE__{} = state, resolve_id, opts \\ []) when is_list(opts) do
    finish_active_resolve(state, resolve_id, accept_decision(resolve_id), opts)
  end

  @doc """
  Complete the active resolve as failed and record degradation/backoff inputs.
  """
  @spec resolve_failed(t(), term(), keyword()) :: {t(), [decision()]}
  def resolve_failed(%__MODULE__{} = state, resolve_id, opts \\ []) when is_list(opts) do
    if state.active_resolve_id == resolve_id do
      {state, degradation_decision} = record_failure(state, opts)

      {state, decisions} =
        finish_active_resolve(state, resolve_id, degradation_decision, opts)

      {state, decisions}
    else
      {state, [ignore_decision(resolve_id)]}
    end
  end

  @doc """
  Clear recorded source degradation state after a healthy observation.
  """
  @spec source_recovered(t(), atom() | binary()) :: t()
  def source_recovered(%__MODULE__{} = state, logical_source)
      when is_atom(logical_source) or is_binary(logical_source) do
    %__MODULE__{state | source_failures: Map.delete(state.source_failures, logical_source)}
  end

  defp refresh_suppressed?(mode, opts) do
    mode in @refresh_modes and Keyword.get(opts, :refresh_allowed?, true) == false
  end

  defp start_resolve(%__MODULE__{} = state, mode, opts) do
    generation = state.generation + 1
    resolve_id = Keyword.get(opts, :resolve_id, generation)

    state = %__MODULE__{
      state
      | status: :resolving,
        generation: generation,
        active_resolve_id: resolve_id,
        active_mode: mode,
        active_started_at: Keyword.get(opts, :started_at),
        active_started_monotonic_ms: Keyword.get(opts, :started_monotonic_ms),
        pending_mode: nil,
        pending_reason: nil,
        coalesced_tick_count: 0
    }

    {state,
     [
       start_decision(mode, resolve_id, Keyword.get(opts, :reason, :requested), %{
         started_at: state.active_started_at,
         started_monotonic_ms: state.active_started_monotonic_ms
       })
     ]}
  end

  defp coalesce_refresh(%__MODULE__{} = state, mode, opts) do
    state = %__MODULE__{
      state
      | pending_mode: pending_refresh_mode(state.pending_mode, mode),
        pending_reason: Keyword.get(opts, :reason, :tick_coalesced),
        coalesced_tick_count: state.coalesced_tick_count + 1
    }

    {state,
     [
       %{
         action: :coalesce_tick,
         resolve_mode: mode,
         resolve_id: state.active_resolve_id,
         reason: Keyword.get(opts, :reason, :already_resolving),
         details: %{coalesced_tick_count: state.coalesced_tick_count}
       }
     ]}
  end

  defp supersede_active_resolve(%__MODULE__{} = state, mode, opts) do
    superseded_resolve_id = state.active_resolve_id

    {state, [start]} =
      %__MODULE__{
        state
        | status: :idle,
          active_resolve_id: nil,
          active_mode: nil,
          active_started_at: nil,
          active_started_monotonic_ms: nil
      }
      |> start_resolve(mode, opts)

    cancel = %{
      action: :cancel_obsolete,
      resolve_mode: mode,
      superseded_resolve_id: superseded_resolve_id,
      resolve_id: state.active_resolve_id,
      reason: Keyword.get(opts, :reason, :superseded)
    }

    {state, [cancel, start]}
  end

  defp finish_active_resolve(%__MODULE__{} = state, resolve_id, decision, opts) do
    if state.active_resolve_id == resolve_id do
      pending_mode = state.pending_mode
      pending_reason = state.pending_reason
      finish_timing = finish_timing(state, opts)
      decision = put_finish_timing(decision, finish_timing)

      state = %__MODULE__{
        state
        | status: :idle,
          active_resolve_id: nil,
          active_mode: nil,
          active_started_at: nil,
          active_started_monotonic_ms: nil,
          pending_mode: nil,
          pending_reason: nil,
          coalesced_tick_count: 0
      }

      case pending_mode do
        nil ->
          {state, [decision]}

        mode ->
          {state, [start]} =
            start_resolve(
              state,
              mode,
              opts
              |> Keyword.merge(reason: pending_reason || :coalesced_tick)
              |> Keyword.put(:started_at, finish_timing.finished_at)
              |> Keyword.put(:started_monotonic_ms, finish_timing.finished_monotonic_ms)
            )

          {state, [decision, start]}
      end
    else
      {state, [ignore_decision(resolve_id)]}
    end
  end

  defp pending_refresh_mode(:stream_append, _mode), do: :stream_append
  defp pending_refresh_mode(_pending_mode, :stream_append), do: :stream_append
  defp pending_refresh_mode(_pending_mode, mode), do: mode

  defp record_failure(%__MODULE__{} = state, opts) do
    failure = failure_details(state, opts)

    state =
      %__MODULE__{
        state
        | last_failure: Map.drop(failure, [:logical_source])
      }
      |> put_source_failure(failure)

    {state,
     %{
       action: :record_degradation,
       resolve_id: state.active_resolve_id,
       reason: failure.reason,
       details: Map.drop(failure, [:reason])
     }}
  end

  defp failure_details(%__MODULE__{} = state, opts) do
    logical_source = Keyword.get(opts, :logical_source)
    failed_at = Keyword.get(opts, :failed_at)
    cooldown_ms = Keyword.get(opts, :cooldown_ms)
    previous = if logical_source, do: Map.get(state.source_failures, logical_source, %{})
    count = Map.get(previous || %{}, :count, 0) + 1

    %{
      logical_source: logical_source,
      reason: Keyword.get(opts, :reason, :resolve_failed),
      count: count,
      degraded?: count >= state.failure_threshold,
      failed_at: failed_at,
      cooldown_until: cooldown_until(failed_at, cooldown_ms)
    }
  end

  defp put_source_failure(%__MODULE__{} = state, %{logical_source: nil}), do: state

  defp put_source_failure(%__MODULE__{} = state, failure) do
    source_failure = %{
      count: failure.count,
      degraded?: failure.degraded?,
      last_reason: failure.reason,
      failed_at: failure.failed_at,
      cooldown_until: failure.cooldown_until
    }

    %__MODULE__{
      state
      | source_failures: Map.put(state.source_failures, failure.logical_source, source_failure)
    }
  end

  defp cooldown_until(%DateTime{} = failed_at, cooldown_ms)
       when is_integer(cooldown_ms) and cooldown_ms > 0 do
    DateTime.add(failed_at, cooldown_ms, :millisecond)
  end

  defp cooldown_until(_failed_at, _cooldown_ms), do: nil

  defp start_decision(mode, resolve_id, reason, timing) do
    decision = %{
      action: :start_resolve,
      resolve_mode: mode,
      resolve_id: resolve_id,
      reason: reason
    }

    maybe_put_details(decision, Map.take(timing, [:started_at, :started_monotonic_ms]))
  end

  defp accept_decision(resolve_id) do
    %{action: :accept_result, resolve_id: resolve_id}
  end

  defp ignore_decision(resolve_id) do
    %{action: :ignore_result, resolve_id: resolve_id, reason: :obsolete_resolve}
  end

  defp noop_decision(mode, reason) do
    %{action: :noop, resolve_mode: mode, reason: reason}
  end

  defp finish_timing(%__MODULE__{} = state, opts) do
    finished_at = Keyword.get(opts, :finished_at)
    finished_monotonic_ms = Keyword.get(opts, :finished_monotonic_ms)

    %{
      started_at: state.active_started_at,
      started_monotonic_ms: state.active_started_monotonic_ms,
      finished_at: finished_at,
      finished_monotonic_ms: finished_monotonic_ms,
      duration_ms:
        duration_ms(
          state.active_started_at,
          state.active_started_monotonic_ms,
          finished_at,
          finished_monotonic_ms
        )
    }
  end

  defp put_finish_timing(decision, timing) do
    maybe_put_details(
      decision,
      Map.take(timing, [
        :started_at,
        :started_monotonic_ms,
        :finished_at,
        :finished_monotonic_ms,
        :duration_ms
      ])
    )
  end

  defp maybe_put_details(decision, details) do
    details =
      details
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    if map_size(details) == 0 do
      decision
    else
      Map.update(decision, :details, details, &Map.merge(&1, details))
    end
  end

  defp duration_ms(_started_at, started_monotonic_ms, _finished_at, finished_monotonic_ms)
       when is_integer(started_monotonic_ms) and is_integer(finished_monotonic_ms) do
    max(finished_monotonic_ms - started_monotonic_ms, 0)
  end

  defp duration_ms(
         %DateTime{} = started_at,
         _started_monotonic_ms,
         %DateTime{} = finished_at,
         _finished_monotonic_ms
       ) do
    max(DateTime.diff(finished_at, started_at, :millisecond), 0)
  end

  defp duration_ms(_started_at, _started_monotonic_ms, _finished_at, _finished_monotonic_ms),
    do: nil
end
