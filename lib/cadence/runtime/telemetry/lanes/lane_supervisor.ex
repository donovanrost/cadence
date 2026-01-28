defmodule Cadence.Runtime.Telemetry.Lanes.LaneSupervisor do
  @moduledoc """
  Supervisor for shard workers within a lane.
  """

  use Supervisor

  require Logger

  alias Cadence.Runtime.Telemetry.Lanes.ShardWorker

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    lane = Keyword.fetch!(opts, :lane)
    name = {:via, Registry, {Cadence.MissionRegistry, {:lanes, mission_id, {:lane, lane}}}}
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    lane = Keyword.fetch!(opts, :lane)

    Logger.debug("Starting Lanes.LaneSupervisor for mission_id=#{mission_id} lane=#{lane}")

    Process.put(:mission_id, mission_id)
    Process.put(:lane, lane)

    shard_count = Keyword.fetch!(opts, :shard_count)
    router = Keyword.fetch!(opts, :router)
    sink = Keyword.get(opts, :sink, Cadence.Telemetry.LogSink.Noop)
    sink_opts = Keyword.get(opts, :sink_opts, [])
    config_version = Keyword.get(opts, :config_version, 0)
    router_version = Keyword.get(opts, :router_version, 1)
    max_batch_size = Keyword.get(opts, :max_batch_size, 200)
    max_batch_delay_ms = Keyword.get(opts, :max_batch_delay_ms, 50)
    max_inflight = Keyword.get(opts, :max_inflight, 5_000)

    children =
      for shard <- 0..(shard_count - 1) do
        %{
          id: {:shard_worker, shard},
          start:
            {ShardWorker, :start_link,
             [
               [
                 mission_id: mission_id,
                 lane: lane,
                 shard_id: shard,
                 router: router,
                 sink: sink,
                 sink_opts: sink_opts,
                 config_version: config_version,
                 router_version: router_version,
                 max_batch_size: max_batch_size,
                 max_batch_delay_ms: max_batch_delay_ms,
                 max_inflight: max_inflight,
                 name: shard_name(mission_id, lane, shard)
               ]
             ]}
        }
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  def terminate(reason, _state) do
    mission_id = Process.get(:mission_id)
    lane = Process.get(:lane)

    if mission_id && lane do
      Logger.debug(
        "Stopping Lanes.LaneSupervisor for mission_id=#{mission_id} lane=#{lane} reason=#{inspect(reason)}"
      )
    end

    :ok
  end

  defp shard_name(mission_id, lane, shard) do
    {:via, Registry, {Cadence.MissionRegistry, {:lanes, mission_id, {:shard, lane, shard}}}}
  end
end
