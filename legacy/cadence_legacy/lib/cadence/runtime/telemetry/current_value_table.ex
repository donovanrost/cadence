defmodule Cadence.Runtime.Telemetry.CurrentValueTable do
  @moduledoc """
  Current Value Table (CVT) - In-memory storage for latest telemetry values.

  The CVT stores the most recent value for each telemetry point in a mission.
  Each mission has its own isolated ETS table: `cvt_mission_<mission_id>`.

  Key design decisions:
  - Mission-scoped isolation: Each mission has its own ETS table
  - High-performance reads: ETS provides O(1) lookups
  - Concurrent access: Multiple processes can read simultaneously
  - GenServer manages table lifecycle and provides structured API

  Table structure:
    Key: {target_id, packet_name, item_name}
    Value: %{
      value: any(),
      received_time: DateTime.t(),
      packet_time: DateTime.t() | nil,
      limits_state: :red | :yellow | :green | :blue,
      metadata: map()
    }
  """

  use GenServer

  require Logger

  alias Cadence.Time, as: CadenceTime

  @type telemetry_key ::
          {target_id :: binary(), packet_name :: String.t(), item_name :: String.t()}
  @type telemetry_value :: %{
          value: any(),
          received_time: DateTime.t(),
          packet_time: DateTime.t() | nil,
          limits_state: atom(),
          metadata: map()
        }

  ## Client API

  @doc """
  Starts the CVT for a specific mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @doc """
  Inserts or updates a telemetry value in the CVT.
  """
  def set(mission_id, target_id, packet_name, item_name, value, opts \\ []) do
    alias Cadence.Telemetry.Stats

    key = {target_id, packet_name, item_name}

    telemetry_value = %{
      value: value,
      received_time: Keyword.get(opts, :received_time, CadenceTime.now()),
      packet_time: Keyword.get(opts, :packet_time),
      limits_state: Keyword.get(opts, :limits_state, :green),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    table_name = table_name(mission_id)

    # Time ETS write
    ets_start = CadenceTime.monotonic(:microsecond)
    :ets.insert(table_name, {key, telemetry_value})
    ets_duration = CadenceTime.monotonic(:microsecond) - ets_start
    Stats.record_timing(mission_id, :ets_write, ets_duration)

    # Time PubSub broadcast
    pubsub_start = CadenceTime.monotonic(:microsecond)
    broadcast_update(mission_id, target_id, packet_name, item_name, telemetry_value)
    pubsub_duration = CadenceTime.monotonic(:microsecond) - pubsub_start
    Stats.record_timing(mission_id, :pubsub_broadcast, pubsub_duration)

    :ok
  end

  @doc """
  Batch insert multiple telemetry values in a single ETS operation.

  Takes a list of items: `[{target_id, packet_name, item_name, value, limits_state}, ...]`
  Returns the list of ETS entries that were inserted.
  """
  def set_batch(mission_id, items, opts \\ []) do
    alias Cadence.Telemetry.Stats

    received_time = Keyword.get(opts, :received_time, CadenceTime.now())
    packet_time = Keyword.get(opts, :packet_time)
    table_name = table_name(mission_id)

    # Build all ETS entries at once
    ets_entries =
      Enum.map(items, fn {target_id, packet_name, item_name, value, limits_state} ->
        key = {target_id, packet_name, item_name}

        telemetry_value = %{
          value: value,
          received_time: received_time,
          packet_time: packet_time,
          limits_state: limits_state,
          metadata: %{}
        }

        {key, telemetry_value}
      end)

    # Single batched ETS insert
    # Sample timing at 1% to avoid overhead in hot path
    should_time = :rand.uniform(100) == 1

    ets_start = if should_time, do: CadenceTime.monotonic(:microsecond)
    :ets.insert(table_name, ets_entries)

    if should_time do
      ets_duration = CadenceTime.monotonic(:microsecond) - ets_start
      Stats.record_timing(mission_id, :ets_write, ets_duration)
    end

    # Return entries for broadcasting (caller decides how to broadcast)
    ets_entries
  end

  @doc """
  Broadcast a batch of updates as a single message per packet.
  """
  def broadcast_packet_update(mission_id, target_id, packet_name, items) do
    alias Cadence.Telemetry.Stats

    topic = "mission:#{mission_id}:telemetry"

    pubsub_start = CadenceTime.monotonic(:microsecond)

    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      topic,
      {:telemetry_packet_update, target_id, packet_name, items}
    )

    pubsub_duration = CadenceTime.monotonic(:microsecond) - pubsub_start
    Stats.record_timing(mission_id, :pubsub_broadcast, pubsub_duration)
  end

  @doc """
  Retrieves a telemetry value from the CVT.

  Returns `{:ok, value}` or `{:error, :not_found}`.
  """
  def get(mission_id, target_id, packet_name, item_name) do
    key = {target_id, packet_name, item_name}
    table_name = table_name(mission_id)

    case :ets.lookup(table_name, key) do
      [{^key, telemetry_value}] -> {:ok, telemetry_value}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Gets all telemetry for a specific target.
  """
  def get_target_telemetry(mission_id, target_id) do
    table_name = table_name(mission_id)

    table_name
    |> :ets.match({{target_id, :"$1", :"$2"}, :"$3"})
    |> Enum.map(fn [packet_name, item_name, value] ->
      {{target_id, packet_name, item_name}, value}
    end)
  end

  @doc """
  Gets all telemetry for a specific packet across all targets.
  """
  def get_packet_telemetry(mission_id, packet_name) do
    table_name = table_name(mission_id)

    table_name
    |> :ets.match({{:"$1", packet_name, :"$2"}, :"$3"})
    |> Enum.map(fn [target_id, item_name, value] ->
      {{target_id, packet_name, item_name}, value}
    end)
  end

  @doc """
  Clears all telemetry for a specific target.
  """
  def clear_target(mission_id, target_id) do
    table_name = table_name(mission_id)

    table_name
    |> :ets.match({{target_id, :"$1", :"$2"}, :_})
    |> Enum.each(fn [packet_name, item_name] ->
      :ets.delete(table_name, {target_id, packet_name, item_name})
    end)

    :ok
  end

  @doc """
  Returns statistics about the CVT.
  """
  def stats(mission_id) do
    table_name = table_name(mission_id)

    case :ets.info(table_name) do
      :undefined ->
        %{total_entries: 0, memory_words: 0, memory_bytes: 0}

      _info ->
        memory = :ets.info(table_name, :memory)

        %{
          total_entries: :ets.info(table_name, :size),
          memory_words: memory,
          memory_bytes: memory * :erlang.system_info(:wordsize)
        }
    end
  end

  ## Server Callbacks

  @impl true
  def init(mission_id) do
    table_name = table_name(mission_id)

    Logger.debug("Starting CurrentValueTable for mission_id=#{mission_id}")

    Logger.info("Creating CVT table: #{table_name} for mission_id=#{mission_id}")

    # Create ETS table with options:
    # - :set - one value per key
    # - :named_table - can be accessed by name
    # - :public - any process can read/write
    # - read_concurrency: true - optimize for concurrent reads
    # - write_concurrency: true - optimize for concurrent writes
    _table =
      :ets.new(table_name, [
        :set,
        :named_table,
        :public,
        read_concurrency: true,
        write_concurrency: true,
        decentralized_counters: true
      ])

    {:ok, %{mission_id: mission_id, table_name: table_name}}
  end

  @impl true
  def handle_call({:get_stats}, _from, state) do
    stats = %{
      total_entries: :ets.info(state.table_name, :size),
      memory_words: :ets.info(state.table_name, :memory)
    }

    {:reply, stats, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.debug("Stopping CurrentValueTable for mission_id=#{state.mission_id}")
    Logger.info("Terminating CVT table: #{state.table_name}")
    :ets.delete(state.table_name)
    :ok
  end

  ## Private Functions

  defp table_name(mission_id) when is_binary(mission_id) do
    String.to_atom("cvt_mission_#{mission_id}")
  end

  defp via_tuple(mission_id) when is_binary(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :cvt}}}
  end

  defp broadcast_update(mission_id, target_id, packet_name, item_name, telemetry_value) do
    topic = "mission:#{mission_id}:telemetry"

    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      topic,
      {:telemetry_update, target_id, packet_name, item_name, telemetry_value}
    )
  end
end
