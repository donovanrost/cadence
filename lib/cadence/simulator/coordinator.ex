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
  - `:definitions_path` - Path to YAML packet definitions (required)
  - `:scenario_path` - Path to scenario file (for ScenarioProvider)

  ## Parallel Mode Options

  - `:parallel_mode` - `:sequential` (default) or `:parallel`
  - `:generator_count` - Number of worker processes (default: System.schedulers_online())
  - `:send_batch_timeout` - Batch flush interval in ms (default: 10)
  - `:send_batch_size` - Batch flush size in bytes (default: 32768)
  """

  use GenServer

  require Logger

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.Uplink.Pipeline, as: UplinkPipeline

  alias Cadence.Simulator.{
    GeneratorWorker,
    PacketEncoder,
    SendBuffer,
    SequenceAllocator,
    SimulatorMetrics
  }

  alias Cadence.Simulator.Providers.{BasicDynamics, DatabaseDynamics, ScenarioProvider}

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
    :uplink_pipeline,
    :uplink_opts,
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
    frame = Keyword.get(opts, :frame)
    {uplink_pipeline, uplink_opts} = init_uplink_pipeline(frame)

    # Determine provider based on options
    {provider_module, provider_config} = determine_provider(opts)

    with {:ok, provider_state} <- provider_module.init(provider_config),
         {:ok, encoder} <- require_encoder(opts),
         {:ok, state} <-
           build_state(%{
             mission_id: mission_id,
             target_id: target_id,
             provider_module: provider_module,
             provider_state: provider_state,
             encoder: encoder,
             output: output,
             rate_hz: rate_hz,
             frame: frame,
             uplink_pipeline: uplink_pipeline,
             uplink_opts: uplink_opts,
             parallel_mode: parallel_mode,
             opts: opts
           }) do
      Logger.info("""
      Simulator Coordinator started:
        mission_id: #{mission_id}
        target_id: #{target_id}
        provider: #{inspect(provider_module)}
        rate_hz: #{rate_hz}
        output: #{inspect(output)}
        parallel_mode: #{parallel_mode}
        encoder: loaded
        frame: #{inspect(frame)}
        uplink_pipeline: #{if uplink_pipeline, do: "initialized", else: "none (raw packets)"}
      """)

      interval_ms = max(trunc(1000 / rate_hz), 1)
      timer_ref = Process.send_after(self(), :generate, interval_ms)
      {:ok, %{state | timer_ref: timer_ref}}
    else
      {:error, :missing_definitions} ->
        {:stop, {:missing_definitions, "definitions_path is required for simulator output"}}

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
            uplink_opts: state.uplink_opts,
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

  defp require_encoder(opts) do
    case load_encoder(opts) do
      nil -> {:error, :missing_definitions}
      encoder -> {:ok, encoder}
    end
  end

  defp build_state(%{
         mission_id: mission_id,
         target_id: target_id,
         provider_module: provider_module,
         provider_state: provider_state,
         encoder: encoder,
         output: output,
         rate_hz: rate_hz,
         frame: frame,
         uplink_pipeline: uplink_pipeline,
         uplink_opts: uplink_opts,
         parallel_mode: parallel_mode,
         opts: opts
       }) do
    state = %__MODULE__{
      mission_id: mission_id,
      target_id: target_id,
      provider_module: provider_module,
      provider_state: provider_state,
      encoder: encoder,
      output: output,
      rate_hz: rate_hz,
      frame: frame,
      uplink_pipeline: uplink_pipeline,
      uplink_opts: uplink_opts,
      parallel_mode: parallel_mode,
      socket: nil
    }

    state =
      case parallel_mode do
        :parallel -> init_parallel_mode(state, opts)
        :sequential -> connect_output(state)
      end

    {:ok, state}
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

        worker_index = rem(step, worker_count)
        worker = Enum.at(acc_state.generator_pool, worker_index)
        GeneratorWorker.generate(worker, step)
        acc_state
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
    {values, provider_state} =
      case state.provider_module.generate_values(state.provider_state, state.step) do
        {:ok, values, next_state} ->
          {values, next_state}

        {:error, reason, next_state} ->
          Logger.error("Provider error: #{inspect(reason)}")
          {%{}, next_state}
      end

    state = send_telemetry(state, values)

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

  defp send_telemetry(%{encoder: encoder} = state, values) do
    # Use encoder for proper packet construction
    {:ok, packets, updated_encoder} = PacketEncoder.encode(encoder, state.target_id, values)

    state =
      Enum.reduce(packets, state, fn {_packet_name, binary}, acc_state ->
        send_packet(acc_state, binary)
      end)

    %{state | encoder: updated_encoder}
  end

  defp send_packet(state, binary) do
    {processed_packet, state} = encode_uplink(state, binary)
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

  defp init_uplink_pipeline(nil) do
    Logger.debug("init_uplink_pipeline: frame is nil, no TM framing")
    {nil, nil}
  end

  defp init_uplink_pipeline(%{format: :tm} = frame) do
    opts = [
      profile: :tm,
      frame_size: frame.frame_size,
      uplink_scid: frame.scid,
      uplink_vcid: frame.vcid
    ]

    case UplinkPipeline.init(opts) do
      {:ok, pipeline} ->
        Logger.debug("init_uplink_pipeline: TM pipeline initialized successfully")
        {pipeline, opts}

      {:error, reason} ->
        Logger.warning("init_uplink_pipeline: TM pipeline failed to init: #{inspect(reason)}")
        {nil, nil}
    end
  end

  defp init_uplink_pipeline(other) do
    Logger.debug("init_uplink_pipeline: unrecognized frame format: #{inspect(other)}")
    {nil, nil}
  end

  defp format_output(nil), do: "none"
  defp format_output({:tcp, host, port}), do: "tcp:#{host}:#{port}"
  defp format_output({:udp, host, port}), do: "udp:#{host}:#{port}"
  defp format_output(other), do: inspect(other)
end
