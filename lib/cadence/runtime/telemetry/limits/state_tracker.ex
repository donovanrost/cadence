defmodule Cadence.Runtime.Telemetry.Limits.StateTracker do
  @moduledoc """
  Tracks limit states and handles persistence-based state transitions.

  The StateTracker maintains an ETS table per mission that tracks:
  - Current reported limit state for each item
  - Pending state being accumulated (for persistence counting)
  - Violation count (consecutive violations)
  - Last update timestamp (for staleness detection)

  ## Persistence Logic

  When an item violates limits:
  1. If same violation type as pending, increment violation count
  2. If different violation type, reset and start counting new violation
  3. When violation_count >= persistence, transition to new state and emit event

  When an item returns to green:
  1. Immediately transition to green (no persistence required)
  2. Reset violation count

  ## ETS Table Structure

  - Table: `limits_state_<mission_id>`
  - Key: `{target_id, qualified_item_name}`
  - Value: `%{current_state, pending_state, violation_count, last_update, persistence}`

  ## Events

  On state transitions, emits `TelemetryLimitEvent` via PubSub.
  """

  use GenServer
  require Logger

  alias Cadence.Ports.Messaging.EventPublisher
  alias Cadence.Runtime.Telemetry.Limits.Cache
  alias Cadence.Telemetry.Events.TelemetryLimitEvent
  alias Cadence.Telemetry.Limits.Evaluator
  alias Cadence.Time, as: CadenceTime

  @type state_entry :: %{
          current_state: Evaluator.limit_state(),
          pending_state: Evaluator.limit_state() | nil,
          violation_count: non_neg_integer(),
          last_update: DateTime.t(),
          persistence: pos_integer(),
          stale_timeout_ms: pos_integer()
        }

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the state tracker for a specific mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @doc """
  Evaluates and updates the limit state for an item.

  Returns the final limit state (after applying persistence logic) and whether
  a state transition occurred.

  ## Parameters

  - `mission_id` - Mission identifier
  - `target_id` - Target identifier
  - `qualified_item_name` - Fully qualified item name (e.g., "HEALTH.cpu_temp")
  - `value` - The telemetry value to evaluate

  ## Returns

  - `{:ok, state, transition?}` where:
    - `state` is the normalized limit state (:green, :yellow, :red, :blue)
    - `transition?` is true if state changed

  - `{:error, reason}` on failure
  """
  @spec evaluate_and_track(String.t(), String.t(), String.t(), any()) ::
          {:ok, atom(), boolean()} | {:error, term()}
  def evaluate_and_track(mission_id, target_id, qualified_item_name, value) do
    case Cache.get_limits(mission_id, target_id, qualified_item_name) do
      {:ok, limits, persistence, stale_timeout_ms} ->
        # Evaluate the value against limits
        raw_state = Evaluator.evaluate(value, limits)

        # Update state tracker and check for transitions
        update_state(
          mission_id,
          target_id,
          qualified_item_name,
          raw_state,
          value,
          persistence,
          stale_timeout_ms
        )

      :not_configured ->
        # No limits configured, always green
        {:ok, :green, false}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Batch evaluates and tracks limits for multiple items.

  More efficient than calling evaluate_and_track multiple times because it:
  - Fetches cache data once for all items
  - Reuses the ETS table reference
  - Uses monotonic time once for all updates

  ## Parameters

  - `mission_id` - Mission identifier
  - `target_id` - Target identifier
  - `items` - List of `{qualified_item_name, value}` tuples

  ## Returns

  List of `{qualified_item_name, value, normalized_state}` tuples.
  """
  @spec evaluate_batch(String.t(), String.t(), [{String.t(), any()}]) ::
          [{String.t(), any(), atom()}]
  def evaluate_batch(mission_id, target_id, items) do
    # Get cache data once for all items
    cache_data = Cache.get_cached_data(mission_id, target_id)
    table_name = table_name(mission_id)
    now = CadenceTime.monotonic(:millisecond)

    # Check if table exists once
    table_exists? = :ets.whereis(table_name) != :undefined

    Enum.map(items, fn {item_name, value} ->
      state =
        evaluate_item_batch(
          mission_id,
          target_id,
          item_name,
          value,
          cache_data,
          table_name,
          table_exists?,
          now
        )

      {item_name, value, state}
    end)
  end

  @doc """
  Batch evaluates limits without persistence tracking.

  This is intended for stateless limits evaluation in the ingest path.
  """
  @spec evaluate_stateless_batch(String.t(), String.t(), [{String.t(), any()}]) ::
          [{String.t(), any(), atom()}]
  def evaluate_stateless_batch(mission_id, target_id, items) do
    cache_data = Cache.get_cached_data(mission_id, target_id)

    Enum.map(items, fn {item_name, value} ->
      state =
        case get_limits_from_cache_data(cache_data, item_name) do
          {:ok, limits, _persistence, _stale_timeout_ms} ->
            value |> Evaluator.evaluate(limits) |> Evaluator.normalize_state()

          _ ->
            :green
        end

      {item_name, value, state}
    end)
  end

  # Optimized per-item evaluation for batch processing
  defp evaluate_item_batch(
         mission_id,
         target_id,
         item_name,
         value,
         cache_data,
         table_name,
         table_exists?,
         now
       ) do
    case get_limits_from_cache_data(cache_data, item_name) do
      {:ok, limits, persistence, stale_timeout_ms} ->
        evaluate_with_limits(%{
          mission_id: mission_id,
          target_id: target_id,
          item_name: item_name,
          value: value,
          limits: limits,
          persistence: persistence,
          stale_timeout_ms: stale_timeout_ms,
          table_name: table_name,
          table_exists?: table_exists?,
          now: now
        })

      :not_configured ->
        :green

      {:error, _reason} ->
        :green
    end
  end

  defp evaluate_with_limits(%{
         mission_id: mission_id,
         target_id: target_id,
         item_name: item_name,
         value: value,
         limits: limits,
         persistence: persistence,
         stale_timeout_ms: stale_timeout_ms,
         table_name: table_name,
         table_exists?: table_exists?,
         now: now
       }) do
    raw_state = Evaluator.evaluate(value, limits)
    normalized_state = Evaluator.normalize_state(raw_state)

    if table_exists? do
      update_or_fallback(%{
        mission_id: mission_id,
        target_id: target_id,
        qualified_item_name: item_name,
        raw_state: raw_state,
        value: value,
        persistence: persistence,
        stale_timeout_ms: stale_timeout_ms,
        table_name: table_name,
        now_mono: now,
        fallback_state: normalized_state
      })
    else
      normalized_state
    end
  end

  defp update_or_fallback(%{
         mission_id: mission_id,
         target_id: target_id,
         qualified_item_name: qualified_item_name,
         raw_state: raw_state,
         value: value,
         persistence: persistence,
         stale_timeout_ms: stale_timeout_ms,
         table_name: table_name,
         now_mono: now_mono,
         fallback_state: fallback_state
       }) do
    case update_state_batch(%{
           mission_id: mission_id,
           target_id: target_id,
           qualified_item_name: qualified_item_name,
           raw_state: raw_state,
           value: value,
           persistence: persistence,
           stale_timeout_ms: stale_timeout_ms,
           table_name: table_name,
           now_mono: now_mono
         }) do
      {:ok, state, _transition?} -> state
      _ -> fallback_state
    end
  end

  # Extract limits from pre-fetched cache data
  defp get_limits_from_cache_data({:ok, item_limits_map, active_limit_set}, item_name) do
    case Map.get(item_limits_map, item_name) do
      nil ->
        :not_configured

      %{has_limits: false} ->
        :not_configured

      %{has_limits: true, limits_config: limits_config} = config ->
        limits = Map.get(limits_config, active_limit_set) || Map.get(limits_config, "DEFAULT")

        if limits do
          {:ok, limits, Map.get(config, :persistence, 1),
           Map.get(config, :stale_timeout_ms, 30_000)}
        else
          :not_configured
        end
    end
  end

  defp get_limits_from_cache_data({:error, reason}, _item_name), do: {:error, reason}
  defp get_limits_from_cache_data(_, _item_name), do: :not_configured

  # Optimized state update for batch processing (avoids redundant lookups)
  defp update_state_batch(%{
         mission_id: mission_id,
         target_id: target_id,
         qualified_item_name: qualified_item_name,
         raw_state: raw_state,
         value: value,
         persistence: persistence,
         stale_timeout_ms: stale_timeout_ms,
         table_name: table_name,
         now_mono: now_mono
       }) do
    key = {target_id, qualified_item_name}
    normalized_state = Evaluator.normalize_state(raw_state)

    ctx = %{
      mission_id: mission_id,
      target_id: target_id,
      qualified_item_name: qualified_item_name,
      table_name: table_name,
      key: key,
      raw_state: raw_state,
      normalized_state: normalized_state,
      value: value,
      persistence: persistence,
      stale_timeout_ms: stale_timeout_ms,
      timestamp_key: :last_update_mono,
      timestamp: now_mono
    }

    case :ets.lookup(table_name, key) do
      [{^key, entry}] ->
        process_state_update(Map.put(ctx, :entry, entry))

      [] ->
        create_initial_entry(ctx)
    end
  end

  @doc """
  Gets the current state for an item.

  Returns `{:ok, state_entry}` or `{:error, :not_found}`.
  """
  @spec get_state(String.t(), String.t(), String.t()) ::
          {:ok, state_entry()} | {:error, :not_found}
  def get_state(mission_id, target_id, qualified_item_name) do
    table_name = table_name(mission_id)

    if :ets.whereis(table_name) != :undefined do
      case :ets.lookup(table_name, {target_id, qualified_item_name}) do
        [{_key, entry}] -> {:ok, entry}
        [] -> {:error, :not_found}
      end
    else
      {:error, :not_found}
    end
  end

  @doc """
  Gets all tracked items for a target.

  Returns a map of `qualified_item_name => state_entry`.
  """
  @spec get_all_states(String.t(), String.t()) :: map()
  def get_all_states(mission_id, target_id) do
    table_name = table_name(mission_id)

    if :ets.whereis(table_name) != :undefined do
      table_name
      |> :ets.match({{target_id, :"$1"}, :"$2"})
      |> Enum.map(fn [item_name, entry] -> {item_name, entry} end)
      |> Map.new()
    else
      %{}
    end
  end

  @doc """
  Gets all stale items for a mission (items past their stale_timeout_ms).

  Used by StalenessMonitor to find items that should transition to :blue.
  """
  @spec get_stale_items(String.t()) :: [{String.t(), String.t(), state_entry()}]
  def get_stale_items(mission_id) do
    table_name = table_name(mission_id)
    now_mono = CadenceTime.monotonic(:millisecond)

    fetch_stale_items(table_name, now_mono)
  end

  defp fetch_stale_items(table_name, now_mono) do
    if :ets.whereis(table_name) != :undefined do
      :ets.foldl(&collect_stale(&1, &2, now_mono), [], table_name)
    else
      []
    end
  end

  defp collect_stale({{target_id, item_name}, entry}, acc, now_mono) do
    if stale_entry?(entry, now_mono) do
      [{target_id, item_name, entry} | acc]
    else
      acc
    end
  end

  defp stale_entry?(entry, now_mono) do
    time_since_update = time_since_update_ms(entry, now_mono)
    time_since_update >= entry.stale_timeout_ms and entry.current_state != :blue
  end

  # Support both old (last_update DateTime) and new (last_update_mono) formats
  defp time_since_update_ms(entry, now_mono) do
    case Map.get(entry, :last_update_mono) do
      nil -> legacy_time_since_update_ms(entry)
      mono -> now_mono - mono
    end
  end

  defp legacy_time_since_update_ms(entry) do
    case Map.get(entry, :last_update) do
      nil -> 0
      dt -> DateTime.diff(CadenceTime.now(), dt, :millisecond)
    end
  end

  @doc """
  Marks an item as stale (blue state).

  Called by StalenessMonitor when item hasn't been updated within timeout.
  """
  @spec mark_stale(String.t(), String.t(), String.t()) :: {:ok, boolean()}
  def mark_stale(mission_id, target_id, qualified_item_name) do
    table_name = table_name(mission_id)

    case fetch_entry(table_name, target_id, qualified_item_name) do
      {:ok, key, entry} ->
        mark_entry_stale(table_name, mission_id, target_id, qualified_item_name, key, entry)

      :not_found ->
        {:ok, false}
    end
  end

  defp fetch_entry(table_name, target_id, qualified_item_name) do
    if :ets.whereis(table_name) != :undefined do
      case :ets.lookup(table_name, {target_id, qualified_item_name}) do
        [{key, entry}] -> {:ok, key, entry}
        [] -> :not_found
      end
    else
      :not_found
    end
  end

  defp mark_entry_stale(table_name, mission_id, target_id, qualified_item_name, key, entry) do
    if entry.current_state != :blue do
      emit_transition_event(
        mission_id,
        target_id,
        qualified_item_name,
        entry.current_state,
        :blue,
        nil
      )

      new_entry = %{entry | current_state: :blue}
      :ets.insert(table_name, {key, new_entry})
      {:ok, true}
    else
      {:ok, false}
    end
  end

  @doc """
  Clears all state tracking for a mission.
  """
  @spec clear(String.t()) :: :ok
  def clear(mission_id) do
    table_name = table_name(mission_id)

    if :ets.whereis(table_name) != :undefined do
      :ets.delete_all_objects(table_name)
    end

    :ok
  end

  @doc """
  Returns statistics about the state tracker for a mission.

  ## Returns

  - `%{tracked_items: count, transitions: count, table_memory_bytes: bytes}`
  - `%{error: :not_found}` if tracker not running
  """
  @spec stats(String.t()) :: map()
  def stats(mission_id) do
    table_name = table_name(mission_id)

    if :ets.whereis(table_name) != :undefined do
      info = :ets.info(table_name)
      size = Keyword.get(info, :size, 0)
      memory_words = Keyword.get(info, :memory, 0)
      word_size = :erlang.system_info(:wordsize)

      # Count items in different states
      state_counts =
        :ets.foldl(
          fn {_key, entry}, acc ->
            state = entry.current_state
            Map.update(acc, state, 1, &(&1 + 1))
          end,
          %{},
          table_name
        )

      %{
        tracked_items: size,
        table_memory_bytes: memory_words * word_size,
        state_counts: state_counts,
        # Transitions counter would need to be tracked separately
        # For now, return 0 (could be enhanced later)
        transitions: 0
      }
    else
      %{error: :not_found}
    end
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init(mission_id) do
    table_name = table_name(mission_id)

    Logger.debug("Starting Limits.StateTracker for mission_id=#{mission_id}")

    Logger.info("Creating limits state tracker table: #{table_name}")

    _table =
      :ets.new(table_name, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, %{mission_id: mission_id, table_name: table_name}}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Logger.debug("Stopping Limits.StateTracker for mission_id=#{state.mission_id}")
    Logger.info("Terminating limits state tracker: #{state.table_name}")
    :ets.delete(state.table_name)
    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp update_state(
         mission_id,
         target_id,
         qualified_item_name,
         raw_state,
         value,
         persistence,
         stale_timeout_ms
       ) do
    table_name = table_name(mission_id)
    key = {target_id, qualified_item_name}
    now = CadenceTime.now()
    normalized_state = Evaluator.normalize_state(raw_state)

    ctx = %{
      mission_id: mission_id,
      target_id: target_id,
      qualified_item_name: qualified_item_name,
      table_name: table_name,
      key: key,
      raw_state: raw_state,
      normalized_state: normalized_state,
      value: value,
      persistence: persistence,
      stale_timeout_ms: stale_timeout_ms,
      timestamp_key: :last_update,
      timestamp: now
    }

    # Ensure table exists (might be called before GenServer starts in tests)
    if :ets.whereis(table_name) == :undefined do
      {:ok, normalized_state, false}
    else
      case :ets.lookup(table_name, key) do
        [{^key, entry}] ->
          process_state_update(Map.put(ctx, :entry, entry))

        [] ->
          # First time seeing this item - create initial entry
          create_initial_entry(ctx)
      end
    end
  end

  defp create_initial_entry(ctx) do
    # For initial entry, if it's a violation and persistence > 1,
    # start in green with pending violation
    if Evaluator.violation?(ctx.raw_state) and ctx.persistence > 1 do
      entry = build_entry(ctx, :green, ctx.raw_state, 1)
      :ets.insert(ctx.table_name, {ctx.key, entry})
      {:ok, :green, false}
    else
      # Immediate state (green or persistence=1 violation)
      entry = build_entry(ctx, ctx.normalized_state, nil, 0)
      :ets.insert(ctx.table_name, {ctx.key, entry})

      # Emit event if starting in violation state
      if Evaluator.violation?(ctx.raw_state) do
        emit_transition_event(
          ctx.mission_id,
          ctx.target_id,
          ctx.qualified_item_name,
          :green,
          ctx.normalized_state,
          ctx.value
        )
      end

      {:ok, ctx.normalized_state, Evaluator.violation?(ctx.raw_state)}
    end
  end

  defp process_state_update(%{entry: entry} = ctx) do
    cond do
      # Green state - immediately transition to green, clear pending
      not Evaluator.violation?(ctx.raw_state) ->
        handle_green_state(ctx)

      # Same violation type as pending - increment count
      entry.pending_state == ctx.raw_state ->
        handle_pending_violation(ctx)

      # Different violation type - reset and start counting new violation
      true ->
        handle_new_violation(ctx)
    end
  end

  defp handle_green_state(%{entry: entry} = ctx) do
    previous_state = entry.current_state
    transitioned? = previous_state != :green
    new_entry = update_entry(ctx, :green, nil, 0)

    :ets.insert(ctx.table_name, {ctx.key, new_entry})

    if transitioned? do
      emit_transition_event(
        ctx.mission_id,
        ctx.target_id,
        ctx.qualified_item_name,
        previous_state,
        :green,
        ctx.value
      )
    end

    {:ok, :green, transitioned?}
  end

  defp handle_pending_violation(%{entry: entry} = ctx) do
    new_count = entry.violation_count + 1

    if new_count >= ctx.persistence do
      # Persistence threshold reached - transition
      previous_state = entry.current_state
      transitioned? = previous_state != ctx.normalized_state
      new_entry = update_entry(ctx, ctx.normalized_state, nil, 0)

      :ets.insert(ctx.table_name, {ctx.key, new_entry})

      if transitioned? do
        emit_transition_event(
          ctx.mission_id,
          ctx.target_id,
          ctx.qualified_item_name,
          previous_state,
          ctx.normalized_state,
          ctx.value
        )
      end

      {:ok, ctx.normalized_state, transitioned?}
    else
      # Still accumulating violations
      new_entry = update_entry(ctx, entry.current_state, ctx.raw_state, new_count)

      :ets.insert(ctx.table_name, {ctx.key, new_entry})

      {:ok, Evaluator.normalize_state(entry.current_state), false}
    end
  end

  defp handle_new_violation(%{entry: entry} = ctx) do
    new_entry = update_entry(ctx, entry.current_state, ctx.raw_state, 1)

    :ets.insert(ctx.table_name, {ctx.key, new_entry})

    {:ok, Evaluator.normalize_state(entry.current_state), false}
  end

  defp build_entry(ctx, current_state, pending_state, violation_count) do
    %{
      current_state: current_state,
      pending_state: pending_state,
      violation_count: violation_count,
      persistence: ctx.persistence,
      stale_timeout_ms: ctx.stale_timeout_ms
    }
    |> Map.put(ctx.timestamp_key, ctx.timestamp)
  end

  defp update_entry(ctx, current_state, pending_state, violation_count) do
    Map.merge(ctx.entry, build_entry(ctx, current_state, pending_state, violation_count))
  end

  defp emit_transition_event(
         mission_id,
         target_id,
         qualified_item_name,
         previous_state,
         new_state,
         value
       ) do
    # Get active limit set for the event
    active_limit_set =
      case Cache.get_active_limit_set(mission_id, target_id) do
        {:ok, set} -> set
        _ -> "UNKNOWN"
      end

    event = %TelemetryLimitEvent{
      id: generate_event_id(),
      mission_id: mission_id,
      target_id: target_id,
      item_name: qualified_item_name,
      previous_state: previous_state,
      new_state: new_state,
      value: value,
      limit_set: active_limit_set,
      timestamp: CadenceTime.now()
    }

    # Broadcast event via EventPublisher port
    topic = "mission:#{mission_id}:events"
    EventPublisher.impl().publish(topic, {:limit_event, event})

    Logger.info(
      "Limit state transition: #{qualified_item_name} #{previous_state} -> #{new_state} " <>
        "(value=#{inspect(value)}, limit_set=#{active_limit_set})"
    )
  end

  defp table_name(mission_id) when is_binary(mission_id) do
    String.to_atom("limits_state_#{mission_id}")
  end

  defp via_tuple(mission_id) when is_binary(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :limits_state_tracker}}}
  end

  defp generate_event_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
