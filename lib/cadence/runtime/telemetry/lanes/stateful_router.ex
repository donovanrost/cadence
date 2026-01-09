defmodule Cadence.Runtime.Telemetry.Lanes.StatefulRouter do
  @moduledoc """
  Router that consumes persisted telemetry and repartitions it by sticky key.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    lane = Keyword.get(opts, :lane, :stateful)

    name =
      Keyword.get(opts, :name) ||
        {:via, Registry,
         {Cadence.MissionRegistry, {:lanes, mission_id, {:stateful_router, lane}}}}

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    shard_count = Keyword.fetch!(opts, :shard_count)
    source_shard_count = Keyword.fetch!(opts, :source_shard_count)
    source = Keyword.get(opts, :source, Cadence.Telemetry.LogSource.File)
    source_lane = Keyword.get(opts, :source_lane, :payload)
    lane = Keyword.get(opts, :lane, :stateful)
    base_dir = Keyword.get(opts, :base_dir)

    Logger.info(
      "Starting stateful lane router for mission_id=#{mission_id}, lane=#{lane}, shards=#{shard_count}"
    )

    subs =
      for shard <- 0..(source_shard_count - 1), into: %{} do
        case source.subscribe(shard,
               group: {:stateful_lane, mission_id, lane},
               mission_id: mission_id,
               lane: source_lane,
               base_dir: base_dir
             ) do
          {:ok, pid, meta} ->
            {{shard, pid}, meta}

          {:error, reason} ->
            Logger.error(
              "Failed to subscribe stateful lane router to shard #{shard}: #{inspect(reason)}"
            )

            {{shard, nil}, %{error: reason}}
        end
      end

    {:ok,
     %{
       mission_id: mission_id,
       shard_count: shard_count,
       source_shard_count: source_shard_count,
       source: source,
       source_lane: source_lane,
       lane: lane,
       subs: subs,
       base_dir: base_dir
     }}
  end

  @impl true
  def handle_info({:log_batch, source_shard, records, meta}, state) do
    records
    |> repartition(state.shard_count)
    |> Enum.each(fn {shard_id, shard_records} ->
      GenServer.cast(stateful_worker_name(state.mission_id, state.lane, shard_id), {
        :stateful_records,
        shard_records
      })
    end)

    maybe_ack(state, source_shard, meta[:end_offset])

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp repartition(records, shard_count) do
    Enum.group_by(records, fn record ->
      sticky_key = {record.target_id, record.apid}
      :erlang.phash2(sticky_key, shard_count)
    end)
  end

  defp maybe_ack(_state, _source_shard, nil), do: :ok

  defp maybe_ack(state, source_shard, end_offset) do
    state.source.ack(source_shard, end_offset,
      group: {:stateful_lane, state.mission_id, state.lane},
      base_dir: state.base_dir
    )
  end

  defp stateful_worker_name(mission_id, lane, shard_id) do
    {:via, Registry,
     {Cadence.MissionRegistry, {:lanes, mission_id, {:stateful_shard, lane, shard_id}}}}
  end
end
