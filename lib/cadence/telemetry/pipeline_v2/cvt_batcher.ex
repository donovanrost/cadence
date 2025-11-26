defmodule Cadence.Telemetry.PipelineV2.CVTBatcher do
  @moduledoc """
  GenStage consumer that batches CVT updates from all partitions.

  Subscribes to all DeriveStage outputs and batches events before writing
  to CVT. Batching reduces ETS write overhead for high-throughput scenarios.

  ## Batching Strategy

  - **Time-based**: Flush batch after `batch_timeout_ms` (default: 100ms)
  - **Size-based**: Flush batch when it reaches `batch_size` (default: 50)
  - Whichever comes first triggers a flush

  ## Subscription

  Dynamically subscribes to DeriveStages for all partitions after startup.
  Uses `:max_demand` and `:min_demand` for backpressure.
  """

  use GenStage
  require Logger

  alias Cadence.Telemetry.{CurrentValueTable, Stats}
  alias Cadence.Telemetry.PipelineV2.{PipelineEvent, PartitionSupervisor}

  @default_batch_size 50
  @default_batch_timeout 100

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenStage.start_link(__MODULE__, opts, name: name)
  end

  @impl GenStage
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    partition_count = Keyword.fetch!(opts, :partition_count)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    batch_timeout = Keyword.get(opts, :batch_timeout, @default_batch_timeout)

    Logger.info("CVTBatcher starting for mission_id=#{mission_id}")

    state = %{
      mission_id: mission_id,
      partition_count: partition_count,
      batch_size: batch_size,
      batch_timeout: batch_timeout,
      batch: [],
      batch_count: 0,
      timer_ref: nil
    }

    # Start the batch timer
    state = schedule_flush(state)

    # Schedule subscription to partitions after a short delay
    # This gives time for PartitionSupervisors to start their stages
    Process.send_after(self(), :subscribe_to_partitions, 200)

    {:consumer, state}
  end

  @impl GenStage
  def handle_info(:subscribe_to_partitions, state) do
    subscribe_to_all_partitions(state)
    {:noreply, [], state}
  end

  def handle_info(:flush_batch, state) do
    state = flush_batch(state)
    state = schedule_flush(state)
    {:noreply, [], state}
  end

  @doc """
  Triggers subscription to all partition DeriveStages.
  Call this after the PipelineV2.Supervisor has started all children.
  """
  def subscribe_to_partitions(batcher_pid) do
    send(batcher_pid, :subscribe_to_partitions)
  end

  defp subscribe_to_all_partitions(state) do
    %{mission_id: mission_id, partition_count: partition_count} = state

    Logger.debug("CVTBatcher subscribing to #{partition_count} partitions")

    # Subscribe to each partition's DeriveStage
    for partition <- 0..(partition_count - 1) do
      derive_stage = PartitionSupervisor.get_output_stage(mission_id, partition)

      case GenServer.whereis(derive_stage) do
        nil ->
          Logger.warning("DeriveStage for partition #{partition} not found, retrying in 100ms")
          Process.send_after(self(), :subscribe_to_partitions, 100)

        _pid ->
          GenStage.async_subscribe(self(), to: derive_stage, max_demand: 10, min_demand: 5)
      end
    end
  end

  @impl GenStage
  def handle_subscribe(:producer, _opts, _from, state) do
    {:automatic, state}
  end

  @impl GenStage
  def handle_events(events, _from, state) do
    # Add events to batch
    new_batch = state.batch ++ events
    new_count = state.batch_count + length(events)

    state = %{state | batch: new_batch, batch_count: new_count}

    # Check if we should flush based on size
    state =
      if new_count >= state.batch_size do
        flush_batch(state)
      else
        state
      end

    {:noreply, [], state}
  end

  # Flush the current batch to CVT
  defp flush_batch(%{batch: []} = state), do: state

  defp flush_batch(state) do
    %{mission_id: mission_id, batch: events} = state

    Stats.time(mission_id, :cvt_batch, fn ->
      # Group events by target_id for efficient batch updates
      events
      |> Enum.each(fn event ->
        write_event_to_cvt(mission_id, event)

        # Record end-to-end latency (packet arrival to CVT write)
        completion_time = System.monotonic_time(:microsecond)
        e2e_latency = completion_time - event.received_at
        Stats.record_timing(mission_id, :end_to_end, e2e_latency)
      end)
    end)

    # Update stats
    Stats.increment(mission_id, :packets_processed, length(events))

    total_items =
      events
      |> Enum.map(fn e -> length(e.items_with_limits || []) end)
      |> Enum.sum()

    Stats.increment(mission_id, :items_processed, total_items)

    %{state | batch: [], batch_count: 0}
  end

  # Write a single event's items to CVT
  defp write_event_to_cvt(mission_id, %PipelineEvent{} = event) do
    %{
      packet_def: packet_def,
      metadata: metadata,
      items_with_limits: items_with_limits
    } = event

    received_time = metadata[:received_at] || DateTime.utc_now()
    is_stored = metadata[:stored] || false

    # Skip CVT update for stored (historical) packets
    unless is_stored do
      target_id = event.target_id
      packet_name = packet_def.name

      # Build batch items list
      batch_items =
        items_with_limits
        |> Enum.reject(fn {item_name, _value, _limits_state} -> item_name in [:received_time] end)
        |> Enum.map(fn {item_name, value, limits_state} ->
          {target_id, packet_name, to_string(item_name), value, limits_state}
        end)

      # Single batched ETS insert
      CurrentValueTable.set_batch(mission_id, batch_items, received_time: received_time)
    end
  end

  # Schedule the next batch flush
  defp schedule_flush(state) do
    # Cancel existing timer if any
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    timer_ref = Process.send_after(self(), :flush_batch, state.batch_timeout)
    %{state | timer_ref: timer_ref}
  end
end
