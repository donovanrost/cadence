defmodule Cadence.Missions.MissionInstance do
  @moduledoc """
  Supervisor for a single mission instance.

  This supervisor manages all processes for a specific mission:
  - Current Value Table (CVT)
  - Interface supervisor (for hardware connections)
  - Telemetry pipeline
  - Command queue
  - Limits monitor

  Each mission instance is registered in the MissionRegistry with its mission_id.
  """

  use Supervisor

  require Logger

  alias Cadence.Missions.Mission
  alias Cadence.Telemetry.CurrentValueTable
  alias Cadence.Telemetry.PipelineV2
  alias Cadence.Telemetry.Limits.StateTracker
  alias Cadence.Telemetry.Limits.StalenessMonitor
  alias Cadence.Commands.{Dispatcher, Queue}
  alias Cadence.Alarms.Engine.AlarmManager
  alias Cadence.Automations.Engine.AutomationManager
  alias Cadence.Procedures.Engine.ExecutionCoordinator

  @default_partition_count 16

  def start_link(opts) do
    mission = Keyword.fetch!(opts, :mission)
    Supervisor.start_link(__MODULE__, mission, name: via_tuple(mission.id))
  end

  @impl true
  def init(%Mission{} = mission) do
    Logger.info(
      "Initializing mission instance for mission_id=#{mission.id}, name=#{mission.name}"
    )

    # Check which pipeline version to use
    pipeline_version = Application.get_env(:cadence, :pipeline_version, :v1)

    pipeline_children = pipeline_children(pipeline_version, mission.id)

    children =
      [
        # Current Value Table - stores latest telemetry values
        {CurrentValueTable, mission_id: mission.id},

        # Packet Identifier - ETS-based packet type lookup
        {Cadence.Telemetry.PacketIdentifier, mission_id: mission.id},

        # Limits State Tracker - tracks limit states and persistence counting
        {StateTracker, mission_id: mission.id},

        # Staleness Monitor - detects stale telemetry and transitions to :blue
        {StalenessMonitor, mission_id: mission.id},

        # Alarm Manager - processes limit events and manages alarms
        {AlarmManager, mission_id: mission.id, organization_id: mission.organization_id}
      ] ++
        pipeline_children ++
        [
          # Protocol Chain Supervisor - manages protocol chains (isolated from interfaces)
          {Cadence.Telemetry.ProtocolChainSupervisor, mission_id: mission.id},

          # Interface Supervisor - manages TCP/UDP/Serial connections
          {Cadence.Interfaces.InterfaceSupervisor, mission_id: mission.id},

          # Command Dispatcher - handles command dispatch, verification, and logging
          {Dispatcher, mission_id: mission.id},

          # Command Queue - manages queued commands for ordered execution
          {Queue, mission_id: mission.id},

          # Procedure Execution Coordinator - manages procedure executions
          {ExecutionCoordinator,
           mission_id: mission.id, organization_id: mission.organization_id},

          # Automation Manager - processes events and triggers automations
          {AutomationManager, mission_id: mission.id, organization_id: mission.organization_id}
        ]

    # Strategy: one_for_one means if a child crashes, only restart that child
    # This is appropriate because the CVT, interfaces, pipeline, etc. are independent
    Supervisor.init(children, strategy: :one_for_one)
  end

  # Pipeline children based on version flag
  defp pipeline_children(:v1, mission_id) do
    [
      # Telemetry Pipeline - processes incoming telemetry (GenServer, for simulator)
      {Cadence.Telemetry.Pipeline, mission_id: mission_id},

      # Broadway Pipeline - high-throughput telemetry processing (for real interfaces)
      {Cadence.Telemetry.BroadwayPipeline, mission_id: mission_id}
    ]
  end

  defp pipeline_children(:v2, mission_id) do
    partition_count =
      Application.get_env(:cadence, :pipeline_v2_partition_count, @default_partition_count)

    [
      # Telemetry Pipeline - processes incoming telemetry (GenServer, for simulator)
      {Cadence.Telemetry.Pipeline, mission_id: mission_id},

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
      {Cadence.Telemetry.Pipeline, mission_id: mission_id},

      # V1 Broadway Pipeline
      {Cadence.Telemetry.BroadwayPipeline, mission_id: mission_id},

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
end
