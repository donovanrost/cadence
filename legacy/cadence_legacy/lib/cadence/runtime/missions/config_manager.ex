defmodule Cadence.Runtime.Missions.ConfigManager do
  @moduledoc """
  Mission-scoped config manager that broadcasts versioned updates to runtime processes.
  """

  use GenServer
  require Logger

  alias Cadence.Runtime.Telemetry.ConfigBundle
  alias Cadence.Runtime.Telemetry.DerivedItems.Cache, as: DerivedItemsCache
  alias Cadence.Runtime.Telemetry.Lanes.LaneConfig
  alias Cadence.Runtime.Telemetry.Limits.Cache, as: LimitsCache

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    config = Keyword.fetch!(opts, :config)
    name = {:via, Registry, {Cadence.MissionRegistry, {:mission_config, mission_id}}}
    GenServer.start_link(__MODULE__, %{mission_id: mission_id, config: config}, name: name)
  end

  def apply_config(mission_id, config) do
    GenServer.cast(via_tuple(mission_id), {:apply_config, config})
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:mission_config, mission_id}}}
  end

  @impl true
  def init(state) do
    Logger.debug("Starting ConfigManager for mission_id=#{state.mission_id}")
    broadcast_config(state.mission_id, state.config)
    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "Stopping ConfigManager for mission_id=#{state.mission_id} reason=#{inspect(reason)}"
    )

    :ok
  end

  @impl true
  def handle_cast({:apply_config, config}, state) do
    Logger.info(
      "Applying mission config update for mission_id=#{state.mission_id} generation=#{config.config_generation}"
    )

    broadcast_config(state.mission_id, config)
    {:noreply, %{state | config: config}}
  end

  defp broadcast_config(mission_id, config) do
    config
    |> ConfigBundle.from_config()
    |> ConfigBundle.store()

    Logger.debug(
      "Stored config bundle for mission_id=#{mission_id} generation=#{config.config_generation}"
    )

    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      "mission:#{mission_id}:config",
      {:config_updated, config.config_generation}
    )

    warm_caches(mission_id, config)
    send_router_config(mission_id, config.config_generation)
    send_shard_config(mission_id, config.config_generation)
  end

  defp send_router_config(mission_id, config_version) do
    router_key = {:lanes, mission_id, :router}

    case Registry.lookup(Cadence.MissionRegistry, router_key) do
      [{pid, _}] -> send(pid, {:config_version, config_version})
      _ -> :ok
    end
  end

  defp send_shard_config(mission_id, config_version) do
    lanes = LaneConfig.from_opts([])

    Enum.each(lanes, fn lane ->
      send_lane_config(mission_id, lane, config_version)
    end)

    send_stateful_config(mission_id, config_version)
  end

  defp send_stateful_config(mission_id, config_version) do
    stateful_lane = Application.get_env(:cadence, :pipeline_stateful_lane, :stateful)

    shard_count =
      Application.get_env(:cadence, :pipeline_stateful_lane_shards) ||
        Application.get_env(:cadence, :pipeline_lane_shards)

    if is_integer(shard_count) and shard_count > 0 do
      Enum.each(0..(shard_count - 1), fn shard_id ->
        shard_key = {:lanes, mission_id, {:stateful_shard, stateful_lane, shard_id}}
        send_config_version(shard_key, config_version)
      end)
    end
  end

  defp send_lane_config(mission_id, lane, config_version) do
    Enum.each(0..(lane.shard_count - 1), fn shard_id ->
      shard_key = {:lanes, mission_id, {:shard, lane.name, shard_id}}
      send_config_version(shard_key, config_version)
    end)
  end

  defp send_config_version(shard_key, config_version) do
    case Registry.lookup(Cadence.MissionRegistry, shard_key) do
      [{pid, _}] -> send(pid, {:config_version, config_version})
      _ -> :ok
    end
  end

  defp warm_caches(mission_id, config) do
    DerivedItemsCache.warm_from_defs(mission_id, config.derived_item_defs)

    LimitsCache.warm_from_packet_defs(
      mission_id,
      config.targets,
      config.packet_defs
    )
  end
end
