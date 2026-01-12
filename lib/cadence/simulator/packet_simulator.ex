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

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.Uplink.Pipeline, as: UplinkPipeline
  alias Cadence.Interfaces
  alias Cadence.Runtime.Interfaces.SDLPConfig
  alias Cadence.Telemetry.Packet
  alias Phoenix.PubSub

  @default_rate_hz 1.0
  @default_packet_types [:health, :attitude, :power]
  # Maximum supported rate (10,000 packets per second)
  @max_rate_hz 15_000

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
      :frame,
      :uplink_pipeline,
      :uplink_opts,
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
  - `:encoding` - Packet encoding format (default: :ccsds)
    - `:ccsds` - CCSDS Space Packet Protocol with binary payload (realistic)
  - `:frame` - Frame format for network output (default: nil)
    - `:tm` - TM transfer frame wrapper (SDLP pipeline)
  - `:frame_size` - Frame size in bytes (tm only)
  - `:scid` - Spacecraft ID for frames (tm only)
  - `:vcid` - Virtual channel ID for frames (tm only)
  - `:output` - Output configuration:
    - `{:tcp, host, port}` - Send to TCP server
    - `{:udp, host, port}` - Send via UDP
    - `:pubsub` - Publish to Phoenix PubSub only
    - `nil` - No network output (PubSub only)

  When `:interface_id` is provided, the simulator uses the interface's SDLP
  configuration to frame outgoing packets via the uplink pipeline.
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
    encoding = parse_encoding(Keyword.get(opts, :encoding, :ccsds))
    output = Keyword.get(opts, :output)
    frame = parse_frame_opts(opts)

    # Clamp rate to maximum supported
    rate_hz = min(rate_hz, @max_rate_hz)

    # Calculate burst parameters for high-rate sending
    # At rates > 1000 Hz, we can't send one packet per ms, so we send bursts
    {interval_ms, packets_per_tick} = calculate_burst_params(rate_hz)

    {uplink_pipeline, uplink_opts} = init_uplink_pipeline(interface_id, frame)

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
      uplink_pipeline: #{pipeline_label(uplink_pipeline)}
    """)

    state = %State{
      mission_id: mission_id,
      interface_id: interface_id,
      targets: targets,
      packet_types: packet_types,
      rate_hz: rate_hz,
      encoding: encoding,
      frame: frame,
      output: output,
      uplink_pipeline: uplink_pipeline,
      uplink_opts: uplink_opts,
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
    new_state = run_generation_cycles(state)
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

  defp run_generation_cycles(state) do
    Enum.reduce(1..state.packets_per_tick, state, fn _tick, tick_state ->
      tick_state
      |> generate_cycle_packets()
      |> bump_cycle_count()
    end)
  end

  defp generate_cycle_packets(state) do
    Enum.reduce(state.targets, state, fn target_id, acc_state ->
      Enum.reduce(state.packet_types, acc_state, fn packet_type, acc_state2 ->
        generate_and_send_packet(acc_state2, target_id, packet_type)
      end)
    end)
  end

  defp bump_cycle_count(state) do
    %{state | cycle_count: state.cycle_count + 1}
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

  defp init_uplink_pipeline(nil, frame) do
    init_uplink_from_frame(frame)
  end

  defp init_uplink_pipeline(interface_id, frame) do
    protocols = Interfaces.list_protocols(interface_id)

    case SDLPConfig.fetch(protocols) do
      {:ok, %{opts: opts}} ->
        case UplinkPipeline.init(opts) do
          {:ok, pipeline} -> {pipeline, opts}
          {:error, _} -> init_uplink_from_frame(frame)
        end

      :error ->
        init_uplink_from_frame(frame)
    end
  rescue
    error ->
      Logger.warning("Failed to initialize uplink pipeline: #{inspect(error)}")
      init_uplink_from_frame(frame)
  end

  defp init_uplink_from_frame(nil), do: {nil, nil}

  defp init_uplink_from_frame(%{format: :tm, frame_size: frame_size, scid: scid, vcid: vcid}) do
    opts = [profile: :tm, frame_size: frame_size, uplink_scid: scid, uplink_vcid: vcid]

    case UplinkPipeline.init(opts) do
      {:ok, pipeline} -> {pipeline, opts}
      {:error, _} -> {nil, nil}
    end
  end

  defp init_uplink_from_frame(_), do: {nil, nil}

  defp pipeline_label(nil), do: "none"
  defp pipeline_label(_), do: "sdlp"

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

    # Build packet based on encoding
    binary_packet =
      encode_packet_ccsds_no_sync_raw(packet_type, target_id, packet, state.packet_count)

    {processed_packet, state} = encode_uplink(state, binary_packet)

    # Send via network if configured
    state = send_packet_network(state, processed_packet)

    # Always publish to PubSub for testing
    pubsub_packet =
      encode_packet_ccsds_no_sync_raw(packet_type, target_id, packet, state.packet_count)

    publish_packet(state.mission_id, target_id, packet_type, pubsub_packet)

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

  defp parse_encoding(:ccsds), do: :ccsds
  defp parse_encoding("ccsds"), do: :ccsds

  defp parse_encoding(other) do
    raise ArgumentError, "Unsupported encoding: #{inspect(other)} (supported: :ccsds)"
  end

  ## Packet Encoding

  # CCSDS Space Packet encoding (no sync pattern).
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
    sequence_count = rem(packet_count, 16_384)
    seq_control = sequence_flags <<< 14 ||| sequence_count

    # CCSDS data_length = payload_size - 1
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
    target_hash = :erlang.phash2(target_id, 65_536)

    secondary_header = <<timestamp_sec::48, target_hash::16>>

    # User data - packed binary telemetry
    # Total: 19 bytes
    user_data =
      <<
        data.cpu_temp::float-32,
        # 0-3: CPU temp (float, °C)
        data.battery_voltage::float-32,
        # 4-7: Battery voltage (float, V)
        data.battery_current::float-32,
        # 8-11: Battery current (float, A)
        trunc(data.battery_percentage)::8,
        # 12: Battery % (uint8, 0-100)
        data.uptime_seconds::32,
        # 13-16: Uptime (uint32, seconds)
        data.memory_used_mb::16
      >>

    # 17-18: Memory (uint16, MB)

    secondary_header <> user_data
  end

  defp encode_telemetry_binary(:attitude, target_id, data) do
    timestamp_sec = DateTime.to_unix(data.received_time)
    target_hash = :erlang.phash2(target_id, 65_536)
    secondary_header = <<timestamp_sec::48, target_hash::16>>

    # User data - attitude telemetry (24 bytes)
    user_data =
      <<
        data.roll::float-32,
        # 0-3: Roll (float, deg)
        data.pitch::float-32,
        # 4-7: Pitch (float, deg)
        data.yaw::float-32,
        # 8-11: Yaw (float, deg)
        data.roll_rate::float-32,
        # 12-15: Roll rate (float, deg/s)
        data.pitch_rate::float-32,
        # 16-19: Pitch rate (float, deg/s)
        data.yaw_rate::float-32
      >>

    # 20-23: Yaw rate (float, deg/s)

    secondary_header <> user_data
  end

  defp encode_telemetry_binary(:power, target_id, data) do
    timestamp_sec = DateTime.to_unix(data.received_time)
    target_hash = :erlang.phash2(target_id, 65_536)
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
      <<
        data.solar_panel_voltage::float-32,
        # 0-3: Solar voltage (float, V)
        data.solar_panel_current::float-32,
        # 4-7: Solar current (float, A)
        data.bus_voltage::float-32,
        # 8-11: Bus voltage (float, V)
        data.bus_current::float-32,
        # 12-15: Bus current (float, A)
        power_mode_byte::8
      >>

    # 16: Power mode (uint8)

    secondary_header <> user_data
  end

  defp send_packet_network(state, _binary_packet) when is_nil(state.socket), do: state

  defp send_packet_network(state, binary_packet) do
    framed_packet = binary_packet

    case state.output do
      {:tcp, _host, _port} ->
        case :gen_tcp.send(state.socket, framed_packet) do
          :ok ->
            state

          {:error, reason} ->
            Logger.warning("Failed to send TCP packet: #{inspect(reason)}")
            state
        end

      {:udp, host, port} ->
        host_charlist = String.to_charlist(host)

        case :gen_udp.send(state.socket, host_charlist, port, framed_packet) do
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

  defp publish_packet(mission_id, target_id, packet_type, binary_packet) do
    metadata = %{
      mission_id: mission_id,
      stored: false,
      target_id: target_id,
      received_at: DateTime.utc_now(),
      interface_id: nil,
      source: %{simulator: true, packet_type: packet_type}
    }

    packet =
      case Packet.from_ccsds(binary_packet, metadata) do
        {:ok, packet} -> packet
        {:error, reason} -> log_failed_packet(mission_id, reason)
      end

    if packet do
      PubSub.broadcast(
        Cadence.PubSub,
        "mission:#{mission_id}:telemetry:raw",
        {:telemetry_packet, packet, metadata}
      )
    end
  end

  defp parse_frame_opts(opts) do
    case Keyword.get(opts, :frame) do
      nil ->
        nil

      :tm ->
        frame_size = Keyword.fetch!(opts, :frame_size)

        %{
          format: :tm,
          frame_size: frame_size,
          scid: Keyword.get(opts, :scid, 0),
          vcid: Keyword.get(opts, :vcid, 0)
        }

      "tm" ->
        parse_frame_opts(Keyword.put(opts, :frame, :tm))

      other ->
        raise ArgumentError, "Unsupported frame format: #{inspect(other)} (supported: :tm)"
    end
  end

  defp encode_uplink(%{uplink_pipeline: nil} = state, packet), do: {packet, state}

  defp encode_uplink(%{uplink_pipeline: pipeline, uplink_opts: opts} = state, packet) do
    ctx = %{
      frame_size: opts[:frame_size],
      scid: opts[:uplink_scid] || opts[:scid],
      vcid: opts[:uplink_vcid] || opts[:vcid],
      map_id: opts[:uplink_map_id]
    }

    sdu = %SDUOctets{
      profile: opts[:profile],
      scid: ctx.scid,
      vcid: ctx.vcid,
      map_id: ctx.map_id,
      direction: :uplink,
      sdu_kind_hint: :space_packet,
      octets: packet,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    case UplinkPipeline.encode(sdu, ctx, pipeline, opts) do
      {:ok, encoded, new_pipeline} ->
        {encoded, %{state | uplink_pipeline: new_pipeline}}

      {:error, reason, new_pipeline} ->
        Logger.warning("Uplink pipeline failed: #{inspect(reason)}, sending raw packet")
        {packet, %{state | uplink_pipeline: new_pipeline}}
    end
  end

  defp log_failed_packet(mission_id, reason) do
    Logger.warning(
      "Simulator failed to build CCSDS packet for mission #{mission_id}: #{inspect(reason)}"
    )

    nil
  end
end
