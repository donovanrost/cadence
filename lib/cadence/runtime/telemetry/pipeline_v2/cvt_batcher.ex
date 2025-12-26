defmodule Cadence.Runtime.Telemetry.PipelineV2.CVTBatcher do
  @moduledoc """
  GenStage consumer that batches CVT updates for a single partition.

  Each partition has its own CVTBatcher, subscribing to that partition's
  DeriveStage only. This eliminates fan-in bottleneck and enables parallel
  ETS writes across partitions.

  ## Batching Strategy

  - **Time-based**: Flush batch after `batch_timeout_ms` (default: 100ms)
  - **Size-based**: Flush batch when it reaches `batch_size` (default: 50)
  - Whichever comes first triggers a flush

  ## Subscription

  Subscribes to a single upstream DeriveStage (passed via `upstream` option).
  Uses `:max_demand` and `:min_demand` for backpressure.
  """

  use GenStage
  require Logger

  alias Cadence.Telemetry.PipelineMetrics
  alias Cadence.Runtime.Telemetry.CurrentValueTable

  # Increased batch size for high-throughput (was 50)
  @default_batch_size 500
  @default_batch_timeout 10
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
    upstream = Keyword.fetch!(opts, :upstream)
    partition = Keyword.get(opts, :partition)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    batch_timeout = Keyword.get(opts, :batch_timeout, @default_batch_timeout)
    max_demand = Keyword.get(opts, :max_demand, @default_max_demand)
    min_demand = Keyword.get(opts, :min_demand, @default_min_demand)
    broadcast_enabled = Keyword.get(opts, :broadcast_enabled, @default_broadcast_enabled)

    Logger.info(
      "CVTBatcher starting for mission_id=#{mission_id}, partition=#{partition}, batch_size=#{batch_size}, broadcast=#{broadcast_enabled}"
    )

    state = %{
      mission_id: mission_id,
      partition: partition,
      upstream: upstream,
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

    # Schedule subscription to upstream after a short delay
    # This gives time for DeriveStage to start
    Process.send_after(self(), :subscribe_to_upstream, 100)

    {:consumer, state}
  end

  @impl GenStage
  def handle_info(:subscribe_to_upstream, state) do
    subscribe_to_upstream(state)
    {:noreply, [], state}
  end

  def handle_info(:flush_batch, state) do
    state = flush_batch(state)
    state = schedule_flush(state)
    {:noreply, [], state}
  end

  defp subscribe_to_upstream(state) do
    %{
      upstream: upstream,
      partition: partition,
      max_demand: max_demand,
      min_demand: min_demand
    } = state

    Logger.debug(
      "CVTBatcher partition=#{partition} subscribing to upstream with demand #{max_demand}/#{min_demand}"
    )

    case GenServer.whereis(upstream) do
      nil ->
        Logger.warning("Upstream DeriveStage for partition #{partition} not found, retrying in 100ms")
        Process.send_after(self(), :subscribe_to_upstream, 100)

      _pid ->
        GenStage.async_subscribe(self(),
          to: upstream,
          max_demand: max_demand,
          min_demand: min_demand
        )
    end
  end

  @impl GenStage
  def handle_subscribe(:producer, _opts, _from, state) do
    {:automatic, state}
  end

  @impl GenStage
  def handle_events(events, _from, state) do
    # Cons the events list onto batch (true O(1))
    # batch is a list of event lists: [[e3, e4], [e1, e2]]
    # Will be flattened and reversed in flush_batch
    new_batch = [events | state.batch]
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

  # Sample rate for timing (1 in N batches)
  @timing_sample_rate 10

  # Flush the current batch to CVT
  defp flush_batch(%{batch: []} = state), do: state

  defp flush_batch(state) do
    %{mission_id: mission_id, partition: partition, batch: batch, broadcast_enabled: broadcast_enabled} = state

    # Sample timing at 1 in 10 batches (batches are already 500x less frequent than packets)
    should_time = :rand.uniform(@timing_sample_rate) == 1
    start_time = if should_time, do: System.monotonic_time(:microsecond)

    total_items = flush_batch_inner(mission_id, batch, broadcast_enabled)

    if should_time do
      completion_time = System.monotonic_time(:microsecond)

      # Record cvt_batch timing
      duration = completion_time - start_time
      PipelineMetrics.record_timing(mission_id, partition, :cvt_batch, duration)

      # Record end-to-end latency from a sampled event in the batch
      # Use first event (most recent due to our ordering)
      sample_event = batch |> List.first() |> List.first()

      if sample_event do
        e2e_latency = completion_time - sample_event.received_at
        PipelineMetrics.record_timing(mission_id, partition, :end_to_end, e2e_latency)
      end
    end

    if is_integer(total_items) do
      PipelineMetrics.inc(mission_id, partition, :items_processed, total_items)
    end

    PipelineMetrics.inc(mission_id, partition, :packets_processed, state.batch_count)

    %{state | batch: [], batch_count: 0}
  end

  defp flush_batch_inner(mission_id, batch, broadcast_enabled) do
    # Process newest events first for Map.put_new optimization
    # batch is [[e5,e6], [e3,e4], [e1,e2]] -> [e6,e5,e4,e3,e2,e1]
    events = Enum.flat_map(batch, &Enum.reverse/1)

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

    total_items
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
  # Skips stored packets and duplicate packet types (keeps newest)
  # With newest-first ordering, we only process first occurrence of each packet type
  defp aggregate_batch_items(events) do
    events
    |> Enum.reduce({%{}, MapSet.new(), 0}, fn event, {items_map, seen_packets, count} ->
      %{
        packet: packet,
        packet_def: packet_def,
        metadata: metadata,
        items_with_limits: items_with_limits
      } = event

      # Skip stored (historical) packets
      is_stored = metadata[:stored] || packet.stored || false
      item_count = length(items_with_limits)

      if is_stored do
        {items_map, seen_packets, count + item_count}
      else
        target_id = event.target_id
        packet_name = packet_def.name
        packet_key = {target_id, packet_name}

        if MapSet.member?(seen_packets, packet_key) do
          # Already processed a newer version of this packet, skip entirely
          {items_map, seen_packets, count + item_count}
        else
          # First (newest) occurrence of this packet type - process all items
          prefix_len = byte_size(packet_name) + 1

          new_items =
            items_with_limits
            |> Enum.reduce(items_map, fn {qualified_name, value, limits_state}, acc ->
              item_name = extract_item_name(qualified_name, prefix_len)
              key = {target_id, packet_name, item_name}
              Map.put(acc, key, {target_id, packet_name, item_name, value, limits_state})
            end)

          {new_items, MapSet.put(seen_packets, packet_key), count + item_count}
        end
      end
    end)
    |> then(fn {items_map, _seen, count} -> {Map.values(items_map), count} end)
  end

  # Extract item name from qualified name using pre-computed prefix length
  # "PACKET.item_name" -> "item_name" (where prefix_len = byte_size("PACKET") + 1)
  defp extract_item_name(qualified_name, prefix_len) when is_binary(qualified_name) do
    # binary_part is O(1) - creates a sub-binary reference, no allocation
    binary_part(qualified_name, prefix_len, byte_size(qualified_name) - prefix_len)
  end

  defp extract_item_name(qualified_name, _prefix_len), do: to_string(qualified_name)

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
