defmodule Cadence.Simulator.Coordinator do
  @moduledoc """
  Mission-scoped GenServer that orchestrates simulation.

  The Coordinator:
  1. Manages the active DynamicsProvider (BasicDynamics or ScenarioProvider)
  2. Loads packet definitions from YAML for proper encoding
  3. Schedules telemetry generation at the configured rate
  4. Encodes values into binary packets using PacketEncoder
  5. Sends packets via TCP/UDP to configured interface

  ## Usage

      # Start with basic dynamics
      {:ok, pid} = Coordinator.start_link(
        mission_id: "mission-123",
        target_id: "SIM-1",
        output: {:tcp, "localhost", 9999},
        rate_hz: 1.0
      )

      # Start with scenario
      {:ok, pid} = Coordinator.start_link(
        mission_id: "mission-123",
        target_id: "SIM-1",
        output: {:tcp, "localhost", 9999},
        scenario_path: "priv/scenarios/alarm_test.yaml",
        definitions_path: "path/to/telemetry.yaml"
      )

      # Stop
      Coordinator.stop(pid)

  ## Configuration Options

  - `:mission_id` - Mission UUID (required)
  - `:target_id` - Target identifier (default: "SIM-1")
  - `:output` - Output mode: `{:tcp, host, port}` or `{:udp, host, port}`
  - `:rate_hz` - Generation rate in Hz (default: 1.0)
  - `:provider` - Provider module (default: BasicDynamics)
  - `:provider_config` - Config passed to provider init
  - `:definitions_path` - Path to YAML packet definitions
  - `:scenario_path` - Path to scenario file (for ScenarioProvider)
  """

  use GenServer

  require Logger

  alias Cadence.Simulator.PacketEncoder
  alias Cadence.Simulator.Providers.{BasicDynamics, DatabaseDynamics, ScenarioProvider}

  @default_rate_hz 1.0
  @default_target_id "SIM-1"

  defstruct [
    :mission_id,
    :target_id,
    :provider_module,
    :provider_state,
    :encoder,
    :output,
    :socket,
    :rate_hz,
    :timer_ref,
    step: 0,
    packet_count: 0
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the simulation coordinator.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    name = Keyword.get(opts, :name, via_tuple(mission_id))
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Stops the coordinator.
  """
  def stop(pid) do
    GenServer.stop(pid)
  end

  @doc """
  Gets current coordinator statistics.
  """
  def stats(pid) do
    GenServer.call(pid, :get_stats)
  end

  @doc """
  Gets the provider status.
  """
  def provider_status(pid) do
    GenServer.call(pid, :get_provider_status)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    target_id = Keyword.get(opts, :target_id, @default_target_id)
    rate_hz = Keyword.get(opts, :rate_hz, @default_rate_hz)
    output = Keyword.get(opts, :output)

    # Determine provider based on options
    {provider_module, provider_config} = determine_provider(opts)

    # Initialize provider
    case provider_module.init(provider_config) do
      {:ok, provider_state} ->
        # Load encoder if definitions provided
        encoder = load_encoder(opts)

        state = %__MODULE__{
          mission_id: mission_id,
          target_id: target_id,
          provider_module: provider_module,
          provider_state: provider_state,
          encoder: encoder,
          output: output,
          rate_hz: rate_hz,
          socket: nil
        }

        # Connect output if needed
        state = connect_output(state)

        Logger.info("""
        Simulator Coordinator started:
          mission_id: #{mission_id}
          target_id: #{target_id}
          provider: #{inspect(provider_module)}
          rate_hz: #{rate_hz}
          output: #{inspect(output)}
          encoder: #{if encoder, do: "loaded", else: "none (using hardcoded encoding)"}
        """)

        # Schedule first generation
        interval_ms = trunc(1000 / rate_hz)
        timer_ref = Process.send_after(self(), :generate, interval_ms)

        {:ok, %{state | timer_ref: timer_ref}}

      {:error, reason} ->
        {:stop, {:provider_init_failed, reason}}
    end
  end

  @impl true
  def handle_info(:generate, state) do
    # Generate values from provider
    {values, provider_state} =
      case state.provider_module.generate_values(state.provider_state, state.step) do
        {:ok, values, new_state} ->
          {values, new_state}

        {:error, reason, new_state} ->
          Logger.error("Provider error: #{inspect(reason)}")
          {%{}, new_state}
      end

    # Encode and send packets
    state = send_telemetry(state, values)

    # Schedule next generation
    interval_ms = trunc(1000 / state.rate_hz)
    timer_ref = Process.send_after(self(), :generate, interval_ms)

    new_state = %{
      state
      | provider_state: provider_state,
        timer_ref: timer_ref,
        step: state.step + 1,
        packet_count: state.packet_count + 1
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      mission_id: state.mission_id,
      target_id: state.target_id,
      provider: state.provider_module,
      rate_hz: state.rate_hz,
      step: state.step,
      packet_count: state.packet_count,
      uptime_seconds: state.step / state.rate_hz,
      output: format_output(state.output),
      encoder_loaded: state.encoder != nil
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:get_provider_status, _from, state) do
    status =
      if function_exported?(state.provider_module, :status, 1) do
        state.provider_module.status(state.provider_state)
      else
        %{provider: state.provider_module}
      end

    {:reply, status, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    if state.socket, do: close_socket(state)
    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :simulator_coordinator}}}
  end

  defp determine_provider(opts) do
    cond do
      # Scenario path provided -> use ScenarioProvider
      scenario_path = Keyword.get(opts, :scenario_path) ->
        config = %{scenario_path: scenario_path}
        {ScenarioProvider, config}

      # Inline scenario provided
      scenario = Keyword.get(opts, :scenario) ->
        config = %{scenario: scenario}
        {ScenarioProvider, config}

      # Explicit provider
      provider = Keyword.get(opts, :provider) ->
        config = Keyword.get(opts, :provider_config, %{})
        {provider, config}

      # Definitions path provided -> use DatabaseDynamics
      definitions_path = Keyword.get(opts, :definitions_path) ->
        config = %{
          definitions_path: definitions_path,
          noise_amplitude: Keyword.get(opts, :noise_amplitude, 1.0)
        }

        {DatabaseDynamics, config}

      # Default to BasicDynamics
      true ->
        config = Keyword.get(opts, :provider_config, %{})
        {BasicDynamics, config}
    end
  end

  defp load_encoder(opts) do
    case Keyword.get(opts, :definitions_path) do
      nil ->
        nil

      path ->
        case PacketEncoder.load(path) do
          {:ok, encoder} ->
            Logger.info("Loaded packet definitions from #{path}")
            encoder

          {:error, reason} ->
            Logger.warning("Failed to load definitions from #{path}: #{inspect(reason)}")
            nil
        end
    end
  end

  defp connect_output(%{output: nil} = state), do: state

  defp connect_output(%{output: {:tcp, host, port}} = state) do
    opts = [
      :binary,
      active: false,
      nodelay: true,
      sndbuf: 131_072,
      send_timeout: 5000
    ]

    case :gen_tcp.connect(String.to_charlist(host), port, opts) do
      {:ok, socket} ->
        Logger.info("Connected to TCP #{host}:#{port}")
        %{state | socket: socket}

      {:error, reason} ->
        Logger.warning("Failed to connect to TCP #{host}:#{port}: #{inspect(reason)}")
        state
    end
  end

  defp connect_output(%{output: {:udp, _host, _port}} = state) do
    case :gen_udp.open(0, [:binary, sndbuf: 131_072]) do
      {:ok, socket} ->
        Logger.info("Opened UDP socket")
        %{state | socket: socket}

      {:error, reason} ->
        Logger.warning("Failed to open UDP socket: #{inspect(reason)}")
        state
    end
  end

  defp connect_output(state), do: state

  defp close_socket(%{socket: nil}), do: :ok
  defp close_socket(%{output: {:tcp, _, _}, socket: socket}), do: :gen_tcp.close(socket)
  defp close_socket(%{output: {:udp, _, _}, socket: socket}), do: :gen_udp.close(socket)
  defp close_socket(_), do: :ok

  defp send_telemetry(state, values) when map_size(values) == 0, do: state

  defp send_telemetry(%{encoder: nil} = state, values) do
    # No encoder - use hardcoded encoding (legacy behavior)
    send_hardcoded_packets(state, values)
  end

  defp send_telemetry(%{encoder: encoder} = state, values) do
    # Use encoder for proper packet construction
    case PacketEncoder.encode(encoder, state.target_id, values) do
      {:ok, packets, updated_encoder} ->
        Enum.each(packets, fn {_packet_name, binary} ->
          send_packet(state, binary)
        end)

        %{state | encoder: updated_encoder}

      {:error, reason} ->
        Logger.error("Encoding failed: #{inspect(reason)}")
        state
    end
  end

  # Legacy hardcoded packet encoding (for backwards compatibility)
  defp send_hardcoded_packets(state, values) do
    # Group by packet and encode
    packets = group_and_encode_legacy(values, state.target_id, state.step)

    Enum.each(packets, fn binary ->
      send_packet(state, binary)
    end)

    state
  end

  defp group_and_encode_legacy(values, target_id, step) do
    # Group by packet name
    by_packet =
      Enum.group_by(values, fn {qualified_name, _} ->
        case String.split(qualified_name, ".", parts: 2) do
          [packet_name, _] -> packet_name
          _ -> "UNKNOWN"
        end
      end)

    # Encode each packet
    Enum.flat_map(by_packet, fn {packet_name, items} ->
      item_values =
        Enum.into(items, %{}, fn {qualified, value} ->
          [_, item] = String.split(qualified, ".", parts: 2)
          {item, value}
        end)

      case encode_legacy_packet(packet_name, target_id, item_values, step) do
        nil -> []
        binary -> [binary]
      end
    end)
  end

  # Legacy encoding for known packet types
  defp encode_legacy_packet("HEALTH", target_id, data, _step) do
    timestamp = System.system_time(:second)
    target_hash = :erlang.phash2(target_id, 65_536)

    secondary_header = <<timestamp::48, target_hash::16>>

    cpu_temp = Map.get(data, "cpu_temp", 25.0)
    battery_voltage = Map.get(data, "battery_voltage", 14.5)
    battery_current = Map.get(data, "battery_current", 2.3)
    battery_percentage = Map.get(data, "battery_percentage", 75.0)
    uptime = Map.get(data, "uptime_seconds", 0)
    memory = Map.get(data, "memory_used_mb", 512)

    user_data = <<
      cpu_temp::float-32,
      battery_voltage::float-32,
      battery_current::float-32,
      trunc(battery_percentage)::8,
      uptime::32,
      memory::16
    >>

    build_ccsds(100, secondary_header <> user_data)
  end

  defp encode_legacy_packet("ATTITUDE", target_id, data, _step) do
    timestamp = System.system_time(:second)
    target_hash = :erlang.phash2(target_id, 65_536)

    secondary_header = <<timestamp::48, target_hash::16>>

    roll = Map.get(data, "roll", 0.0)
    pitch = Map.get(data, "pitch", 0.0)
    yaw = Map.get(data, "yaw", 0.0)
    roll_rate = Map.get(data, "roll_rate", 0.0)
    pitch_rate = Map.get(data, "pitch_rate", 0.0)
    yaw_rate = Map.get(data, "yaw_rate", 0.0)

    user_data = <<
      roll::float-32,
      pitch::float-32,
      yaw::float-32,
      roll_rate::float-32,
      pitch_rate::float-32,
      yaw_rate::float-32
    >>

    build_ccsds(101, secondary_header <> user_data)
  end

  defp encode_legacy_packet("POWER", target_id, data, _step) do
    timestamp = System.system_time(:second)
    target_hash = :erlang.phash2(target_id, 65_536)

    secondary_header = <<timestamp::48, target_hash::16>>

    solar_voltage = Map.get(data, "solar_panel_voltage", 28.0)
    solar_current = Map.get(data, "solar_panel_current", 5.0)
    bus_voltage = Map.get(data, "bus_voltage", 27.5)
    bus_current = Map.get(data, "bus_current", 3.2)

    power_mode =
      case Map.get(data, "power_mode", "NOMINAL") do
        "NOMINAL" -> 0
        "BATTERY" -> 1
        "CHARGING" -> 2
        _ -> 255
      end

    user_data = <<
      solar_voltage::float-32,
      solar_current::float-32,
      bus_voltage::float-32,
      bus_current::float-32,
      power_mode::8
    >>

    build_ccsds(102, secondary_header <> user_data)
  end

  defp encode_legacy_packet(packet_name, _target_id, _data, _step) do
    Logger.warning("Unknown packet type for legacy encoding: #{packet_name}")
    nil
  end

  defp build_ccsds(apid, payload) do
    import Bitwise

    sync = <<0x1A, 0xCF, 0xFC, 0x1D>>

    version = 0
    type = 0
    sec_hdr_flag = 1
    packet_id = version <<< 13 ||| type <<< 12 ||| sec_hdr_flag <<< 11 ||| apid

    sequence_flags = 3
    sequence_count = 0
    seq_control = sequence_flags <<< 14 ||| sequence_count

    data_length = byte_size(payload) - 1

    primary_header = <<packet_id::16, seq_control::16, data_length::16>>

    sync <> primary_header <> payload
  end

  defp send_packet(%{socket: nil}, _binary), do: :ok

  defp send_packet(%{output: {:tcp, _, _}, socket: socket}, binary) do
    case :gen_tcp.send(socket, binary) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("TCP send failed: #{inspect(reason)}")
    end
  end

  defp send_packet(%{output: {:udp, host, port}, socket: socket}, binary) do
    case :gen_udp.send(socket, String.to_charlist(host), port, binary) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("UDP send failed: #{inspect(reason)}")
    end
  end

  defp send_packet(_, _), do: :ok

  defp format_output(nil), do: "none"
  defp format_output({:tcp, host, port}), do: "tcp:#{host}:#{port}"
  defp format_output({:udp, host, port}), do: "udp:#{host}:#{port}"
  defp format_output(other), do: inspect(other)
end
