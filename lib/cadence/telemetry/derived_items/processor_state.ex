defmodule Cadence.Telemetry.DerivedItems.ProcessorState do
  @moduledoc """
  ETS-based state storage for stateful derived item functions.

  Stateful functions like `rolling_avg`, `rate`, and `delta` need to maintain
  state across packet evaluations. This module provides efficient ETS-based
  storage for that state.

  ## State Structure

  - Table: `:processor_state`
  - Key: `{mission_id, item_name, function_key}`
  - Value: Function-specific state (varies by function type)

  ## State Lifecycle

  State is:
  - Created on first evaluation of a stateful function
  - Updated on each subsequent evaluation with new input data
  - Cleared when a mission is stopped or explicitly reset

  ## Crash Recovery

  State survives process crashes since it lives in ETS. On restart, processors
  simply read their last state from ETS and continue. At most, the in-flight
  packet's contribution is lost.

  ## Partition Safety

  Different partitions may evaluate the same derived item, but stateful functions
  are only updated when their source items have new data. ETS provides safe
  concurrent access across partitions.

  ## Example

      # State key for rolling_avg(HEALTH.TEMP1, 10) in derived item TEMP_SMOOTH
      state_key = {"TEMP_SMOOTH", {:rolling_avg, hash_of_args}}

      # Get state (returns nil if not found)
      state = ProcessorState.get(mission_id, state_key)

      # Update state after computation
      ProcessorState.put(mission_id, state_key, %{buffer: [...], last_avg: 25.5})
  """

  use GenServer
  require Logger

  @table :processor_state

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the processor state server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets state for a specific processor function instance.

  ## Parameters

  - `mission_id` - The mission ID
  - `state_key` - Tuple of `{item_name, {function_name, args_hash}}`

  ## Returns

  - The stored state map, or `nil` if not found
  """
  @spec get(String.t(), {String.t(), tuple()}) :: map() | nil
  def get(mission_id, state_key) do
    case :ets.lookup(@table, {mission_id, state_key}) do
      [{_, state}] -> state
      [] -> nil
    end
  end

  @doc """
  Stores state for a specific processor function instance.

  ## Parameters

  - `mission_id` - The mission ID
  - `state_key` - Tuple of `{item_name, {function_name, args_hash}}`
  - `state` - The state map to store
  """
  @spec put(String.t(), {String.t(), tuple()}, map()) :: true
  def put(mission_id, state_key, state) do
    :ets.insert(@table, {{mission_id, state_key}, state})
  end

  @doc """
  Clears all processor state for a mission.

  Call this when a mission is stopped or when state needs to be reset.
  """
  @spec clear_mission(String.t()) :: :ok
  def clear_mission(mission_id) do
    # Match and delete all entries for this mission
    :ets.match_delete(@table, {{mission_id, :_}, :_})
    Logger.debug("Cleared processor state for mission #{mission_id}")
    :ok
  end

  @doc """
  Clears state for a specific derived item within a mission.

  Useful when a derived item's expression is modified.
  """
  @spec clear_item(String.t(), String.t()) :: :ok
  def clear_item(mission_id, item_name) do
    # Match and delete all entries for this item
    :ets.match_delete(@table, {{mission_id, {item_name, :_}}, :_})
    Logger.debug("Cleared processor state for item #{item_name} in mission #{mission_id}")
    :ok
  end

  @doc """
  Returns statistics about the processor state table.
  """
  @spec stats() :: map()
  def stats do
    case :ets.whereis(@table) do
      :undefined ->
        %{size: 0, memory_bytes: 0, running: false}

      _tid ->
        info = :ets.info(@table)

        %{
          size: Keyword.get(info, :size, 0),
          memory_bytes: Keyword.get(info, :memory, 0) * :erlang.system_info(:wordsize),
          running: true
        }
    end
  end

  @doc """
  Checks if the processor state table is available.

  Returns `true` if the ETS table exists and is accessible.
  """
  @spec available?() :: boolean()
  def available? do
    :ets.whereis(@table) != :undefined
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init(_opts) do
    # Create ETS table owned by this process
    table =
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    Logger.info("Processor state storage started (table: #{inspect(table)})")

    {:ok, %{table: table}}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    Logger.info("Processor state storage stopping")
    :ok
  end
end
