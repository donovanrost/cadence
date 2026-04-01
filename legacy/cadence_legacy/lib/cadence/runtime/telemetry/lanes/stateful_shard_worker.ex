defmodule Cadence.Runtime.Telemetry.Lanes.StatefulShardWorker do
  @moduledoc """
  Stateful lane worker that computes stateful derived telemetry and limits.
  """

  use GenServer

  require Logger

  alias Cadence.Runtime.Telemetry.CurrentValueTable
  alias Cadence.Runtime.Telemetry.Limits.StateTracker
  alias Cadence.Telemetry.{DerivedItems, LogEnvelope}

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    lane = Keyword.fetch!(opts, :lane)
    shard_id = Keyword.fetch!(opts, :shard_id)
    sink = Keyword.get(opts, :sink, Cadence.Telemetry.LogSink.Noop)
    sink_opts = Keyword.get(opts, :sink_opts, [])
    config_version = Keyword.get(opts, :config_version, 0)

    Logger.debug(
      "Starting Lanes.StatefulShardWorker for mission_id=#{mission_id} lane=#{lane} shard_id=#{shard_id}"
    )

    {:ok,
     %{
       mission_id: mission_id,
       lane: lane,
       shard_id: shard_id,
       sink: sink,
       sink_opts: sink_opts,
       config_version: config_version
     }}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "Stopping Lanes.StatefulShardWorker for mission_id=#{state.mission_id} lane=#{state.lane} shard_id=#{state.shard_id} reason=#{inspect(reason)}"
    )

    :ok
  end

  @impl true
  def handle_cast({:stateful_records, records}, state) do
    items = build_items(records, state.mission_id)
    persist_and_broadcast(items, state)
    append_records(records, items, state)

    {:noreply, state}
  end

  @impl true
  def handle_info({:config_version, version}, state) when is_integer(version) do
    {:noreply, %{state | config_version: version}}
  end

  defp build_items(records, mission_id) do
    Enum.flat_map(records, &build_record_items(&1, mission_id))
  end

  defp build_record_items(record, mission_id) do
    packet_name = record.meta[:packet_def] || "unknown"

    case DerivedItems.compute_stateful(record.payload, mission_id) do
      {:ok, derived_items} when map_size(derived_items) > 0 ->
        items_with_limits =
          StateTracker.evaluate_batch(mission_id, record.target_id, Enum.to_list(derived_items))

        Enum.map(items_with_limits, fn {item_name, value, limit_state} ->
          {record.target_id, packet_name, item_name, value, limit_state}
        end)

      _ ->
        []
    end
  end

  defp persist_and_broadcast([], _state), do: :ok

  defp persist_and_broadcast(items, state) do
    ets_entries = CurrentValueTable.set_batch(state.mission_id, items, [])
    broadcast_updates(state.mission_id, ets_entries)
  end

  defp append_records(_records, [], _state), do: :ok

  defp append_records(records, items, state) do
    envelopes = build_stateful_envelopes(records, items, state)
    maybe_append_envelopes(state, envelopes)
  end

  defp build_stateful_envelopes(records, items, state) do
    items
    |> Enum.group_by(fn {target_id, packet_name, _item_name, _value, _state} ->
      {target_id, packet_name}
    end)
    |> Enum.flat_map(fn {{target_id, packet_name}, grouped} ->
      build_stateful_envelope(records, state, target_id, packet_name, grouped)
    end)
  end

  defp build_stateful_envelope(records, state, target_id, packet_name, grouped) do
    case find_base_record(records, target_id, packet_name) do
      nil ->
        []

      base ->
        payload = build_stateful_payload(grouped)
        [to_stateful_envelope(base, state, target_id, payload)]
    end
  end

  defp find_base_record(records, target_id, packet_name) do
    Enum.find(records, fn record ->
      record.target_id == target_id and (record.meta[:packet_def] || "unknown") == packet_name
    end)
  end

  defp build_stateful_payload(grouped) do
    Enum.reduce(grouped, %{}, fn {_t, _p, item_name, value, _}, acc ->
      Map.put(acc, item_name, value)
    end)
  end

  defp to_stateful_envelope(base, state, target_id, payload) do
    %LogEnvelope{
      mission_id: state.mission_id,
      target_id: target_id,
      apid: base.apid,
      lane: state.lane,
      shard_id: state.shard_id,
      router_version: base.router_version,
      config_version: state.config_version,
      sequence: base.sequence,
      ingest_monotonic_ns: base.ingest_monotonic_ns,
      source_wall_clock_ms: base.source_wall_clock_ms,
      checksum: base.checksum,
      payload: payload,
      meta:
        Map.merge(base.meta || %{}, %{
          stateful: true,
          source_lane: base.lane
        })
    }
  end

  defp maybe_append_envelopes(_state, []), do: :ok

  defp maybe_append_envelopes(state, envelopes) do
    _ = state.sink.append(state.shard_id, envelopes, state.sink_opts)
    :ok
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
