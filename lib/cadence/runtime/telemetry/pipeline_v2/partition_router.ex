defmodule Cadence.Runtime.Telemetry.PipelineV2.PartitionRouter do
  @moduledoc """
  GenStage producer that subscribes to PubSub and routes events to partitions.

  The PartitionRouter is the entry point for the V2 pipeline. It:
  - Subscribes to `mission:<mission_id>:telemetry:raw`
  - Transforms raw `{packet, metadata}` tuples into PipelineEvent structs
  - Routes events to partitions based on (target_id, apid) hash
  - Uses GenStage.PartitionDispatcher for efficient routing

  ## Partitioning Strategy

  Events are partitioned by `{target_id, apid}` tuple:
  - Same (target_id, apid) → same partition → sequential processing
  - Different (target_id, apid) → may go to different partitions → parallel processing

  This ensures packet ordering within a stream while maximizing parallelism
  across different packet types.

  ## Backpressure

  When downstream partitions slow down, demand decreases and packets queue
  in the router. The queue has a configurable max depth to prevent OOM.
  """

  use GenStage
  require Logger

  alias Cadence.Runtime.Telemetry.PipelineV2.PipelineEvent
  alias Cadence.Telemetry.PipelineMetrics

  @default_partition_count 16
  # Increased default for high-throughput telemetry (was 10,000)
  @default_max_queue_depth 100_000

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenStage.start_link(__MODULE__, opts, name: name)
  end

  @spec queue_depth(atom() | pid() | {atom(), any()} | {:via, atom(), any()}) :: any()
  @doc """
  Returns the current queue depth of the router.
  """
  def queue_depth(pid) do
    GenStage.call(pid, :queue_depth)
  end

  @impl GenStage
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    partition_count = Keyword.get(opts, :partition_count, @default_partition_count)
    max_queue_depth = Keyword.get(opts, :max_queue_depth, @default_max_queue_depth)

    Logger.info(
      "PartitionRouter starting for mission_id=#{mission_id} with #{partition_count} partitions, queue_depth=#{max_queue_depth}"
    )

    # Initialize metrics for this mission (one counter array per partition)
    PipelineMetrics.init(mission_id, partition_count)

    # Subscribe to raw telemetry topic
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:telemetry:raw")

    state = %{
      mission_id: mission_id,
      partition_count: partition_count,
      max_queue_depth: max_queue_depth,
      demand: 0,
      queue: :queue.new(),
      dropped_count: 0
    }

    # Use PartitionDispatcher to route to downstream partitions
    {:producer, state,
     dispatcher: {
       GenStage.PartitionDispatcher,
       partitions: 0..(partition_count - 1), hash: &partition_hash/1
     }}
  end

  @impl GenStage
  def handle_demand(demand, state) do
    dispatch_events(%{state | demand: state.demand + demand})
  end

  @impl GenStage
  def handle_info({:telemetry_packet, packet, metadata}, state) do
    # Transform to PipelineEvent (determines partition)
    event = PipelineEvent.new(packet, metadata, state.mission_id, state.partition_count)

    # Increment counter for the appropriate partition
    PipelineMetrics.inc(state.mission_id, event.partition, :packets_received)

    # Record packet size for bitrate calculation (byte_size is O(1) on binaries)
    PipelineMetrics.inc(state.mission_id, event.partition, :bytes_received, byte_size(packet.raw))

    # Check queue depth before adding
    queue_depth = :queue.len(state.queue)

    if queue_depth >= state.max_queue_depth do
      # Drop oldest event to make room (bounded queue)
      {{:value, _dropped}, trimmed_queue} = :queue.out(state.queue)
      new_queue = :queue.in(event, trimmed_queue)

      if rem(state.dropped_count + 1, 1000) == 0 do
        Logger.warning(
          "PartitionRouter queue full, dropped #{state.dropped_count + 1} events",
          mission_id: state.mission_id
        )
      end

      dispatch_events(%{state | queue: new_queue, dropped_count: state.dropped_count + 1})
    else
      new_queue = :queue.in(event, state.queue)
      dispatch_events(%{state | queue: new_queue})
    end
  end

  @impl GenStage
  def handle_call(:queue_depth, _from, state) do
    depth = :queue.len(state.queue)
    {:reply, depth, [], state}
  end

  # Partition hash function for PartitionDispatcher
  # Returns {event, partition_number}
  defp partition_hash(event) do
    {event, event.partition}
  end

  # Dispatch events when there's demand
  defp dispatch_events(%{demand: 0} = state) do
    {:noreply, [], state}
  end

  defp dispatch_events(%{demand: demand, queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, event}, new_queue} ->
        dispatch_events(%{state | demand: demand - 1, queue: new_queue}, [event])

      {:empty, _queue} ->
        {:noreply, [], state}
    end
  end

  defp dispatch_events(%{demand: 0} = state, events) do
    {:noreply, Enum.reverse(events), state}
  end

  defp dispatch_events(%{demand: demand, queue: queue} = state, events) do
    case :queue.out(queue) do
      {{:value, event}, new_queue} ->
        dispatch_events(%{state | demand: demand - 1, queue: new_queue}, [event | events])

      {:empty, _queue} ->
        {:noreply, Enum.reverse(events), state}
    end
  end
end
