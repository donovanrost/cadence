defmodule Cadence.Runtime.Telemetry.Lanes.CVTConsumer do
  @moduledoc """
  Consumes persisted telemetry from the sink and updates the CVT + PubSub.
  """

  use GenServer
  require Logger

  alias Cadence.Runtime.Telemetry.CurrentValueTable

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    lane = Keyword.get(opts, :lane, :payload)

    name =
      {:via, Registry, {Cadence.MissionRegistry, {:lanes, mission_id, {:cvt_consumer, lane}}}}

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
      "Starting CVT consumer for mission_id=#{mission_id}, lane=#{lane}, shards=#{shard_count}"
    )

    subs =
      for shard <- 0..(shard_count - 1), into: %{} do
        case source.subscribe(shard,
               group: {:cvt, mission_id},
               mission_id: mission_id,
               lane: lane,
               base_dir: base_dir
             ) do
          {:ok, pid, meta} ->
            {{shard, pid}, meta}

          {:error, reason} ->
            Logger.error("Failed to subscribe CVT consumer to shard #{shard}: #{inspect(reason)}")
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
    |> build_items()
    |> persist_and_broadcast(state)

    maybe_ack(state, shard_id, meta[:end_offset])

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp build_items(records) do
    Enum.flat_map(records, &build_record_items/1)
  end

  defp build_record_items(record) do
    packet_name = record.meta[:packet_def] || "unknown"

    case record.meta[:items_with_limits] do
      list when is_list(list) ->
        Enum.map(list, fn {item_name, value, limit_state} ->
          {record.target_id, packet_name, item_name, value, limit_state}
        end)

      _ ->
        Enum.map(record.payload, fn {item_name, value} ->
          {record.target_id, packet_name, item_name, value, :green}
        end)
    end
  end

  defp persist_and_broadcast([], _state), do: :ok

  defp persist_and_broadcast(items, state) do
    ets_entries = CurrentValueTable.set_batch(state.mission_id, items, [])
    broadcast_updates(state.mission_id, ets_entries)
  end

  defp maybe_ack(_state, _shard_id, nil), do: :ok

  defp maybe_ack(state, shard_id, end_offset) do
    state.source.ack(shard_id, end_offset,
      group: {:cvt, state.mission_id},
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
