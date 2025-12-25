defmodule Cadence.Runtime.Missions.MissionInstance do
  @moduledoc """
  Supervisor for a single mission instance.

  This supervisor manages all processes for a specific mission:
  - Current Value Table (CVT)
  - Interface supervisor (for hardware connections)
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

  # Accept Ecto schema, domain entity, or MissionConfig
  alias Cadence.Missions.Mission
  alias Cadence.Domain.Missions.Entities.Mission, as: MissionEntity
  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Runtime.Telemetry.CurrentValueTable
  alias Cadence.Runtime.Telemetry.PipelineV2
  alias Cadence.Runtime.Telemetry.Limits.StateTracker
  alias Cadence.Runtime.Telemetry.Limits.StalenessMonitor
  alias Cadence.Runtime.Commands.MetaCommandCache
  alias Cadence.Runtime.Commands.TargetPipelineSupervisor
  alias Cadence.Runtime.Alarms.AlarmManager
  alias Cadence.Automations.Engine.AutomationManager
  alias Cadence.Procedures.Engine.ExecutionCoordinator
  alias Cadence.Runtime.Missions.CacheWarmer
  alias Cadence.Runtime.Missions.MissionTracker
  alias Cadence.Runtime.Missions.MissionStatus

  @default_partition_count 16

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
    do_init(config.mission_id, config.mission.name, config.organization_id)
  end

  def init(%Mission{} = mission) do
    do_init(mission.id, mission.name, mission.organization_id)
  end

  def init(%MissionEntity{} = entity) do
    do_init(entity.id, entity.name, entity.organization_id)
  end

  defp do_init(mission_id, mission_name, organization_id) do
    Logger.info(
      "Initializing mission instance for mission_id=#{mission_id}, name=#{mission_name}"
    )

    # Check which pipeline version to use
    pipeline_version = Application.get_env(:cadence, :pipeline_version, :v1)

    pipeline_children = pipeline_children(pipeline_version, mission_id)

    children =
      [
        # Current Value Table - stores latest telemetry values
        {CurrentValueTable, mission_id: mission_id},

        # Packet Identifier - ETS-based packet type lookup
        {Cadence.Runtime.Telemetry.PacketIdentifier, mission_id: mission_id},

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
          # Protocol Chain Supervisor - manages protocol chains (isolated from interfaces)
          {Cadence.Telemetry.ProtocolChainSupervisor, mission_id: mission_id},

          # Interface Supervisor - manages TCP/UDP/Serial connections
          {Cadence.Runtime.Interfaces.InterfaceSupervisor, mission_id: mission_id},

          # Target Pipeline Supervisor - manages per-target command queues and dispatchers
          {TargetPipelineSupervisor, mission_id: mission_id},

          # Procedure Execution Coordinator - manages procedure executions
          {ExecutionCoordinator, mission_id: mission_id, organization_id: organization_id},

          # Automation Manager - processes events and triggers automations
          {AutomationManager, mission_id: mission_id, organization_id: organization_id},

          # Cache Warmer - pre-warms Limits and DerivedItems caches
          # Must be last to ensure all ETS tables and services are ready
          {CacheWarmer, mission_id: mission_id}
        ]

    # Strategy: one_for_one means if a child crashes, only restart that child
    # This is appropriate because the CVT, interfaces, pipeline, etc. are independent
    Supervisor.init(children, strategy: :one_for_one)
  end

  # Pipeline children based on version flag
  defp pipeline_children(:v1, mission_id) do
    [
      # Telemetry Pipeline - processes incoming telemetry (GenServer, for simulator)
      {Cadence.Runtime.Telemetry.Pipeline, mission_id: mission_id},

      # Broadway Pipeline - high-throughput telemetry processing (for real interfaces)
      {Cadence.Runtime.Telemetry.BroadwayPipeline, mission_id: mission_id}
    ]
  end

  defp pipeline_children(:v2, mission_id) do
    partition_count =
      Application.get_env(:cadence, :pipeline_v2_partition_count, @default_partition_count)

    [
      # Telemetry Pipeline - processes incoming telemetry (GenServer, for simulator)
      {Cadence.Runtime.Telemetry.Pipeline, mission_id: mission_id},

      # V2 Pipeline - high-throughput GenStage-based processing
      {PipelineV2.Supervisor,
       [
         mission_id: mission_id,
         partition_count: partition_count
       ]}
    ]
  end

  defp pipeline_children(:both, mission_id) do
    # Run both pipelines in parallel for testing/comparison
    partition_count =
      Application.get_env(:cadence, :pipeline_v2_partition_count, @default_partition_count)

    [
      # Telemetry Pipeline - processes incoming telemetry (GenServer, for simulator)
      {Cadence.Runtime.Telemetry.Pipeline, mission_id: mission_id},

      # V1 Broadway Pipeline
      {Cadence.Runtime.Telemetry.BroadwayPipeline, mission_id: mission_id},

      # V2 Pipeline (will also subscribe to same PubSub topic)
      {PipelineV2.Supervisor,
       [
         mission_id: mission_id,
         partition_count: partition_count
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

  defp extract_ids(%Mission{} = mission) do
    {mission.id, mission.organization_id, mission.config_generation || 1}
  end

  defp extract_ids(%MissionEntity{} = entity) do
    {entity.id, entity.organization_id, entity.config_generation || 1}
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
end
