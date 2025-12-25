defmodule Cadence.Runtime.Telemetry.PipelineV2.Supervisor do
  @moduledoc """
  Top-level supervisor for the V2 telemetry pipeline.

  Starts and supervises:
  - PartitionRouter (PubSub subscriber, event distributor)
  - PartitionSupervisors (one per partition, each with 5 stages including CVTBatcher)

  ## Architecture

  ```
  PipelineV2.Supervisor
  ├── PartitionRouter (producer)
  ├── PartitionSupervisor_0
  │   ├── IdentifyStage_0
  │   ├── DecommutationStage_0
  │   ├── ConversionStage_0
  │   ├── DeriveStage_0
  │   └── CVTBatcher_0 (per-partition consumer)
  ├── PartitionSupervisor_1
  │   └── ...
  └── ... (N partitions)
  ```

  Each partition has its own CVTBatcher, eliminating fan-in bottleneck
  and enabling parallel ETS writes.

  ## Configuration

  Options passed to start_link:
  - `mission_id` (required) - Mission ID
  - `partition_count` - Number of partitions (default: 16)
  - `batch_size` - CVT batch size (default: 50)
  - `batch_timeout` - CVT batch timeout in ms (default: 100)
  """

  use Supervisor
  require Logger

  alias Cadence.Runtime.Telemetry.PipelineV2.{PartitionRouter, PartitionSupervisor}

  @default_partition_count 16

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    name = via_tuple(mission_id)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl Supervisor
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    partition_count = Keyword.get(opts, :partition_count, @default_partition_count)
    batch_size = Keyword.get(opts, :batch_size, 50)
    batch_timeout = Keyword.get(opts, :batch_timeout, 100)

    Logger.info(
      "PipelineV2.Supervisor starting for mission_id=#{mission_id} with #{partition_count} partitions"
    )

    router_name = router_name(mission_id)

    # Build children list
    # Each PartitionSupervisor includes its own CVTBatcher (no fan-in)
    partition_children =
      for partition <- 0..(partition_count - 1) do
        %{
          id: {PartitionSupervisor, partition},
          start:
            {PartitionSupervisor, :start_link,
             [
               [
                 mission_id: mission_id,
                 partition: partition,
                 router_pid: router_name,
                 batch_size: batch_size,
                 batch_timeout: batch_timeout,
                 broadcast_enabled: true,
                 name: partition_supervisor_name(mission_id, partition)
               ]
             ]},
          type: :supervisor
        }
      end

    # Start PartitionRouter first, then all PartitionSupervisors
    children =
      [
        # 1. Start the PartitionRouter (producer)
        {PartitionRouter,
         [
           mission_id: mission_id,
           partition_count: partition_count,
           name: router_name
         ]}
      ] ++ partition_children

    # Use rest_for_one: if router fails, restart all partitions
    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc """
  Returns the PartitionRouter PID/name for a mission.
  """
  def get_router(mission_id) do
    router_name(mission_id)
  end

  # Name helpers
  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:pipeline_v2, mission_id, :supervisor}}}
  end

  defp router_name(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:pipeline_v2, mission_id, :router}}}
  end

  defp partition_supervisor_name(mission_id, partition) do
    {:via, Registry,
     {Cadence.MissionRegistry, {:pipeline_v2, mission_id, {:partition_supervisor, partition}}}}
  end
end
