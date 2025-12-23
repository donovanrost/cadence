defmodule Cadence.Runtime.Telemetry.PipelineV2.CVTBatcher do
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

  alias Cadence.Telemetry.Stats
  alias Cadence.Runtime.Telemetry.CurrentValueTable
  alias Cadence.Runtime.Telemetry.PipelineV2.PartitionSupervisor

  # Increased batch size for high-throughput (was 50)
  @default_batch_size 500
  @default_batch_timeout 100
  # Align with stage_behaviour.ex defaults for consistent backpressure
  @default_max_demand 500
  @default_min_demand 250
  # PubSub broadcast is only used by tests, disabled by default for performance
  @default_broadcast_enabled false

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
    max_demand = Keyword.get(opts, :max_demand, @default_max_demand)
    min_demand = Keyword.get(opts, :min_demand, @default_min_demand)
    broadcast_enabled = Keyword.get(opts, :broadcast_enabled, @default_broadcast_enabled)

    Logger.info(
      "CVTBatcher starting for mission_id=#{mission_id}, batch_size=#{batch_size}, broadcast=#{broadcast_enabled}"
    )

    state = %{
      mission_id: mission_id,
      partition_count: partition_count,
      batch_size: batch_size,
      batch_timeout: batch_timeout,
      max_demand: max_demand,
      min_demand: min_demand,
      broadcast_enabled: broadcast_enabled,
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
    %{
      mission_id: mission_id,
      partition_count: partition_count,
      max_demand: max_demand,
      min_demand: min_demand
    } = state

    Logger.debug(
      "CVTBatcher subscribing to #{partition_count} partitions with demand #{max_demand}/#{min_demand}"
    )

    # Subscribe to each partition's DeriveStage
    for partition <- 0..(partition_count - 1) do
      derive_stage = PartitionSupervisor.get_output_stage(mission_id, partition)

      case GenServer.whereis(derive_stage) do
        nil ->
          Logger.warning("DeriveStage for partition #{partition} not found, retrying in 100ms")
          Process.send_after(self(), :subscribe_to_partitions, 100)

        _pid ->
          GenStage.async_subscribe(self(),
            to: derive_stage,
            max_demand: max_demand,
            min_demand: min_demand
          )
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
    %{mission_id: mission_id, batch: events, broadcast_enabled: broadcast_enabled} = state

    Stats.time(mission_id, :cvt_batch, fn ->
      # Aggregate ALL items from ALL events into a single list for one ETS insert
      # This is much faster than N separate inserts
      {all_items, total_items} = aggregate_batch_items(events)

      # Single ETS insert for entire batch (was: one per event)
      unless Enum.empty?(all_items) do
        CurrentValueTable.set_batch(mission_id, all_items, [])

        # Broadcast updates via PubSub for real-time subscribers (WebSocket clients)
        if broadcast_enabled do
          broadcast_batch_updates(mission_id, all_items)
        end
      end

      # Record end-to-end latency (sample from last event in batch)
      case List.last(events) do
        nil ->
          :ok

        event ->
          completion_time = System.monotonic_time(:microsecond)
          e2e_latency = completion_time - event.received_at
          Stats.record_timing(mission_id, :end_to_end, e2e_latency)
      end

      total_items
    end)
    |> case do
      total_items when is_integer(total_items) ->
        Stats.increment(mission_id, :items_processed, total_items)

      _ ->
        :ok
    end

    # Update stats
    Stats.increment(mission_id, :packets_processed, length(events))

    %{state | batch: [], batch_count: 0}
  end

  # Broadcast batch updates grouped by packet for efficient PubSub
  defp broadcast_batch_updates(mission_id, all_items) do
    # Group items by {target_id, packet_name} for batch broadcasting
    all_items
    |> Enum.group_by(fn {target_id, packet_name, _item, _value, _limits} ->
      {target_id, packet_name}
    end)
    |> Enum.each(fn {{target_id, packet_name}, items} ->
      # Convert to format expected by broadcast_packet_update
      formatted_items =
        Enum.map(items, fn {_target, _packet, item_name, value, limits_state} ->
          {item_name,
           %{value: value, limits_state: limits_state, received_time: DateTime.utc_now()}}
        end)

      CurrentValueTable.broadcast_packet_update(
        mission_id,
        target_id,
        packet_name,
        formatted_items
      )
    end)
  end

  # Aggregate all items from all events into a single list
  # Skips stored packets, deduplicates by key (keeps latest value)
  defp aggregate_batch_items(events) do
    events
    |> Enum.reduce({%{}, 0}, fn event, {items_map, count} ->
      %{
        packet: packet,
        packet_def: packet_def,
        metadata: metadata,
        items_with_limits: items_with_limits
      } = event

      # Skip stored (historical) packets
      is_stored = metadata[:stored] || packet.stored || false

      if is_stored do
        {items_map, count}
      else
        target_id = event.target_id
        packet_name = packet_def.name

        # Add items to map (later events overwrite earlier for same key = latest value wins)
        new_items =
          items_with_limits
          |> Enum.reduce(items_map, fn {qualified_name, value, limits_state}, acc ->
            item_name = extract_item_name(qualified_name, packet_name)
            key = {target_id, packet_name, item_name}
            Map.put(acc, key, {target_id, packet_name, item_name, value, limits_state})
          end)

        {new_items, count + length(items_with_limits)}
      end
    end)
    |> then(fn {items_map, count} -> {Map.values(items_map), count} end)
  end

  # Extract item name from qualified name
  # "PACKET.item_name" -> "item_name"
  # "PACKET.RECEIVED_TIMESECONDS" -> "RECEIVED_TIMESECONDS"
  defp extract_item_name(qualified_name, packet_name) do
    prefix = "#{packet_name}."

    if String.starts_with?(qualified_name, prefix) do
      String.replace_prefix(qualified_name, prefix, "")
    else
      # If not qualified (shouldn't happen), use as-is
      to_string(qualified_name)
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
