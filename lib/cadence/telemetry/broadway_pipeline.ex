defmodule Cadence.Telemetry.BroadwayPipeline do
  @moduledoc """
  Broadway-based telemetry processing pipeline for high-throughput spacecraft operations.

  This pipeline replaces the GenServer-based Pipeline with a concurrent, backpressure-aware
  streaming architecture using Broadway (GenStage).

  ## Architecture

  ```
  Interfaces → PubSub → Broadway Pipeline → CVT → PubSub → UI
  ```

  ## Processing Stages

  1. **Producer** - Subscribes to PubSub `mission:<mission_id>:telemetry:raw`
  2. **Processor (identify)** - Packet type identification via ETS lookup
  3. **Processor (decommutate)** - Extract telemetry items from binary
  4. **Processor (convert)** - Apply polynomial/state conversions
  5. **Processor (derive)** - Compute derived items from expressions
  6. **Processor (check_limits)** - Check red/yellow limits (TODO)
  7. **Batcher** - Batch CVT updates for efficiency
  8. **Batch Processor** - Bulk write to CVT + PubSub

  ## Configuration

  - Concurrency: 4 processors per stage (configurable)
  - Max demand: 10 messages per processor
  - Batcher: 100ms batch timeout, 50 message max batch
  - Partition: By target_id for ordered processing per target

  ## Backpressure

  Broadway provides automatic backpressure: if CVT updates are slow, the pipeline
  slows down packet processing automatically, preventing memory buildup.
  """

  use Broadway
  require Logger

  alias Broadway.Message
  alias Cadence.Telemetry.{Packet, PacketIdentifier, Decommutation, CurrentValueTable, Conversions, DerivedItems, Stats}

  # Tunable parameters for throughput optimization
  @producer_concurrency 1
  @processor_concurrency 4
  @batcher_concurrency 2
  @max_demand 10
  @batch_size 50
  @batch_timeout 100
  # Rate limit: packets per second (set high to find true processing ceiling)
  # Note: 1000 was the original limit, 500 Hz ceiling was due to this
  @rate_limit 50000

  ## Client API

  @doc """
  Starts the Broadway pipeline for a mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)

    Broadway.start_link(__MODULE__,
      name: via_tuple(mission_id),
      context: %{mission_id: mission_id},
      producer: [
        module: {Cadence.Telemetry.BroadwayPubSub, mission_id: mission_id},
        concurrency: @producer_concurrency,
        transformer: {__MODULE__, :transform, []},
        rate_limiting: [allowed_messages: @rate_limit, interval: 1000]
      ],
      processors: [
        default: [concurrency: @processor_concurrency, max_demand: @max_demand]
      ],
      batchers: [
        cvt_updates: [
          concurrency: @batcher_concurrency,
          batch_size: @batch_size,
          batch_timeout: @batch_timeout,
          partition_by: &partition_by_target/1
        ]
      ]
    )
  end

  @doc """
  Transforms incoming PubSub messages into Broadway messages.

  This is called by the producer to convert raw PubSub events into structured messages.
  """
  def transform({packet, metadata}, _opts) do
    %Message{
      data: %{packet: packet, metadata: metadata},
      acknowledger: {__MODULE__, :ack_id, :ack_data}
    }
  end

  ## Broadway Callbacks

  @impl Broadway
  def process_name({:via, Registry, {registry, {key_prefix, mission_id, _base}}}, suffix) do
    {:via, Registry, {registry, {key_prefix, mission_id, suffix}}}
  end

  @impl Broadway
  def handle_message(:default, %Message{data: %{packet: %Packet{} = packet, metadata: _metadata}} = message, context) do
    process_start = System.monotonic_time(:microsecond)
    mission_id = context.mission_id

    # Step 1: Identify packet type based on format
    packet_format = Packet.get_format(packet)

    identify_result = Stats.time(mission_id, :identify, fn ->
      identify_packet(packet, packet_format, mission_id)
    end)

    case identify_result do
      {:ok, packet_def} ->
        # Step 2: Extract payload and decommutate
        case Packet.get_payload(packet) do
          {:ok, payload} ->
            decom_result = Stats.time(mission_id, :decommutate, fn ->
              Decommutation.decommutate(payload, packet_def, packet_format)
            end)

            case decom_result do
              {:ok, raw_items} ->
                # Step 3: Apply conversions
                converted_items = Stats.time(mission_id, :convert, fn ->
                  apply_conversions(raw_items, packet_def.items)
                end)

                # Step 4: Build qualified item names and compute derived items
                all_items = Stats.time(mission_id, :derive, fn ->
                  # Qualify item names with packet name (PACKET.item format)
                  packet_name = packet_def.name
                  qualified_items =
                    converted_items
                    |> Enum.map(fn {name, value} -> {"#{packet_name}.#{name}", value} end)
                    |> Enum.into(%{})

                  # Compute derived items using mission's runtime overlay
                  case DerivedItems.compute(qualified_items, mission_id) do
                    {:ok, items} -> items
                    {:error, reason} ->
                      Logger.warning("Derived items computation failed: #{inspect(reason)}")
                      qualified_items
                  end
                end)

                # Step 5: Check limits (TODO)
                items_with_limits =
                  Enum.map(all_items, fn {name, value} ->
                    {name, value, :green}
                  end)

                # Record total processing time
                process_duration = System.monotonic_time(:microsecond) - process_start
                Stats.record_timing(mission_id, :total_process, process_duration)

                # Build final message data for batcher
                message
                |> Message.update_data(fn data ->
                  Map.merge(data, %{
                    packet_def: packet_def,
                    items_with_limits: items_with_limits
                  })
                end)
                |> Message.put_batcher(:cvt_updates)

              {:error, reason} ->
                Logger.error("Decommutation error for #{packet_def.name}: #{inspect(reason)}")
                Message.failed(message, reason)
            end

          {:error, reason} ->
            Logger.error("Payload extraction error: #{inspect(reason)}")
            Message.failed(message, reason)
        end

      {:error, :unknown_packet} ->
        Logger.warning(
          "Unknown packet type for mission_id=#{mission_id}, format=#{packet_format}"
        )

        Message.failed(message, :unknown_packet)

      {:error, reason} ->
        Logger.error("Packet identification error: #{inspect(reason)}")
        Message.failed(message, reason)
    end
  end

  @impl Broadway
  def handle_batch(
        :cvt_updates,
        messages,
        _batch_info,
        %{mission_id: mission_id} = _context
      ) do
    # Time the entire batch CVT update
    total_items = Stats.time(mission_id, :cvt_batch, fn ->
      Enum.reduce(messages, 0, fn message, acc ->
        %{
          packet_def: packet_def,
          metadata: metadata,
          items_with_limits: items_with_limits
        } = message.data

        update_cvt_batch(mission_id, packet_def, metadata, items_with_limits)
        acc + length(items_with_limits)
      end)
    end)

    # Update stats counters
    Stats.increment(mission_id, :packets_processed, length(messages))
    Stats.increment(mission_id, :items_processed, total_items)

    messages
  end

  @impl Broadway
  def handle_failed(messages, context) do
    # Track failed packets
    mission_id = context[:mission_id]
    if mission_id, do: Stats.increment(mission_id, :packets_failed, length(messages))

    # Log failed messages
    Enum.each(messages, fn message ->
      Logger.error("Failed to process message: #{inspect(message.status)}")
    end)

    messages
  end

  ## Private Functions

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:broadway_pipeline, mission_id, :main}}}
  end

  defp partition_by_target(%Message{data: %{packet_def: packet_def}}) do
    # Partition by target_id to ensure ordered processing per target
    # Hash the target_id to get an integer (use "default" if nil)
    target = packet_def.target_id || "default"
    :erlang.phash2(target)
  end

  # Identify packet based on format
  defp identify_packet(%Packet{} = packet, :ccsds, mission_id) do
    # CCSDS format: Use APID from header
    case Packet.get_apid(packet) do
      nil ->
        Logger.debug("CCSDS packet missing APID, raw header: #{inspect(:binary.part(packet.raw, 0, min(6, byte_size(packet.raw))), limit: :infinity)}")
        {:error, :missing_apid}

      apid ->
        # Get target_id from packet for target-scoped definition lookup
        target_id = packet.target_id || "UNKNOWN"
        Logger.debug("Looking up CCSDS packet with APID=#{apid} for mission_id=#{mission_id}, target_id=#{target_id}")
        PacketIdentifier.identify_by_apid(mission_id, target_id, apid)
    end
  end

  defp identify_packet(%Packet{} = packet, :simulator, mission_id) do
    # Simulator format: Use type byte
    case Packet.get_type_byte(packet) do
      {:ok, _type_byte} ->
        # Extract target_id from packet
        case packet.raw do
          <<_type::8, target_id_len::8, rest::binary>> when byte_size(rest) >= target_id_len ->
            <<target_id::binary-size(target_id_len), _payload::binary>> = rest

            # Call identify with type_byte, then merge target_id
            case PacketIdentifier.identify(mission_id, packet.raw) do
              {:ok, packet_def} ->
                {:ok, Map.put(packet_def, :target_id, target_id)}

              error ->
                error
            end

          _ ->
            {:error, :malformed_packet}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_conversions(raw_items, packet_items) do
    # Apply conversions to each item based on its definition
    Enum.map(raw_items, fn {item_name, raw_value} ->
      # Find the item definition
      item_def = Enum.find(packet_items, fn item -> to_string(item.name) == item_name end)

      converted_value =
        case item_def do
          %{conversion: conversion} when not is_nil(conversion) ->
            case Conversions.apply_db_conversion(raw_value, conversion) do
              {:ok, value} -> value
              {:error, reason} ->
                Logger.warning(
                  "Conversion failed for #{item_name}: #{inspect(reason)}, using raw value"
                )

                raw_value
            end

          _ ->
            # No conversion defined
            raw_value
        end

      {item_name, converted_value}
    end)
    |> Enum.into(%{})
  end

  defp update_cvt_batch(mission_id, packet_def, metadata, items_with_limits) do
    received_time = metadata[:received_at] || DateTime.utc_now()
    is_stored = metadata[:stored] || false

    # Skip CVT update for stored (historical) packets
    unless is_stored do
      # Use target_id from metadata (set by interface), fall back to packet_def, then "default"
      target_id = metadata[:target_id] || packet_def.target_id || "default"
      packet_name = packet_def.name

      # Build batch items list (excluding metadata fields)
      batch_items =
        items_with_limits
        |> Enum.reject(fn {item_name, _value, _limits_state} -> item_name in [:received_time] end)
        |> Enum.map(fn {item_name, value, limits_state} ->
          {target_id, packet_name, to_string(item_name), value, limits_state}
        end)

      # Single batched ETS insert (UI polls CVT directly, no broadcast needed)
      CurrentValueTable.set_batch(mission_id, batch_items, received_time: received_time)
    end
  end

  ## Acknowledger Callbacks (No-op for PubSub)

  def ack(:ack_id, _successful, _failed) do
    # PubSub messages don't need acknowledgement
    :ok
  end
end

defmodule Cadence.Telemetry.BroadwayPubSub do
  @moduledoc """
  Broadway producer that subscribes to Phoenix.PubSub.

  Receives raw telemetry packets published on `mission:<mission_id>:telemetry:raw`.
  """

  use GenStage
  require Logger

  alias Cadence.Telemetry.Stats

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @doc """
  Returns the current queue depth of the producer.
  """
  def queue_depth(pid) do
    GenStage.call(pid, :queue_depth)
  end

  @impl GenStage
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    Logger.info("BroadwayPubSub producer starting for mission_id=#{mission_id}")

    # Initialize stats for this mission
    Stats.init(mission_id)

    # Subscribe to raw telemetry topic
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:telemetry:raw")

    {:producer, %{mission_id: mission_id, demand: 0, queue: :queue.new()}}
  end

  @impl GenStage
  def handle_demand(demand, state) do
    # Handle demand from downstream consumers
    dispatch_events(%{state | demand: state.demand + demand})
  end

  @impl GenStage
  def handle_info({:telemetry_packet, packet, metadata}, state) do
    # Track received packets
    Stats.increment(state.mission_id, :packets_received)

    # Received a telemetry packet from PubSub
    event = {packet, metadata}
    new_queue = :queue.in(event, state.queue)
    dispatch_events(%{state | queue: new_queue})
  end

  @impl GenStage
  def handle_call(:queue_depth, _from, state) do
    depth = :queue.len(state.queue)
    {:reply, depth, [], state}
  end

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
