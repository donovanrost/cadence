defmodule Cadence.Simulator.PacketSimulator do
  @moduledoc """
  Test packet simulator for generating realistic telemetry during development.

  This GenServer generates configurable telemetry packets and can output them
  via TCP/UDP for testing the telemetry pipeline without real spacecraft hardware.

  ## Features

  - Generates realistic health, attitude, and power telemetry
  - Configurable packet types and generation rates
  - TCP/UDP output for interface testing
  - Mission-scoped configuration
  - Simulates realistic value variations and anomalies

  ## Usage

      # Start simulator for a mission
      {:ok, pid} = PacketSimulator.start_link(
        mission_id: "mission-123",
        targets: ["sat-1", "sat-2"],
        packet_types: [:health, :attitude, :power],
        rate_hz: 1.0,
        output: {:tcp, "localhost", 8080}
      )

      # Stop simulator
      PacketSimulator.stop(pid)
  """

  use GenServer

  import Bitwise
  require Logger

  alias Cadence.Interfaces
  alias Cadence.Telemetry.ProtocolChain.Processor

  @default_rate_hz 1.0
  @default_packet_types [:health, :attitude, :power]
  # Maximum supported rate (10,000 packets per second)
  @max_rate_hz 15_000

  # CCSDS sync pattern (standard)
  @ccsds_sync <<0x1A, 0xCF, 0xFC, 0x1D>>

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :interface_id,
      :targets,
      :packet_types,
      :rate_hz,
      :output,
      :socket,
      :timer_ref,
      :encoding,
      :write_chain,
      # Burst mode fields for high-rate sending
      interval_ms: 1,
      packets_per_tick: 1,
      cycle_count: 0,
      packet_count: 0
    ]
  end

  ## Client API

  @doc """
  Starts the packet simulator.

  ## Options

  - `:mission_id` - Mission ID for scoping (required)
  - `:interface_id` - Interface ID to look up write protocols from (optional)
  - `:targets` - List of target IDs to simulate (default: ["sim-target-1"])
  - `:packet_types` - List of packet types to generate (default: [:health, :attitude, :power])
  - `:rate_hz` - Packet generation rate in Hz (default: 1.0)
  - `:encoding` - Packet encoding format (default: :json)
    - `:json` - Simple length-prefixed with JSON payload (for testing)
    - `:ccsds` - CCSDS Space Packet Protocol with binary payload (realistic)
  - `:output` - Output configuration:
    - `{:tcp, host, port}` - Send to TCP server
    - `{:udp, host, port}` - Send via UDP
    - `:pubsub` - Publish to Phoenix PubSub only
    - `nil` - No network output (PubSub only)

  When `:interface_id` is provided, the simulator will process outgoing packets
  through the interface's write protocol chain. This allows testing protocols
  like CRC that need to append data to outgoing packets.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    name = Keyword.get(opts, :name, via_tuple(mission_id))
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Stops the simulator.
  """
  def stop(pid) do
    GenServer.stop(pid)
  end

  @doc """
  Gets current simulator statistics.
  """
  def stats(pid) do
    GenServer.call(pid, :get_stats)
  end

  @doc """
  Triggers immediate packet generation (useful for testing).
  """
  def generate_packet(pid) do
    GenServer.cast(pid, :generate_packet)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    interface_id = Keyword.get(opts, :interface_id)
    targets = Keyword.get(opts, :targets, ["sim-target-1"])
    packet_types = Keyword.get(opts, :packet_types, @default_packet_types)
    rate_hz = Keyword.get(opts, :rate_hz, @default_rate_hz)
    encoding = Keyword.get(opts, :encoding, :json)
    output = Keyword.get(opts, :output)

    # Clamp rate to maximum supported
    rate_hz = min(rate_hz, @max_rate_hz)

    # Calculate burst parameters for high-rate sending
    # At rates > 1000 Hz, we can't send one packet per ms, so we send bursts
    {interval_ms, packets_per_tick} = calculate_burst_params(rate_hz)

    # Initialize write chain from interface protocols if interface_id provided
    write_chain = init_write_chain(interface_id)

    mode_info =
      if packets_per_tick > 1 do
        "burst mode: #{packets_per_tick} packets every #{interval_ms}ms"
      else
        "standard mode: #{interval_ms}ms interval"
      end

    Logger.info("""
    Starting PacketSimulator:
      mission_id: #{mission_id}
      interface_id: #{inspect(interface_id)}
      targets: #{inspect(targets)}
      packet_types: #{inspect(packet_types)}
      rate_hz: #{rate_hz} (#{mode_info})
      encoding: #{encoding}
      output: #{inspect(output)}
      write_chain: #{length(write_chain || [])} protocol(s)
    """)

    state = %State{
      mission_id: mission_id,
      interface_id: interface_id,
      targets: targets,
      packet_types: packet_types,
      rate_hz: rate_hz,
      encoding: encoding,
      output: output,
      write_chain: write_chain,
      interval_ms: interval_ms,
      packets_per_tick: packets_per_tick,
      socket: nil,
      timer_ref: nil
    }

    # Connect output if needed
    state =
      case output do
        {:tcp, _host, _port} -> connect_tcp(state)
        {:udp, _host, _port} -> connect_udp(state)
        _ -> state
      end

    # Start generation timer
    timer_ref = Process.send_after(self(), :generate, interval_ms)

    {:ok, %{state | timer_ref: timer_ref}}
  end

  # Calculate burst parameters based on target rate
  # Returns {interval_ms, packets_per_tick}
  #
  # At low rates (≤1000 Hz), we send 1 packet per tick with varying intervals.
  # At high rates (>1000 Hz), we send multiple packets per 1ms tick (burst mode).
  #
  # Examples:
  #   100 Hz  → {10ms, 1 packet}  = 100 pps
  #   1000 Hz → {1ms, 1 packet}   = 1000 pps
  #   5000 Hz → {1ms, 5 packets}  = 5000 pps
  #   10000 Hz → {1ms, 10 packets} = 10000 pps
  defp calculate_burst_params(rate_hz) when rate_hz <= 1000 do
    interval_ms = max(1, trunc(1000 / rate_hz))
    {interval_ms, 1}
  end

  defp calculate_burst_params(rate_hz) do
    # Burst mode: multiple packets per 1ms tick
    packets_per_tick = ceil(rate_hz / 1000)
    {1, packets_per_tick}
  end

  @impl true
  def handle_info(:generate, state) do
    # Generate packets_per_tick cycles worth of packets
    # In standard mode (packets_per_tick=1), this generates one cycle
    # In burst mode (packets_per_tick>1), this generates multiple cycles per tick
    new_state =
      Enum.reduce(1..state.packets_per_tick, state, fn _tick, tick_state ->
        # Generate packets for all targets and all packet types (one full cycle)
        cycle_state =
          Enum.reduce(tick_state.targets, tick_state, fn target_id, acc_state ->
            Enum.reduce(tick_state.packet_types, acc_state, fn packet_type, acc_state2 ->
              generate_and_send_packet(acc_state2, target_id, packet_type)
            end)
          end)

        %{cycle_state | cycle_count: cycle_state.cycle_count + 1}
      end)

    # Schedule next generation using pre-calculated interval
    timer_ref = Process.send_after(self(), :generate, state.interval_ms)

    {:noreply, %{new_state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_cast(:generate_packet, state) do
    # Generate one packet for first target
    target_id = hd(state.targets)
    packet_type = hd(state.packet_types)
    new_state = generate_and_send_packet(state, target_id, packet_type)

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      mission_id: state.mission_id,
      targets: length(state.targets),
      packet_types: state.packet_types,
      rate_hz: state.rate_hz,
      cycle_count: state.cycle_count,
      packet_count: state.packet_count,
      uptime_seconds: state.cycle_count / state.rate_hz
    }

    {:reply, stats, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    if state.socket, do: :gen_tcp.close(state.socket)
    :ok
  end

  ## Private Functions

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :simulator}}}
  end

  # Initialize write protocol chain from interface configuration
  defp init_write_chain(nil), do: nil

  defp init_write_chain(interface_id) do
    protocols = Interfaces.list_protocols(interface_id)

    if Enum.empty?(protocols) do
      nil
    else
      chain = Processor.init_chain(protocols, "write")
      Logger.debug("Initialized write chain with #{length(chain)} protocol(s) for interface #{interface_id}")
      chain
    end
  rescue
    error ->
      Logger.warning("Failed to initialize write chain: #{inspect(error)}")
      nil
  end

  # Process packet through write protocol chain
  defp process_write_chain(%{write_chain: nil} = state, packet) do
    {packet, state}
  end

  defp process_write_chain(%{write_chain: []} = state, packet) do
    {packet, state}
  end

  defp process_write_chain(%{write_chain: write_chain} = state, packet) do
    case Processor.process_write(write_chain, packet) do
      {:ok, encoded_packet, updated_chain} ->
        {encoded_packet, %{state | write_chain: updated_chain}}

      {:error, reason} ->
        Logger.warning("Write chain processing failed: #{inspect(reason)}, sending raw packet")
        {packet, state}
    end
  end

  # Calculate total trailer bytes that will be added by write chain protocols
  # Currently only CRC protocol adds trailer bytes
  defp calculate_write_chain_trailer_size(nil), do: 0
  defp calculate_write_chain_trailer_size([]), do: 0

  defp calculate_write_chain_trailer_size(write_chain) do
    alias Cadence.Telemetry.Protocols.CRCProtocol

    Enum.reduce(write_chain, 0, fn
      {CRCProtocol, state}, acc -> acc + state.crc_size
      _, acc -> acc
    end)
  end

  # Check if CCSDSProtocol is in the write chain
  defp has_ccsds_protocol?(nil), do: false
  defp has_ccsds_protocol?([]), do: false

  defp has_ccsds_protocol?(write_chain) do
    alias Cadence.Telemetry.Protocols.CCSDSProtocol

    Enum.any?(write_chain, fn
      {CCSDSProtocol, _} -> true
      _ -> false
    end)
  end

  defp connect_tcp(state) do
    {:tcp, host, port} = state.output
    host_charlist = String.to_charlist(host)

    # Optimized socket options for high-throughput packet transmission
    opts = [
      :binary,
      active: false,
      # Disable Nagle's algorithm - critical for small packet throughput
      # Without this, TCP batches small packets causing 40ms+ delays
      nodelay: true,
      # Increase send buffer for burst sending (128KB)
      sndbuf: 131_072,
      # Increase receive buffer (64KB)
      recbuf: 65_536,
      # Prevent indefinite blocking on send
      send_timeout: 5000,
      # Keep connection alive for long simulations
      keepalive: true
    ]

    case :gen_tcp.connect(host_charlist, port, opts) do
      {:ok, socket} ->
        Logger.info("Packet simulator connected to TCP #{host}:#{port} (nodelay enabled)")
        %{state | socket: socket}

      {:error, reason} ->
        Logger.warning(
          "Failed to connect to TCP #{host}:#{port}: #{inspect(reason)}. Will use PubSub only."
        )

        state
    end
  end

  defp connect_udp(state) do
    # Optimized UDP socket options for high-throughput
    opts = [
      :binary,
      active: false,
      # Increase send buffer (128KB)
      sndbuf: 131_072
    ]

    case :gen_udp.open(0, opts) do
      {:ok, socket} ->
        Logger.info("Packet simulator opened UDP socket (optimized buffers)")
        %{state | socket: socket}

      {:error, reason} ->
        Logger.warning("Failed to open UDP socket: #{inspect(reason)}. Will use PubSub only.")
        state
    end
  end

  defp generate_and_send_packet(state, target_id, packet_type) do
    packet = generate_packet_data(packet_type, state.cycle_count)

    # Build packet based on encoding and whether we have a write chain
    binary_packet =
      if state.write_chain && state.encoding == :ccsds && has_ccsds_protocol?(state.write_chain) do
        # CCSDSProtocol will handle all framing - just send header + payload
        # CCSDSProtocol.write_data detects pre-built packets and adds sync + CRC
        encode_packet_ccsds_no_sync_raw(packet_type, target_id, packet, state.packet_count)
      else
        # Normal path - full packet encoding
        encode_packet(state.encoding, packet_type, target_id, packet, state.packet_count)
      end

    # Process through write protocol chain if configured
    {processed_packet, state} = process_write_chain(state, binary_packet)

    # Send via network if configured
    state = send_packet_network(state, processed_packet)

    # Always publish to PubSub for testing
    publish_packet(state.mission_id, target_id, packet_type, packet)

    %{state | packet_count: state.packet_count + 1}
  end

  defp generate_packet_data(:health, cycle) do
    # Simulate realistic health telemetry with some variation
    base_temp = 20.0
    temp_variation = :math.sin(cycle / 10.0) * 5.0

    %{
      cpu_temp: base_temp + temp_variation + random_noise(1.0),
      battery_voltage: 14.5 + :math.sin(cycle / 20.0) * 0.5 + random_noise(0.1),
      battery_current: 2.3 + random_noise(0.2),
      battery_percentage: min(100.0, 75.0 + :math.sin(cycle / 50.0) * 20.0),
      uptime_seconds: cycle * 10,
      memory_used_mb: 512 + :rand.uniform(100),
      received_time: DateTime.utc_now()
    }
  end

  defp generate_packet_data(:attitude, cycle) do
    # Simulate spacecraft attitude with slow rotation
    %{
      roll: :math.sin(cycle / 30.0) * 10.0 + random_noise(0.5),
      pitch: :math.cos(cycle / 25.0) * 8.0 + random_noise(0.5),
      yaw: :math.sin(cycle / 40.0) * 15.0 + random_noise(0.5),
      roll_rate: :math.cos(cycle / 15.0) * 0.1 + random_noise(0.01),
      pitch_rate: :math.sin(cycle / 20.0) * 0.1 + random_noise(0.01),
      yaw_rate: :math.cos(cycle / 18.0) * 0.1 + random_noise(0.01),
      received_time: DateTime.utc_now()
    }
  end

  defp generate_packet_data(:power, cycle) do
    # Simulate power subsystem
    solar_panel_angle = rem(cycle, 360)
    solar_efficiency = max(0.0, :math.cos(solar_panel_angle * :math.pi() / 180.0))

    %{
      solar_panel_voltage: 28.0 * solar_efficiency + random_noise(0.5),
      solar_panel_current: 5.0 * solar_efficiency + random_noise(0.2),
      bus_voltage: 27.5 + random_noise(0.3),
      bus_current: 3.2 + random_noise(0.5),
      power_mode: Enum.random(["nominal", "battery", "charging"]),
      received_time: DateTime.utc_now()
    }
  end

  defp random_noise(amplitude) do
    (:rand.uniform() - 0.5) * 2.0 * amplitude
  end

  ## Packet Encoding

  defp encode_packet(:json, packet_type, target_id, data, _packet_count) do
    encode_packet_json(packet_type, target_id, data)
  end

  defp encode_packet(:ccsds, packet_type, target_id, data, packet_count) do
    encode_packet_ccsds(packet_type, target_id, data, packet_count)
  end

  # JSON encoding (original format for simple testing)
  defp encode_packet_json(packet_type, target_id, data) do
    # Simple length-prefixed encoding for testing
    # Format: [length:32][packet_type:8][target_id_len:8][target_id][json_payload]

    packet_type_byte =
      case packet_type do
        :health -> 1
        :attitude -> 2
        :power -> 3
        _ -> 0
      end

    target_id_bytes = target_id
    target_id_len = byte_size(target_id_bytes)

    payload = Jason.encode!(data)
    payload_bytes = payload

    packet_content =
      <<packet_type_byte::8, target_id_len::8>> <>
        target_id_bytes <> payload_bytes

    length = byte_size(packet_content)

    <<length::32, packet_content::binary>>
  end

  # CCSDS Space Packet Protocol encoding (realistic spacecraft format)
  defp encode_packet_ccsds(packet_type, target_id, data, packet_count) do
    # CCSDS Space Packet Protocol structure:
    # [sync:4][primary_header:6][secondary_header:variable][user_data:variable]

    # Assign APIDs based on packet type (Application Process Identifier)
    apid =
      case packet_type do
        :health -> 100
        :attitude -> 101
        :power -> 102
        _ -> 0
      end

    # Encode telemetry data as binary
    payload = encode_telemetry_binary(packet_type, target_id, data)

    # CCSDS Primary Header (6 bytes)
    # Bits 0-2: Version (always 000 for Space Packet Protocol)
    # Bit 3: Type (0=telemetry, 1=command)
    # Bit 4: Secondary header flag (1=present)
    # Bits 5-15: APID (Application Process Identifier)
    version = 0
    type = 0
    # telemetry
    sec_hdr_flag = 1
    # secondary header present
    packet_id = version <<< 13 ||| type <<< 12 ||| sec_hdr_flag <<< 11 ||| apid

    # Sequence control (2 bytes)
    # Bits 0-1: Sequence flags (11=unsegmented)
    # Bits 2-15: Sequence count (0-16383)
    sequence_flags = 3
    # unsegmented
    sequence_count = rem(packet_count, 16384)
    seq_control = sequence_flags <<< 14 ||| sequence_count

    # Data length (2 bytes) - length of (secondary header + user data - 1)
    data_length = byte_size(payload) - 1

    # Assemble primary header
    primary_header = <<packet_id::16, seq_control::16, data_length::16>>

    # Complete CCSDS packet with sync pattern
    @ccsds_sync <> primary_header <> payload
  end

  # CCSDS encoding without sync pattern - for CCSDSProtocol
  # CCSDSProtocol will add sync and handle CRC, updating length field as needed
  defp encode_packet_ccsds_no_sync_raw(packet_type, target_id, data, packet_count) do
    apid =
      case packet_type do
        :health -> 100
        :attitude -> 101
        :power -> 102
        _ -> 0
      end

    payload = encode_telemetry_binary(packet_type, target_id, data)

    version = 0
    type = 0
    sec_hdr_flag = 1
    packet_id = version <<< 13 ||| type <<< 12 ||| sec_hdr_flag <<< 11 ||| apid

    sequence_flags = 3
    sequence_count = rem(packet_count, 16384)
    seq_control = sequence_flags <<< 14 ||| sequence_count

    # CCSDS data_length = payload_size - 1 (CCSDSProtocol will add CRC size if needed)
    data_length = byte_size(payload) - 1
    primary_header = <<packet_id::16, seq_control::16, data_length::16>>

    # Return header + payload (no sync)
    primary_header <> payload
  end

  # Encode telemetry data as binary based on packet type
  defp encode_telemetry_binary(:health, target_id, data) do
    # Secondary header (8 bytes)
    # Timestamp (6 bytes) - simplified: just use seconds since epoch
    timestamp_sec = DateTime.to_unix(data.received_time)

    # Target ID hash (2 bytes)
    target_hash = :erlang.phash2(target_id, 65536)

    secondary_header = <<timestamp_sec::48, target_hash::16>>

    # User data - packed binary telemetry
    # Total: 19 bytes
    user_data =
      <<data.cpu_temp::float-32,
        # 0-3: CPU temp (float, °C)
        data.battery_voltage::float-32,
        # 4-7: Battery voltage (float, V)
        data.battery_current::float-32,
        # 8-11: Battery current (float, A)
        trunc(data.battery_percentage)::8,
        # 12: Battery % (uint8, 0-100)
        data.uptime_seconds::32,
        # 13-16: Uptime (uint32, seconds)
        data.memory_used_mb::16>>

    # 17-18: Memory (uint16, MB)

    secondary_header <> user_data
  end

  defp encode_telemetry_binary(:attitude, target_id, data) do
    timestamp_sec = DateTime.to_unix(data.received_time)
    target_hash = :erlang.phash2(target_id, 65536)
    secondary_header = <<timestamp_sec::48, target_hash::16>>

    # User data - attitude telemetry (24 bytes)
    user_data =
      <<data.roll::float-32,
        # 0-3: Roll (float, deg)
        data.pitch::float-32,
        # 4-7: Pitch (float, deg)
        data.yaw::float-32,
        # 8-11: Yaw (float, deg)
        data.roll_rate::float-32,
        # 12-15: Roll rate (float, deg/s)
        data.pitch_rate::float-32,
        # 16-19: Pitch rate (float, deg/s)
        data.yaw_rate::float-32>>

    # 20-23: Yaw rate (float, deg/s)

    secondary_header <> user_data
  end

  defp encode_telemetry_binary(:power, target_id, data) do
    timestamp_sec = DateTime.to_unix(data.received_time)
    target_hash = :erlang.phash2(target_id, 65536)
    secondary_header = <<timestamp_sec::48, target_hash::16>>

    # Power mode encoding
    power_mode_byte =
      case data.power_mode do
        "nominal" -> 0
        "battery" -> 1
        "charging" -> 2
        _ -> 255
      end

    # User data - power telemetry (17 bytes)
    user_data =
      <<data.solar_panel_voltage::float-32,
        # 0-3: Solar voltage (float, V)
        data.solar_panel_current::float-32,
        # 4-7: Solar current (float, A)
        data.bus_voltage::float-32,
        # 8-11: Bus voltage (float, V)
        data.bus_current::float-32,
        # 12-15: Bus current (float, A)
        power_mode_byte::8>>

    # 16: Power mode (uint8)

    secondary_header <> user_data
  end

  defp send_packet_network(state, _binary_packet) when is_nil(state.socket), do: state

  defp send_packet_network(state, binary_packet) do
    case state.output do
      {:tcp, _host, _port} ->
        case :gen_tcp.send(state.socket, binary_packet) do
          :ok ->
            state

          {:error, reason} ->
            Logger.warning("Failed to send TCP packet: #{inspect(reason)}")
            state
        end

      {:udp, host, port} ->
        host_charlist = String.to_charlist(host)

        case :gen_udp.send(state.socket, host_charlist, port, binary_packet) do
          :ok ->
            state

          {:error, reason} ->
            Logger.warning("Failed to send UDP packet: #{inspect(reason)}")
            state
        end

      _ ->
        state
    end
  end

  defp publish_packet(mission_id, target_id, packet_type, data) do
    topic = "mission:#{mission_id}:simulator"

    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      topic,
      {:simulated_packet, target_id, packet_type, data}
    )
  end
end
