defmodule Cadence.Runtime.Telemetry.Lanes.Supervisor do
  @moduledoc """
  Mission-scoped supervisor for the lanes/shards telemetry pipeline.
  """

  use Supervisor

  require Logger

  alias Cadence.Runtime.Telemetry.Lanes.{
    Autoscaler,
    LaneConfig,
    LaneSupervisor,
    Router,
    StatefulSupervisor
  }

  @default_shard_count 8

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    name = {:via, Registry, {Cadence.MissionRegistry, {:lanes, mission_id, :supervisor}}}
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)

    Logger.debug("Starting Lanes.Supervisor for mission_id=#{mission_id}")
    Process.put(:mission_id, mission_id)

    shard_count = Keyword.get(opts, :shard_count, @default_shard_count)
    lanes = LaneConfig.from_opts(Keyword.put_new(opts, :shard_count, shard_count))
    consumer_lanes = Keyword.get(opts, :consumer_lanes, [:payload])
    sink = Keyword.get(opts, :sink, Cadence.Telemetry.LogSink.File)

    sink_opts =
      opts
      |> Keyword.get(:sink_opts, [])
      |> Keyword.put_new(:segment_bytes, 64_000_000)
      |> Keyword.put_new(:max_segments, 16)
      |> Keyword.put_new(:max_total_bytes, 1_000_000_000)

    source = Keyword.get(opts, :source, Cadence.Telemetry.LogSource.File)
    base_dir = Keyword.get(sink_opts, :base_dir)
    router_version = Keyword.get(opts, :router_version, 1)
    config_version = Keyword.get(opts, :config_version, 0)
    max_batch_size = Keyword.get(opts, :max_batch_size, 200)
    max_batch_delay_ms = Keyword.get(opts, :max_batch_delay_ms, 50)
    max_inflight = Keyword.get(opts, :max_inflight, 5_000)
    max_queue_depth = Keyword.get(opts, :max_queue_depth, 100_000)
    stateful_lane = Keyword.get(opts, :stateful_lane, :stateful)
    stateful_source_lane = Keyword.get(opts, :stateful_source_lane, :payload)
    stateful_shard_count = Keyword.get(opts, :stateful_shard_count, shard_count)
    stateful_source_shard_count = lane_shard_count(lanes, stateful_source_lane)

    router_name = {:via, Registry, {Cadence.MissionRegistry, {:lanes, mission_id, :router}}}

    lane_children =
      Enum.map(lanes, fn lane ->
        {LaneSupervisor,
         [
           mission_id: mission_id,
           lane: lane.name,
           shard_count: lane.shard_count,
           router: router_name,
           sink: sink,
           sink_opts: sink_opts,
           config_version: config_version,
           router_version: router_version,
           max_batch_size: max_batch_size,
           max_batch_delay_ms: max_batch_delay_ms,
           max_inflight: max_inflight
         ]}
      end)

    consumer_children =
      consumer_lanes
      |> Enum.filter(&Enum.any?(lanes, fn lane -> lane_name_match?(lane.name, &1) end))
      |> Enum.flat_map(fn lane ->
        [
          {Cadence.Runtime.Telemetry.Lanes.CVTConsumer,
           [
             mission_id: mission_id,
             shard_count: lane_shard_count(lanes, lane),
             source: source,
             lane: lane,
             base_dir: base_dir
           ]},
          {Cadence.Runtime.Telemetry.Lanes.LimitsConsumer,
           [
             mission_id: mission_id,
             shard_count: lane_shard_count(lanes, lane),
             source: source,
             lane: lane,
             base_dir: base_dir
           ]}
        ]
      end)

    stateful_children =
      if stateful_shard_count > 0 do
        [
          {StatefulSupervisor,
           [
             mission_id: mission_id,
             lane: stateful_lane,
             shard_count: stateful_shard_count,
             source_shard_count: stateful_source_shard_count,
             sink: sink,
             sink_opts: sink_opts,
             config_version: config_version,
             source: source,
             source_lane: stateful_source_lane,
             base_dir: base_dir
           ]}
        ]
      else
        []
      end

    children =
      [
        {Router,
         [
           mission_id: mission_id,
           lanes: lanes,
           router_version: router_version,
           config_version: config_version,
           max_inflight: max_inflight,
           name: router_name
         ]},
        {Autoscaler,
         [
           mission_id: mission_id,
           router: router_name,
           lanes: lanes,
           max_queue_depth: max_queue_depth
         ]}
      ] ++ lane_children ++ consumer_children ++ stateful_children

    Supervisor.init(children, strategy: :rest_for_one)
  end

  def terminate(reason, _state) do
    case Process.get(:mission_id) do
      nil ->
        :ok

      mission_id ->
        Logger.debug(
          "Stopping Lanes.Supervisor for mission_id=#{mission_id} reason=#{inspect(reason)}"
        )
    end

    :ok
  end

  defp lane_shard_count(lanes, lane) do
    lane_config = Enum.find(lanes, &lane_name_match?(&1.name, lane))
    (lane_config && lane_config.shard_count) || @default_shard_count
  end

  defp lane_name_match?(lane_name, candidate) when is_atom(lane_name) and is_atom(candidate),
    do: lane_name == candidate

  defp lane_name_match?(lane_name, candidate) when is_binary(lane_name) and is_binary(candidate),
    do: lane_name == candidate

  defp lane_name_match?(lane_name, candidate) when is_atom(lane_name) and is_binary(candidate),
    do: Atom.to_string(lane_name) == candidate

  defp lane_name_match?(lane_name, candidate) when is_binary(lane_name) and is_atom(candidate),
    do: lane_name == Atom.to_string(candidate)

  defp lane_name_match?(_, _), do: false
end
