defmodule Cadence.Runtime.Telemetry.PipelineV2.PartitionSupervisor do
  @moduledoc """
  Supervisor for a single partition's processing stages.

  Each partition has its own isolated pipeline of stages:
  IdentifyStage → DecommutationStage → ConversionStage → DeriveStage → CVTBatcher

  Events flow through these stages sequentially within the partition,
  maintaining order for packets with the same (target_id, apid).

  Each partition has its own CVTBatcher, eliminating fan-in bottleneck.

  ## Process Naming

  Stages are registered in the mission registry with names:
  `{:pipeline_v2, mission_id, {:stage, partition, stage_name}}`
  """

  use Supervisor
  require Logger

  alias Cadence.Runtime.Telemetry.PipelineV2.Stages.{
    ConversionStage,
    DecommutationStage,
    DeriveStage,
    IdentifyStage
  }

  alias Cadence.Runtime.Telemetry.PipelineV2.CVTBatcher

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl Supervisor
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    partition = Keyword.fetch!(opts, :partition)
    router_pid = Keyword.fetch!(opts, :router_pid)

    # CVTBatcher config (passed from top-level supervisor)
    batch_size = Keyword.get(opts, :batch_size, 50)
    batch_timeout = Keyword.get(opts, :batch_timeout, 100)
    broadcast_enabled = Keyword.get(opts, :broadcast_enabled, false)

    Logger.debug("Starting PartitionSupervisor for partition #{partition}")

    # Stage names for this partition
    identify_name = stage_name(mission_id, partition, :identify)
    decom_name = stage_name(mission_id, partition, :decom)
    convert_name = stage_name(mission_id, partition, :convert)
    derive_name = stage_name(mission_id, partition, :derive)
    batcher_name = batcher_name(mission_id, partition)

    children = [
      # IdentifyStage subscribes to PartitionRouter (which uses PartitionDispatcher)
      {IdentifyStage,
       [
         mission_id: mission_id,
         partition: partition,
         upstream: router_pid,
         upstream_partitioned: true,
         name: identify_name
       ]},

      # DecommutationStage subscribes to IdentifyStage
      {DecommutationStage,
       [
         mission_id: mission_id,
         partition: partition,
         upstream: identify_name,
         name: decom_name
       ]},

      # ConversionStage subscribes to DecommutationStage
      {ConversionStage,
       [
         mission_id: mission_id,
         partition: partition,
         upstream: decom_name,
         name: convert_name
       ]},

      # DeriveStage subscribes to ConversionStage
      {DeriveStage,
       [
         mission_id: mission_id,
         partition: partition,
         upstream: convert_name,
         name: derive_name
       ]},

      # CVTBatcher subscribes to DeriveStage (per-partition, no fan-in)
      {CVTBatcher,
       [
         mission_id: mission_id,
         partition: partition,
         upstream: derive_name,
         batch_size: batch_size,
         batch_timeout: batch_timeout,
         broadcast_enabled: broadcast_enabled,
         name: batcher_name
       ]}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc """
  Returns the registered name for a stage in a partition.
  """
  def stage_name(mission_id, partition, stage) do
    {:via, Registry,
     {Cadence.MissionRegistry, {:pipeline_v2, mission_id, {:stage, partition, stage}}}}
  end

  @doc """
  Returns the PID of the final stage (DeriveStage) for this partition.

  Used by CVTBatcherBroadway to subscribe to partition outputs.
  """
  def get_output_stage(mission_id, partition) do
    stage_name(mission_id, partition, :derive)
  end

  @doc """
  Returns the registered name for the CVTBatcher in a partition.
  """
  def batcher_name(mission_id, partition) do
    {:via, Registry, {Cadence.MissionRegistry, {:pipeline_v2, mission_id, {:batcher, partition}}}}
  end
end
