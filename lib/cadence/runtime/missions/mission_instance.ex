defmodule Cadence.Runtime.Missions.MissionInstance do
  @moduledoc """
  Supervisor for a single mission instance.

  This supervisor manages all processes for a specific mission:
  - Current Value Table (CVT)
  - Transport interface supervisor (for hardware connections)
  - Link controllers (per SCID)
  - Channel services (per ChannelId)
  - Telemetry pipeline
  - Command queue
  - Limits monitor

  Each mission instance is registered in the MissionRegistry with its mission_id.

  ## Data Plane

  This module is part of the Data Plane - it manages runtime processes and
  does not make database calls. Configuration is received via MissionConfig
  at startup and updated via `{:apply_config, config}` messages.

  ## Config Injection

  When started with a MissionConfig, the full configuration is passed to
  child processes at startup. This eliminates ETS-based caches in favor of
  GenServer state for config data.

  ## Hot Reload

  Config changes are pushed via `{:apply_config, config}` messages from the
  OrgReconciler. Each child component handles its own config update logic.
  """

  use Supervisor

  require Logger

  # Accept MissionConfig only
  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Automations.Engine.AutomationManager
  alias Cadence.Runtime.Alarms.AlarmManager
  alias Cadence.Runtime.Commands.MetaCommandCache
  alias Cadence.Runtime.Commands.TargetPipelineSupervisor
  alias Cadence.Runtime.Commands.VerificationManager
  alias Cadence.Runtime.Contacts.{ContactScheduler, SignalRouter}
  alias Cadence.Runtime.Contacts.Supervisor, as: ContactSupervisor
  alias Cadence.Runtime.Links.Supervisor, as: LinksSupervisor
  alias Cadence.Runtime.Missions.CacheWarmer
  alias Cadence.Runtime.Missions.ConfigManager
  alias Cadence.Runtime.Missions.MissionStatus
  alias Cadence.Runtime.Missions.MissionTracker
  alias Cadence.Runtime.Protocol.Supervisor, as: ProtocolSupervisor
  alias Cadence.Runtime.Telemetry.CurrentValueTable
  alias Cadence.Runtime.Telemetry.Limits.StalenessMonitor
  alias Cadence.Runtime.Telemetry.Limits.StateTracker
  alias Cadence.Runtime.Transport.COP1.StreamSupervisor, as: COP1StreamSupervisor
  alias Cadence.Runtime.Transport.InterfaceSupervisor
  alias Cadence.Runtime.Uplink.Dispatcher, as: UplinkDispatcher

  @default_lane_shards 8

  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    {mission_id, org_id, config_generation} = extract_ids(config)

    result = Supervisor.start_link(__MODULE__, config, name: via_tuple(mission_id))

    # Track in Phoenix.Tracker after supervisor starts
    case result do
      {:ok, _pid} ->
        track_mission(mission_id, org_id, config_generation)
        result

      error ->
        error
    end
  end

  @impl true
  def init(%MissionConfig{} = config) do
    do_init(config.mission_id, config.mission.name, config.organization_id, config)
  end

  defp do_init(mission_id, mission_name, organization_id, config) do
    Logger.debug("Starting MissionInstance for mission_id=#{mission_id}")
    Process.put(:mission_id, mission_id)

    Logger.info(
      "Initializing mission instance for mission_id=#{mission_id}, name=#{mission_name}"
    )

    Logger.info("Using pipeline_version=lanes for mission_id=#{mission_id}")

    pipeline_children = lanes_pipeline_children(mission_id, config)

    cache_warmer_children =
      if CacheWarmer.enabled?() do
        [
          # Cache Warmer - pre-warms Limits and DerivedItems caches
          # Must be last to ensure all ETS tables and services are ready
          {CacheWarmer, config: config}
        ]
      else
        []
      end

    children =
      [
        # Config Manager - broadcasts versioned config updates
        {ConfigManager, mission_id: mission_id, config: config},
        # Current Value Table - stores latest telemetry values
        {CurrentValueTable, mission_id: mission_id},

        # MetaCommand Cache - ETS-based command lookup for O(1) dispatch
        {MetaCommandCache, mission_id: mission_id},

        # Limits State Tracker - tracks limit states and persistence counting
        {StateTracker, mission_id: mission_id},

        # Staleness Monitor - detects stale telemetry and transitions to :blue
        {StalenessMonitor, mission_id: mission_id},

        # Alarm Manager - processes limit events and manages alarms
        {AlarmManager, mission_id: mission_id, organization_id: organization_id}
      ] ++
        pipeline_children ++
        [
          # Contact Scheduler - activates transports during planned contacts
          # Interface Supervisor - manages new transport interface workers
          {InterfaceSupervisor, mission_id: mission_id},
          # Contact Runtime Supervisor - per-contact readiness & actions
          {ContactSupervisor, mission_id: mission_id},
          # Contact Signal Router - routes transport readiness signals
          {SignalRouter, mission_id: mission_id},
          # Contact Scheduler - activates transports during planned contacts
          {ContactScheduler, mission_id: mission_id, organization_id: organization_id},

          # Links Supervisor - manages per-SCID link controllers
          {LinksSupervisor, mission_id: mission_id},

          # Protocol Supervisor - manages per-channel protocol services
          {ProtocolSupervisor, mission_id: mission_id},

          # Config Reconciler - applies desired bindings from DB
          {Cadence.Runtime.Links.ConfigReconciler,
           mission_id: mission_id, organization_id: organization_id},

          # COP-1 Stream Supervisor - mission-scoped COP-1 stream state
          {COP1StreamSupervisor, mission_id: mission_id},

          # Uplink Dispatcher - routes command PDUs to channel services
          {UplinkDispatcher, config: config},

          # Command Verification Manager - tracks verification runners per mission
          {VerificationManager, mission_id: mission_id},

          # Target Pipeline Supervisor - manages per-target command queues and dispatchers
          {TargetPipelineSupervisor, config: config},

          # Automation Manager - processes events and triggers automations
          {AutomationManager, mission_id: mission_id, organization_id: organization_id}
        ] ++
        cache_warmer_children

    # Strategy: one_for_one means if a child crashes, only restart that child
    # This is appropriate because the CVT, interfaces, pipeline, etc. are independent
    Supervisor.init(children, strategy: :one_for_one)
  end

  def terminate(reason, _state) do
    case Process.get(:mission_id) do
      nil ->
        :ok

      mission_id ->
        Logger.debug(
          "Stopping MissionInstance for mission_id=#{mission_id} reason=#{inspect(reason)}"
        )
    end

    :ok
  end

  defp lanes_pipeline_children(mission_id, config) do
    shard_count = Application.get_env(:cadence, :pipeline_lane_shards, @default_lane_shards)
    router_version = Application.get_env(:cadence, :pipeline_lane_router_version, 1)

    config_version =
      if is_map(config) do
        config.config_generation
      else
        Application.get_env(:cadence, :pipeline_lane_config_version, 0)
      end

    sink = Application.get_env(:cadence, :pipeline_lane_sink, Cadence.Telemetry.LogSink.File)

    source =
      Application.get_env(:cadence, :pipeline_lane_source, Cadence.Telemetry.LogSource.File)

    sink_opts = Application.get_env(:cadence, :pipeline_lane_sink_opts, [])
    sink_opts = maybe_enable_fast_noop_mode(sink, sink_opts)
    lanes = Application.get_env(:cadence, :pipeline_lanes)
    consumer_lanes = Application.get_env(:cadence, :pipeline_lane_consumers, [:payload])
    stateful_lane = Application.get_env(:cadence, :pipeline_stateful_lane, :stateful)
    stateful_source_lane = Application.get_env(:cadence, :pipeline_stateful_source_lane, :payload)

    stateful_shard_count =
      Application.get_env(:cadence, :pipeline_stateful_lane_shards, shard_count)

    [
      # New lanes/shards pipeline
      {Cadence.Runtime.Telemetry.Lanes.Supervisor,
       [
         mission_id: mission_id,
         shard_count: shard_count,
         lanes: lanes,
         consumer_lanes: consumer_lanes,
         stateful_lane: stateful_lane,
         stateful_source_lane: stateful_source_lane,
         stateful_shard_count: stateful_shard_count,
         router_version: router_version,
         config_version: config_version,
         sink: sink,
         sink_opts: sink_opts,
         source: source
       ]}
    ]
  end

  @doc """
  Returns the PID of a mission instance by mission_id.
  """
  def whereis(mission_id) when is_binary(mission_id) do
    case Registry.lookup(Cadence.MissionRegistry, mission_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Returns the via tuple for registering a mission instance.
  """
  def via_tuple(mission_id) when is_binary(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, mission_id}}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Extract mission_id, org_id, and config_generation from config
  defp extract_ids(%MissionConfig{} = config) do
    {config.mission_id, config.organization_id, config.config_generation}
  end

  # Track mission in Phoenix.Tracker
  defp track_mission(mission_id, org_id, config_generation) do
    status = MissionStatus.new(mission_id, config_generation)

    case MissionTracker.track(mission_id, org_id, MissionStatus.to_tracker_meta(status)) do
      {:ok, _ref} ->
        Logger.debug("Tracked mission #{mission_id} in MissionTracker")

      {:error, reason} ->
        Logger.warning("Failed to track mission #{mission_id}: #{inspect(reason)}")
    end
  end

  defp maybe_enable_fast_noop_mode(Cadence.Telemetry.LogSink.Noop, sink_opts) do
    Keyword.put_new(sink_opts, :skip_log_records, true)
  end

  defp maybe_enable_fast_noop_mode(_sink, sink_opts), do: sink_opts
end
