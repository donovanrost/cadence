defmodule Cadence.Telemetry.Limits.StateTracker do
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

  alias Cadence.Telemetry.Limits.{Evaluator, Cache}
  alias Cadence.Telemetry.Events.TelemetryLimitEvent

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
    now = System.monotonic_time(:millisecond)

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
        raw_state = Evaluator.evaluate(value, limits)

        if table_exists? do
          case update_state_batch(
                 mission_id,
                 target_id,
                 item_name,
                 raw_state,
                 value,
                 persistence,
                 stale_timeout_ms,
                 table_name,
                 now
               ) do
            {:ok, state, _transition?} -> state
            _ -> Evaluator.normalize_state(raw_state)
          end
        else
          Evaluator.normalize_state(raw_state)
        end

      :not_configured ->
        :green

      {:error, _reason} ->
        :green
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
  defp update_state_batch(
         mission_id,
         target_id,
         qualified_item_name,
         raw_state,
         value,
         persistence,
         stale_timeout_ms,
         table_name,
         now_mono
       ) do
    key = {target_id, qualified_item_name}
    normalized_state = Evaluator.normalize_state(raw_state)

    case :ets.lookup(table_name, key) do
      [{^key, entry}] ->
        process_state_update_batch(
          mission_id,
          target_id,
          qualified_item_name,
          table_name,
          key,
          entry,
          raw_state,
          normalized_state,
          value,
          persistence,
          stale_timeout_ms,
          now_mono
        )

      [] ->
        create_initial_entry_batch(
          mission_id,
          target_id,
          qualified_item_name,
          table_name,
          key,
          raw_state,
          normalized_state,
          value,
          persistence,
          stale_timeout_ms,
          now_mono
        )
    end
  end

  defp create_initial_entry_batch(
         mission_id,
         target_id,
         qualified_item_name,
         table_name,
         key,
         raw_state,
         normalized_state,
         value,
         persistence,
         stale_timeout_ms,
         now_mono
       ) do
    if Evaluator.violation?(raw_state) and persistence > 1 do
      entry = %{
        current_state: :green,
        pending_state: raw_state,
        violation_count: 1,
        last_update_mono: now_mono,
        persistence: persistence,
        stale_timeout_ms: stale_timeout_ms
      }

      :ets.insert(table_name, {key, entry})
      {:ok, :green, false}
    else
      entry = %{
        current_state: normalized_state,
        pending_state: nil,
        violation_count: 0,
        last_update_mono: now_mono,
        persistence: persistence,
        stale_timeout_ms: stale_timeout_ms
      }

      :ets.insert(table_name, {key, entry})

      if Evaluator.violation?(raw_state) do
        emit_transition_event(
          mission_id,
          target_id,
          qualified_item_name,
          :green,
          normalized_state,
          value
        )
      end

      {:ok, normalized_state, Evaluator.violation?(raw_state)}
    end
  end

  defp process_state_update_batch(
         mission_id,
         target_id,
         qualified_item_name,
         table_name,
         key,
         entry,
         raw_state,
         normalized_state,
         value,
         persistence,
         stale_timeout_ms,
         now_mono
       ) do
    cond do
      not Evaluator.violation?(raw_state) ->
        previous_state = entry.current_state
        transitioned? = previous_state != :green

        new_entry = %{
          entry
          | current_state: :green,
            pending_state: nil,
            violation_count: 0,
            last_update_mono: now_mono,
            persistence: persistence,
            stale_timeout_ms: stale_timeout_ms
        }

        :ets.insert(table_name, {key, new_entry})

        if transitioned? do
          emit_transition_event(
            mission_id,
            target_id,
            qualified_item_name,
            previous_state,
            :green,
            value
          )
        end

        {:ok, :green, transitioned?}

      entry.pending_state == raw_state ->
        new_count = entry.violation_count + 1

        if new_count >= persistence do
          previous_state = entry.current_state
          transitioned? = previous_state != normalized_state

          new_entry = %{
            entry
            | current_state: normalized_state,
              pending_state: nil,
              violation_count: 0,
              last_update_mono: now_mono,
              persistence: persistence,
              stale_timeout_ms: stale_timeout_ms
          }

          :ets.insert(table_name, {key, new_entry})

          if transitioned? do
            emit_transition_event(
              mission_id,
              target_id,
              qualified_item_name,
              previous_state,
              normalized_state,
              value
            )
          end

          {:ok, normalized_state, transitioned?}
        else
          new_entry = %{
            entry
            | pending_state: raw_state,
              violation_count: new_count,
              last_update_mono: now_mono,
              persistence: persistence,
              stale_timeout_ms: stale_timeout_ms
          }

          :ets.insert(table_name, {key, new_entry})
          {:ok, Evaluator.normalize_state(entry.current_state), false}
        end

      true ->
        new_entry = %{
          entry
          | pending_state: raw_state,
            violation_count: 1,
            last_update_mono: now_mono,
            persistence: persistence,
            stale_timeout_ms: stale_timeout_ms
        }

        :ets.insert(table_name, {key, new_entry})
        {:ok, Evaluator.normalize_state(entry.current_state), false}
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
    now_mono = System.monotonic_time(:millisecond)

    if :ets.whereis(table_name) != :undefined do
      :ets.foldl(
        fn {{target_id, item_name}, entry}, acc ->
          # Support both old (last_update DateTime) and new (last_update_mono) formats
          time_since_update =
            case Map.get(entry, :last_update_mono) do
              nil ->
                # Legacy: use DateTime field
                case Map.get(entry, :last_update) do
                  nil -> 0
                  dt -> DateTime.diff(DateTime.utc_now(), dt, :millisecond)
                end

              mono ->
                now_mono - mono
            end

          if time_since_update >= entry.stale_timeout_ms and entry.current_state != :blue do
            [{target_id, item_name, entry} | acc]
          else
            acc
          end
        end,
        [],
        table_name
      )
    else
      []
    end
  end

  @doc """
  Marks an item as stale (blue state).

  Called by StalenessMonitor when item hasn't been updated within timeout.
  """
  @spec mark_stale(String.t(), String.t(), String.t()) :: {:ok, boolean()}
  def mark_stale(mission_id, target_id, qualified_item_name) do
    table_name = table_name(mission_id)

    if :ets.whereis(table_name) != :undefined do
      case :ets.lookup(table_name, {target_id, qualified_item_name}) do
        [{key, entry}] ->
          if entry.current_state != :blue do
            # Emit transition event
            emit_transition_event(
              mission_id,
              target_id,
              qualified_item_name,
              entry.current_state,
              :blue,
              nil
            )

            # Update state
            new_entry = %{entry | current_state: :blue}
            :ets.insert(table_name, {key, new_entry})
            {:ok, true}
          else
            {:ok, false}
          end

        [] ->
          {:ok, false}
      end
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
    now = DateTime.utc_now()
    normalized_state = Evaluator.normalize_state(raw_state)

    # Ensure table exists (might be called before GenServer starts in tests)
    unless :ets.whereis(table_name) != :undefined do
      {:ok, normalized_state, false}
    else
      case :ets.lookup(table_name, key) do
        [{^key, entry}] ->
          process_state_update(
            mission_id,
            target_id,
            qualified_item_name,
            table_name,
            key,
            entry,
            raw_state,
            normalized_state,
            value,
            persistence,
            stale_timeout_ms,
            now
          )

        [] ->
          # First time seeing this item - create initial entry
          create_initial_entry(
            mission_id,
            target_id,
            qualified_item_name,
            table_name,
            key,
            raw_state,
            normalized_state,
            value,
            persistence,
            stale_timeout_ms,
            now
          )
      end
    end
  end

  defp create_initial_entry(
         mission_id,
         target_id,
         qualified_item_name,
         table_name,
         key,
         raw_state,
         normalized_state,
         value,
         persistence,
         stale_timeout_ms,
         now
       ) do
    # For initial entry, if it's a violation and persistence > 1,
    # start in green with pending violation
    if Evaluator.violation?(raw_state) and persistence > 1 do
      entry = %{
        current_state: :green,
        pending_state: raw_state,
        violation_count: 1,
        last_update: now,
        persistence: persistence,
        stale_timeout_ms: stale_timeout_ms
      }

      :ets.insert(table_name, {key, entry})
      {:ok, :green, false}
    else
      # Immediate state (green or persistence=1 violation)
      entry = %{
        current_state: normalized_state,
        pending_state: nil,
        violation_count: 0,
        last_update: now,
        persistence: persistence,
        stale_timeout_ms: stale_timeout_ms
      }

      :ets.insert(table_name, {key, entry})

      # Emit event if starting in violation state
      if Evaluator.violation?(raw_state) do
        emit_transition_event(
          mission_id,
          target_id,
          qualified_item_name,
          :green,
          normalized_state,
          value
        )
      end

      {:ok, normalized_state, Evaluator.violation?(raw_state)}
    end
  end

  defp process_state_update(
         mission_id,
         target_id,
         qualified_item_name,
         table_name,
         key,
         entry,
         raw_state,
         normalized_state,
         value,
         persistence,
         stale_timeout_ms,
         now
       ) do
    cond do
      # Green state - immediately transition to green, clear pending
      not Evaluator.violation?(raw_state) ->
        previous_state = entry.current_state
        transitioned? = previous_state != :green

        new_entry = %{
          entry
          | current_state: :green,
            pending_state: nil,
            violation_count: 0,
            last_update: now,
            persistence: persistence,
            stale_timeout_ms: stale_timeout_ms
        }

        :ets.insert(table_name, {key, new_entry})

        if transitioned? do
          emit_transition_event(
            mission_id,
            target_id,
            qualified_item_name,
            previous_state,
            :green,
            value
          )
        end

        {:ok, :green, transitioned?}

      # Same violation type as pending - increment count
      entry.pending_state == raw_state ->
        new_count = entry.violation_count + 1

        if new_count >= persistence do
          # Persistence threshold reached - transition
          previous_state = entry.current_state
          transitioned? = previous_state != normalized_state

          new_entry = %{
            entry
            | current_state: normalized_state,
              pending_state: nil,
              violation_count: 0,
              last_update: now,
              persistence: persistence,
              stale_timeout_ms: stale_timeout_ms
          }

          :ets.insert(table_name, {key, new_entry})

          if transitioned? do
            emit_transition_event(
              mission_id,
              target_id,
              qualified_item_name,
              previous_state,
              normalized_state,
              value
            )
          end

          {:ok, normalized_state, transitioned?}
        else
          # Still accumulating violations
          new_entry = %{
            entry
            | pending_state: raw_state,
              violation_count: new_count,
              last_update: now,
              persistence: persistence,
              stale_timeout_ms: stale_timeout_ms
          }

          :ets.insert(table_name, {key, new_entry})

          # Return current state (not yet transitioned)
          {:ok, Evaluator.normalize_state(entry.current_state), false}
        end

      # Different violation type - reset and start counting new violation
      true ->
        new_entry = %{
          entry
          | pending_state: raw_state,
            violation_count: 1,
            last_update: now,
            persistence: persistence,
            stale_timeout_ms: stale_timeout_ms
        }

        :ets.insert(table_name, {key, new_entry})

        # Return current state (not yet transitioned)
        {:ok, Evaluator.normalize_state(entry.current_state), false}
    end
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
      timestamp: DateTime.utc_now()
    }

    # Broadcast event via PubSub
    topic = "mission:#{mission_id}:events"

    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      topic,
      {:limit_event, event}
    )

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
