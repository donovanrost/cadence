defmodule Cadence.Runtime.Telemetry.Lanes.StatefulSupervisor do
  @moduledoc """
  Supervisor for the stateful telemetry lane.
  """

  use Supervisor

  alias Cadence.Runtime.Telemetry.Lanes.{StatefulRouter, StatefulShardWorker}

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    lane = Keyword.get(opts, :lane, :stateful)

    name =
      {:via, Registry, {Cadence.MissionRegistry, {:lanes, mission_id, {:stateful, lane}}}}

    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    lane = Keyword.get(opts, :lane, :stateful)
    shard_count = Keyword.fetch!(opts, :shard_count)
    source_shard_count = Keyword.fetch!(opts, :source_shard_count)
    sink = Keyword.get(opts, :sink, Cadence.Telemetry.LogSink.Noop)
    sink_opts = Keyword.get(opts, :sink_opts, [])
    config_version = Keyword.get(opts, :config_version, 0)
    source = Keyword.get(opts, :source, Cadence.Telemetry.LogSource.File)
    source_lane = Keyword.get(opts, :source_lane, :payload)
    base_dir = Keyword.get(opts, :base_dir)

    router_name =
      {:via, Registry, {Cadence.MissionRegistry, {:lanes, mission_id, {:stateful_router, lane}}}}

    workers =
      for shard <- 0..(shard_count - 1) do
        %{
          id: {:stateful_shard_worker, shard},
          start:
            {StatefulShardWorker, :start_link,
             [
               [
                 mission_id: mission_id,
                 lane: lane,
                 shard_id: shard,
                 sink: sink,
                 sink_opts: sink_opts,
                 config_version: config_version,
                 name: worker_name(mission_id, lane, shard)
               ]
             ]}
        }
      end

    children =
      [
        {StatefulRouter,
         [
           mission_id: mission_id,
           lane: lane,
           shard_count: shard_count,
           source_shard_count: source_shard_count,
           source: source,
           source_lane: source_lane,
           base_dir: base_dir,
           name: router_name
         ]}
      ] ++ workers

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp worker_name(mission_id, lane, shard_id) do
    {:via, Registry,
     {Cadence.MissionRegistry, {:lanes, mission_id, {:stateful_shard, lane, shard_id}}}}
  end
end
