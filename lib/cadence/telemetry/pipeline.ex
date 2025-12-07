defmodule Cadence.Telemetry.Pipeline do
  @moduledoc """
  Main telemetry processing pipeline for a mission.

  Orchestrates the complete telemetry flow:
  1. Receives pre-deframed packets from interfaces (with metadata)
  2. Packet identification (ETS lookup)
  3. Decommutation (extracting telemetry items)
  4. Conversions (RAW to CONVERTED values)
  5. CVT update (storing current values)
  6. PubSub broadcast (for real-time display)

  Each mission has its own pipeline instance for isolation.

  ## Protocol Architecture

  Following the COSMOS architecture, protocol framing is now handled by
  interfaces. The pipeline receives clean packets with metadata indicating:
  - Whether the packet is stored (historical) or real-time
  - Which target and interface it came from
  - Reception timestamp

  Stored packets do not update the CVT (to avoid overwriting real-time data).
  """

  use GenServer
  require Logger

  alias Cadence.Telemetry.{PacketIdentifier, Decommutation, CurrentValueTable}

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      packets_processed: 0,
      items_processed: 0,
      errors: 0
    ]
  end

  ## Client API

  @doc """
  Starts the telemetry pipeline for a mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @doc """
  Processes a pre-deframed packet with metadata.

  This is the primary entry point for interfaces. Interfaces handle protocol
  framing and send complete packets with metadata to the pipeline.

  Metadata should include:
  - `stored` - boolean, true for historical data (won't update CVT)
  - `target_id` - string, target identifier
  - `received_at` - DateTime, reception timestamp
  - `interface_id` - optional, interface ID
  """
  def process_packet(mission_id, packet, metadata) when is_binary(packet) and is_map(metadata) do
    GenServer.cast(via_tuple(mission_id), {:process_packet, packet, metadata})
  end

  @doc """
  Processes raw binary data through the pipeline.

  DEPRECATED: Use process_packet/3 instead. This is kept for backward
  compatibility with existing code that doesn't use the interface system.
  """
  def process_data(mission_id, binary_data) when is_binary(binary_data) do
    # Convert to new API format
    metadata = %{
      stored: false,
      target_id: "unknown",
      received_at: DateTime.utc_now()
    }

    process_packet(mission_id, binary_data, metadata)
  end

  @doc """
  Returns pipeline statistics.
  """
  def stats(mission_id) do
    GenServer.call(via_tuple(mission_id), :stats)
  end

  ## Server Callbacks

  @impl true
  def init(mission_id) do
    Logger.info("Starting telemetry pipeline for mission_id=#{mission_id}")

    # Subscribe to simulator packets for this mission
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:simulator")

    state = %State{
      mission_id: mission_id
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:process_packet, packet, metadata}, state) do
    # Process the packet with metadata
    new_state = process_packet_internal(packet, metadata, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      mission_id: state.mission_id,
      packets_processed: state.packets_processed,
      items_processed: state.items_processed,
      errors: state.errors
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:simulated_packet, target_id, packet_type, data}, state) do
    Logger.debug("Received simulated #{packet_type} packet from #{target_id}")

    # For simulator packets, we receive already-parsed data
    # Process it directly (bypass identification since we know the type)
    new_state = process_simulator_packet(target_id, packet_type, data, state)

    {:noreply, new_state}
  end

  ## Private Functions

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :telemetry_pipeline}}}
  end

  defp process_packet_internal(binary_packet, metadata, state) do
    case PacketIdentifier.identify(state.mission_id, binary_packet) do
      {:ok, packet_def} ->
        process_identified_packet(binary_packet, packet_def, metadata, state)

      {:error, :unknown_packet} ->
        Logger.warning("Unknown packet type received for mission_id=#{state.mission_id}")
        %{state | errors: state.errors + 1}

      {:error, reason} ->
        Logger.error("Packet identification error: #{inspect(reason)}")
        %{state | errors: state.errors + 1}
    end
  end

  defp process_identified_packet(binary_packet, packet_def, metadata, state) do
    # Extract payload (skip packet type byte and target_id)
    case binary_packet do
      <<_packet_type::8, target_id_len::8, rest::binary>> ->
        if byte_size(rest) >= target_id_len do
          <<_target_id::binary-size(target_id_len), payload::binary>> = rest

          # Decommutate
          case Decommutation.decommutate(payload, packet_def, :json) do
            {:ok, raw_items} ->
              # Update CVT with each item (respecting stored flag)
              update_cvt(
                packet_def.target_id,
                packet_def.name,
                raw_items,
                metadata,
                state
              )

            {:error, reason} ->
              Logger.error("Decommutation error: #{inspect(reason)}")
              %{state | errors: state.errors + 1}
          end
        else
          Logger.error("Malformed packet: insufficient data for target_id")
          %{state | errors: state.errors + 1}
        end

      _ ->
        Logger.error("Malformed packet structure")
        %{state | errors: state.errors + 1}
    end
  end

  defp process_simulator_packet(target_id, packet_type, data, state) do
    packet_name = packet_type |> to_string() |> String.upcase()

    # Data is already a map of values from the simulator
    # Simulator packets are always real-time (not stored)
    metadata = %{
      stored: false,
      target_id: target_id,
      received_at: DateTime.utc_now()
    }

    update_cvt(target_id, packet_name, data, metadata, state)
  end

  defp update_cvt(target_id, packet_name, items, metadata, state) when is_map(items) do
    received_time = metadata[:received_at] || DateTime.utc_now()
    is_stored = metadata[:stored] || false

    # Update each item in the CVT (skip if stored packet)
    items_count =
      Enum.reduce(items, 0, fn {item_name, raw_value}, count ->
        # Skip metadata fields like received_time
        if item_name not in [:received_time] do
          # TODO: Apply conversions here when we have conversion configs
          converted_value = raw_value

          # Only update CVT if this is NOT a stored (historical) packet
          # Stored packets don't update current values
          unless is_stored do
            CurrentValueTable.set(
              state.mission_id,
              target_id,
              packet_name,
              to_string(item_name),
              converted_value,
              received_time: received_time,
              limits_state: :green
            )
          end

          count + 1
        else
          count
        end
      end)

    %{
      state
      | packets_processed: state.packets_processed + 1,
        items_processed: state.items_processed + items_count
    }
  end
end
