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

      # Start in parallel mode for high throughput
      {:ok, pid} = Coordinator.start_link(
        mission_id: "mission-123",
        target_id: "SIM-1",
        output: {:tcp, "localhost", 9999},
        rate_hz: 10000.0,
        parallel_mode: :parallel,
        generator_count: 8
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

  ## Parallel Mode Options

  - `:parallel_mode` - `:sequential` (default) or `:parallel`
  - `:generator_count` - Number of worker processes (default: System.schedulers_online())
  - `:send_batch_timeout` - Batch flush interval in ms (default: 10)
  - `:send_batch_size` - Batch flush size in bytes (default: 32768)
  """

  use GenServer

  require Logger

  alias Cadence.Simulator.{
    GeneratorWorker,
    PacketEncoder,
    SendBuffer,
    SequenceAllocator,
    SimulatorMetrics
  }

  alias Cadence.Simulator.Providers.{BasicDynamics, DatabaseDynamics, ScenarioProvider}
  alias Cadence.Protocols.CCSDS.TMFrameProtocol
  alias Cadence.Telemetry.ProtocolChain.Processor

  @default_rate_hz 1.0
  @default_target_id "SIM-1"
  @default_generator_count System.schedulers_online()
  @default_send_batch_timeout 10
  @default_send_batch_size 32_768

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
    :frame,
    :write_chain,
    :write_chain_configs,
    :oid_lfsr_by_vcid,
    # Parallel mode fields
    :parallel_mode,
    :generator_pool,
    :sequence_allocator,
    :send_buffer,
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
    parallel_mode = Keyword.get(opts, :parallel_mode, :sequential)
    frame = configure_oid(Keyword.get(opts, :frame), rate_hz)
    write_chain_configs = build_write_chain_configs(frame)
    write_chain = init_write_chain(write_chain_configs)

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
          frame: frame,
          write_chain: write_chain,
          write_chain_configs: write_chain_configs,
          oid_lfsr_by_vcid: %{},
          parallel_mode: parallel_mode,
          socket: nil
        }

        # Initialize based on parallel mode
        state =
          case parallel_mode do
            :parallel ->
              init_parallel_mode(state, opts)

            :sequential ->
              # Connect output for sequential mode
              connect_output(state)
          end

        Logger.info("""
        Simulator Coordinator started:
          mission_id: #{mission_id}
          target_id: #{target_id}
          provider: #{inspect(provider_module)}
          rate_hz: #{rate_hz}
          output: #{inspect(output)}
          parallel_mode: #{parallel_mode}
          encoder: #{if encoder, do: "loaded", else: "none (using hardcoded encoding)"}
        """)

        # Schedule first generation
        interval_ms = max(trunc(1000 / rate_hz), 1)
        timer_ref = Process.send_after(self(), :generate, interval_ms)

        {:ok, %{state | timer_ref: timer_ref}}

      {:error, reason} ->
        {:stop, {:provider_init_failed, reason}}
    end
  end

  # Initialize parallel mode with workers, send buffer, and sequence allocator
  defp init_parallel_mode(state, opts) do
    generator_count = Keyword.get(opts, :generator_count, @default_generator_count)
    batch_timeout = Keyword.get(opts, :send_batch_timeout, @default_send_batch_timeout)
    batch_size = Keyword.get(opts, :send_batch_size, @default_send_batch_size)

    # Initialize metrics
    SimulatorMetrics.init(state.mission_id)

    # Create sequence allocator with known APIDs
    apids =
      if state.encoder do
        PacketEncoder.apids(state.encoder)
      else
        [100, 101, 102]
      end

    sequence_allocator = SequenceAllocator.new(apids)

    # Start send buffer
    {:ok, send_buffer} =
      SendBuffer.start_link(
        output: state.output,
        batch_timeout: batch_timeout,
        batch_size: batch_size
      )

    # Start generator workers
    generator_pool =
      for worker_id <- 0..(generator_count - 1) do
        {:ok, pid} =
          GeneratorWorker.start_link(
            worker_id: worker_id,
            coordinator_id: state.mission_id,
            provider_module: state.provider_module,
            provider_state: state.provider_state,
            encoder: state.encoder,
            target_id: state.target_id,
            write_chain_configs: state.write_chain_configs,
            sequence_allocator: sequence_allocator,
            send_buffer: send_buffer,
            name: nil
          )

        pid
      end

    Logger.info("Started #{generator_count} generator workers for parallel mode")

    %{
      state
      | sequence_allocator: sequence_allocator,
        send_buffer: send_buffer,
        generator_pool: generator_pool
    }
  end

  @impl true
  def handle_info(:generate, %{parallel_mode: :parallel} = state) do
    # Parallel mode: dispatch to workers in round-robin
    # Use burst mode for high rates (>1000 Hz) - dispatch multiple steps per tick
    worker_count = length(state.generator_pool)

    {steps_per_tick, interval_ms} =
      if state.rate_hz <= 1000 do
        # Standard mode: 1 step per interval
        {1, max(trunc(1000 / state.rate_hz), 1)}
      else
        # Burst mode: multiple steps per 1ms tick
        {ceil(state.rate_hz / 1000), 1}
      end

    # Dispatch steps to workers (or emit OID frames)
    state =
      Enum.reduce(0..(steps_per_tick - 1), state, fn offset, acc_state ->
        step = acc_state.step + offset

        if oid_due?(acc_state, step) do
          {updated_state, _sent} = send_oid_frame(acc_state)
          updated_state
        else
          worker_index = rem(step, worker_count)
          worker = Enum.at(acc_state.generator_pool, worker_index)
          GeneratorWorker.generate(worker, step)
          acc_state
        end
      end)

    # Schedule next tick
    timer_ref = Process.send_after(self(), :generate, interval_ms)

    new_state = %{
      state
      | timer_ref: timer_ref,
        step: state.step + steps_per_tick,
        packet_count: state.packet_count + steps_per_tick
    }

    {:noreply, new_state}
  end

  def handle_info(:generate, state) do
    # Sequential mode: original behavior
    {state, provider_state} =
      if oid_due?(state, state.step) do
        {updated_state, _sent} = send_oid_frame(state)
        {updated_state, state.provider_state}
      else
        # Generate values from provider
        {values, new_state} =
          case state.provider_module.generate_values(state.provider_state, state.step) do
            {:ok, values, next_state} ->
              {values, next_state}

            {:error, reason, next_state} ->
              Logger.error("Provider error: #{inspect(reason)}")
              {%{}, next_state}
          end

        {send_telemetry(state, values), new_state}
      end

    # Schedule next generation
    interval_ms = max(trunc(1000 / state.rate_hz), 1)
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
    base_stats = %{
      mission_id: state.mission_id,
      target_id: state.target_id,
      provider: state.provider_module,
      rate_hz: state.rate_hz,
      step: state.step,
      packet_count: state.packet_count,
      uptime_seconds: state.step / max(state.rate_hz, 0.001),
      output: format_output(state.output),
      encoder_loaded: state.encoder != nil,
      parallel_mode: state.parallel_mode
    }

    # Add parallel mode specific stats
    stats =
      case state.parallel_mode do
        :parallel ->
          parallel_stats = %{
            generator_count: length(state.generator_pool),
            send_buffer_stats: SendBuffer.stats(state.send_buffer),
            metrics: SimulatorMetrics.get_stats(state.mission_id)
          }

          Map.merge(base_stats, parallel_stats)

        :sequential ->
          base_stats
      end

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

    # Clean up based on mode
    case state.parallel_mode do
      :parallel -> cleanup_parallel(state)
      :sequential -> cleanup_sequential(state)
    end

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :simulator_coordinator}}}
  end

  defp cleanup_parallel(state) do
    stop_generator_pool(state.generator_pool)
    stop_send_buffer(state.send_buffer)
    SimulatorMetrics.cleanup(state.mission_id)
  end

  defp stop_generator_pool(nil), do: :ok

  defp stop_generator_pool(generator_pool) do
    Enum.each(generator_pool, fn pid ->
      if Process.alive?(pid), do: GeneratorWorker.stop(pid)
    end)
  end

  defp stop_send_buffer(nil), do: :ok

  defp stop_send_buffer(send_buffer) do
    if Process.alive?(send_buffer), do: SendBuffer.stop(send_buffer)
  end

  defp cleanup_sequential(state) do
    if state.socket, do: close_socket(state)
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
  defp connect_output(%{output: :pubsub} = state), do: state

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
  defp close_socket(%{output: :pubsub}), do: :ok
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
    {:ok, packets, updated_encoder} = PacketEncoder.encode(encoder, state.target_id, values)

    state =
      Enum.reduce(packets, state, fn {_packet_name, binary}, acc_state ->
        send_packet(acc_state, binary)
      end)

    %{state | encoder: updated_encoder}
  end

  # Legacy hardcoded packet encoding (for backwards compatibility)
  defp send_hardcoded_packets(state, values) do
    # Group by packet and encode
    packets = group_and_encode_legacy(values, state.target_id, state.step)

    Enum.reduce(packets, state, fn binary, acc_state ->
      send_packet(acc_state, binary)
    end)
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

  defp send_packet(state, binary) do
    {processed_packet, state} = process_write_chain(state, binary)
    send_frame(state, processed_packet)
    state
  end

  defp send_frame(%{parallel_mode: :parallel, send_buffer: send_buffer}, frame_binary) do
    SendBuffer.send_packet(send_buffer, frame_binary)
  end

  defp send_frame(%{output: {:tcp, _, _}, socket: socket}, frame_binary) do
    case :gen_tcp.send(socket, frame_binary) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("TCP send failed: #{inspect(reason)}")
    end
  end

  defp send_frame(%{output: {:udp, host, port}, socket: socket}, frame_binary) do
    case :gen_udp.send(socket, String.to_charlist(host), port, frame_binary) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("UDP send failed: #{inspect(reason)}")
    end
  end

  defp send_frame(_, _frame_binary), do: :ok

  defp process_write_chain(%{write_chain: nil} = state, packet), do: {packet, state}
  defp process_write_chain(%{write_chain: []} = state, packet), do: {packet, state}

  defp process_write_chain(%{write_chain: write_chain} = state, packet) do
    case Processor.process_write(write_chain, packet) do
      {:ok, encoded_packet, updated_chain} ->
        {encoded_packet, %{state | write_chain: updated_chain}}

      {:error, reason} ->
        Logger.warning("Write chain processing failed: #{inspect(reason)}, sending raw packet")
        {packet, state}
    end
  end

  defp configure_oid(nil, _rate_hz), do: nil

  defp configure_oid(%{format: :tm} = frame, rate_hz) do
    case Map.get(frame, :oid_rate_hz) do
      nil ->
        frame

      oid_rate when is_number(oid_rate) and oid_rate > 0 ->
        Map.put(frame, :oid_every, oid_every(rate_hz, oid_rate))

      _ ->
        frame
    end
  end

  defp configure_oid(frame, _rate_hz), do: frame

  defp oid_every(rate_hz, oid_rate_hz) do
    rate_hz = max(rate_hz, 0.001)
    oid_rate_hz = min(oid_rate_hz, rate_hz)
    interval = rate_hz / oid_rate_hz
    max(round(interval), 1)
  end

  defp oid_due?(%{frame: %{format: :tm, oid_every: oid_every}}, step)
       when is_integer(oid_every) do
    if oid_every == 1 do
      true
    else
      step > 0 and rem(step, oid_every) == 0
    end
  end

  defp oid_due?(_state, _step), do: false

  defp send_oid_frame(%{frame: %{format: :tm} = frame} = state) do
    pn_state = Map.get(state.oid_lfsr_by_vcid, frame.vcid)

    {updated_chain, result} =
      update_tm_frame_in_chain(state.write_chain, fn tm_state ->
        TMFrameProtocol.encode_oid(tm_state, pn_state)
      end)

    case result do
      {oid_frame, next_tm_state, next_pn_state} ->
        updated_state = %{
          state
          | write_chain: updated_chain,
            oid_lfsr_by_vcid: Map.put(state.oid_lfsr_by_vcid, next_tm_state.vcid, next_pn_state)
        }

        send_frame(updated_state, oid_frame)
        {updated_state, :ok}

      nil ->
        {state, :ok}
    end
  end

  defp send_oid_frame(state), do: {state, :ok}

  defp update_tm_frame_in_chain(nil, _fun), do: {nil, nil}

  defp update_tm_frame_in_chain(write_chain, fun) do
    Enum.map_reduce(write_chain, nil, fn
      {TMFrameProtocol, tm_state}, nil ->
        {frame, next_tm_state, next_pn_state} = fun.(tm_state)
        {{TMFrameProtocol, next_tm_state}, {frame, next_tm_state, next_pn_state}}

      entry, acc ->
        {entry, acc}
    end)
  end

  defp build_write_chain_configs(nil), do: nil

  defp build_write_chain_configs(%{format: :tm} = frame) do
    [
      {"tm_frame",
       %{
         frame_size: frame.frame_size,
         scid: frame.scid,
         vcid: frame.vcid
       }}
    ]
  end

  defp init_write_chain(nil), do: nil
  defp init_write_chain(configs), do: Processor.clone_chain(configs)

  defp format_output(nil), do: "none"
  defp format_output({:tcp, host, port}), do: "tcp:#{host}:#{port}"
  defp format_output({:udp, host, port}), do: "udp:#{host}:#{port}"
  defp format_output(other), do: inspect(other)
end
