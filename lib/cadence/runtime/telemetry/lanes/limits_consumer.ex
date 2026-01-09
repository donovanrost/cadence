defmodule Cadence.Runtime.Telemetry.Lanes.LimitsConsumer do
  @moduledoc """
  Consumes persisted telemetry from the sink and evaluates limits out-of-band.
  """

  use GenServer
  require Logger

  alias Cadence.Runtime.Telemetry.CurrentValueTable
  alias Cadence.Runtime.Telemetry.Limits.StateTracker

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    lane = Keyword.get(opts, :lane, :payload)

    name =
      {:via, Registry, {Cadence.MissionRegistry, {:lanes, mission_id, {:limits_consumer, lane}}}}

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    shard_count = Keyword.fetch!(opts, :shard_count)
    source = Keyword.get(opts, :source, Cadence.Telemetry.LogSource.File)
    lane = Keyword.get(opts, :lane, :payload)
    base_dir = Keyword.get(opts, :base_dir)

    Logger.info(
      "Starting limits consumer for mission_id=#{mission_id}, lane=#{lane}, shards=#{shard_count}"
    )

    subs =
      for shard <- 0..(shard_count - 1), into: %{} do
        case source.subscribe(shard,
               group: {:limits, mission_id},
               mission_id: mission_id,
               lane: lane,
               base_dir: base_dir
             ) do
          {:ok, pid, meta} ->
            {{shard, pid}, meta}

          {:error, reason} ->
            Logger.error(
              "Failed to subscribe limits consumer to shard #{shard}: #{inspect(reason)}"
            )

            {{shard, nil}, %{error: reason}}
        end
      end

    {:ok,
     %{
       mission_id: mission_id,
       shard_count: shard_count,
       source: source,
       subs: subs,
       base_dir: base_dir
     }}
  end

  @impl true
  def handle_info({:log_batch, shard_id, records, meta}, state) do
    records
    |> build_items(state.mission_id)
    |> persist_and_broadcast(state)

    maybe_ack(state, shard_id, meta[:end_offset])

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp build_items(records, mission_id) do
    Enum.flat_map(records, &build_record_items(&1, mission_id))
  end

  defp build_record_items(record, mission_id) do
    packet_name = record.meta[:packet_def] || "unknown"

    items =
      StateTracker.evaluate_batch(mission_id, record.target_id, Enum.to_list(record.payload))

    Enum.map(items, fn {item_name, value, limit_state} ->
      {record.target_id, packet_name, item_name, value, limit_state}
    end)
  end

  defp persist_and_broadcast([], _state), do: :ok

  defp persist_and_broadcast(items, state) do
    ets_entries = CurrentValueTable.set_batch(state.mission_id, items, [])
    broadcast_updates(state.mission_id, ets_entries)
  end

  defp maybe_ack(_state, _shard_id, nil), do: :ok

  defp maybe_ack(state, shard_id, end_offset) do
    state.source.ack(shard_id, end_offset,
      group: {:limits, state.mission_id},
      base_dir: state.base_dir
    )
  end

  defp broadcast_updates(mission_id, ets_entries) do
    ets_entries
    |> Enum.map(fn {{target_id, packet_name, item_name}, telemetry_value} ->
      {target_id, packet_name, item_name, telemetry_value}
    end)
    |> Enum.group_by(fn {target_id, packet_name, _item_name, _value} ->
      {target_id, packet_name}
    end)
    |> Enum.each(fn {{target_id, packet_name}, items} ->
      formatted =
        Enum.map(items, fn {_t, _p, item_name, telemetry_value} ->
          {item_name, telemetry_value}
        end)

      CurrentValueTable.broadcast_packet_update(mission_id, target_id, packet_name, formatted)
    end)
  end
end
