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
  - `:clcw_overrides` - Map of CLCW fields to override (requires `clcw_enabled`)
  - `:clcw_schedule` - List of `%{at: step, overrides: %{...}}` entries
  - `:uplink_drop_every` - Drop every Nth uplink frame (simulated loss)

  ## Parallel Mode Options

  - `:parallel_mode` - `:sequential` (default) or `:parallel`
  - `:generator_count` - Number of worker processes (default: System.schedulers_online())
  - `:send_batch_timeout` - Batch flush interval in ms (default: 10)
  - `:send_batch_size` - Batch flush size in bytes (default: 32768)
  """

  use GenServer

  require Logger

  alias Cadence.CCSDS.SDLP.Metrics
  alias Cadence.CCSDS.SDLP.TM.FrameCodec, as: TMFrameCodec
  alias Cadence.CCSDS.TC.TransferFrame
  alias Cadence.CCSDS.Transport.COP1.{CLCW, FARM}
  alias Cadence.CCSDS.Uplink.Pipeline, as: UplinkPipeline

  alias Cadence.Simulator.{
    COP1.CLCWInjector,
    GeneratorWorker,
    PacketEncoder,
    SendBuffer,
    SequenceAllocator,
    SimulatorMetrics,
    UplinkRuntime
  }

  alias Cadence.Simulator.Providers.{BasicDynamics, DatabaseDynamics, ScenarioProvider}
  alias Cadence.Time.Timer, as: TimeTimer

  @default_rate_hz 1.0
  @default_target_id "SIM-1"
  @default_generator_count System.schedulers_online()
  @default_send_batch_timeout 10
  @default_send_batch_size 32_768
  @default_in_flight_multiplier 4
  @default_send_buffer_queue_floor 16
  @default_dispatch_batch_floor 4
  @default_dispatch_batch_ceiling 32

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
    :uplink_frame,
    :uplink_pipeline,
    :uplink_opts,
    :uplink_ctx_base,
    :uplink_encode_opts,
    :uplink_sdu_base,
    :clcw_enabled,
    :clcw_injector,
    :farm,
    :uplink_buffer,
    :mode,
    :listener,
    :uplink_drop_every,
    # Parallel mode fields
    :parallel_mode,
    :generator_pool,
    :sequence_allocator,
    :send_buffer,
    :max_in_flight_steps,
    :max_send_buffer_queue,
    :dispatch_batch_floor,
    :dispatch_batch_ceiling,
    :send_buffer_queue_len,
    :send_buffer_backlog_bytes,
    :send_buffer_status_version,
    :idle_workers,
    in_flight_steps: 0,
    backpressure_events: 0,
    dispatch_cursor: 0,
    next_step: 0,
    pending_steps: 0,
    step: 0,
    packet_count: 0,
    uplink_seen: 0
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
    requested_parallel_mode = Keyword.get(opts, :parallel_mode, :sequential)
    mode = Keyword.get(opts, :mode, :connect)
    frame = Keyword.get(opts, :frame)
    uplink_frame = Keyword.get(opts, :uplink_frame)
    {uplink_pipeline, uplink_opts} = init_uplink_pipeline(frame)
    clcw_enabled = Keyword.get(opts, :clcw_enabled, false)
    clcw_injector = build_clcw_injector(opts, clcw_enabled)

    uplink_drop_value =
      Keyword.get(opts, :uplink_drop_every) || Keyword.get(opts, :drop_uplink_every)

    uplink_drop_every = parse_uplink_drop(uplink_drop_value)

    # Determine provider based on options
    {provider_module, provider_config} = determine_provider(opts)

    parallel_mode =
      normalize_parallel_mode(requested_parallel_mode, provider_module, provider_config)

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
             uplink_frame: uplink_frame,
             uplink_pipeline: uplink_pipeline,
             uplink_opts: uplink_opts,
             clcw_enabled: clcw_enabled,
             clcw_injector: clcw_injector,
             parallel_mode: parallel_mode,
             mode: mode,
             uplink_drop_every: uplink_drop_every,
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
        connection_mode: #{mode}
        encoder: loaded
        frame: #{inspect(frame)}
        uplink_pipeline: #{if uplink_pipeline, do: "initialized", else: "none (raw packets)"}
      """)

      interval_ms = max(trunc(1000 / rate_hz), 1)
      timer_ref = TimeTimer.send_after(self(), :generate, interval_ms)
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
    generator_count =
      opts
      |> Keyword.get(:generator_count, @default_generator_count)
      |> normalize_generator_count()

    batch_timeout = Keyword.get(opts, :send_batch_timeout, @default_send_batch_timeout)
    batch_size = Keyword.get(opts, :send_batch_size, @default_send_batch_size)
    steps_per_tick = parallel_steps_per_tick(state.rate_hz)
    max_in_flight_steps = normalize_max_in_flight_steps(opts, generator_count, steps_per_tick)
    max_send_buffer_queue = normalize_max_send_buffer_queue(opts, generator_count)
    dispatch_batch_floor = normalize_dispatch_batch_floor(opts)

    dispatch_batch_ceiling =
      normalize_dispatch_batch_ceiling(opts, dispatch_batch_floor, steps_per_tick)

    state =
      if state.mode == :listen do
        connect_output(state)
      else
        state
      end

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
        batch_size: batch_size,
        coordinator_pid: self(),
        mode: state.mode
      )

    # Start generator workers
    generator_pool =
      for worker_id <- 0..(generator_count - 1) do
        {:ok, pid} =
          GeneratorWorker.start_link(
            worker_id: worker_id,
            coordinator_id: state.mission_id,
            coordinator_pid: self(),
            provider_module: state.provider_module,
            provider_state: state.provider_state,
            encoder: state.encoder,
            target_id: state.target_id,
            uplink_opts: state.uplink_opts,
            sequence_allocator: sequence_allocator,
            send_buffer: send_buffer,
            clcw_enabled: state.clcw_enabled,
            clcw_injector: state.clcw_injector,
            name: nil
          )

        pid
      end

    Logger.info("Started #{generator_count} generator workers for parallel mode")

    %{
      state
      | sequence_allocator: sequence_allocator,
        send_buffer: send_buffer,
        generator_pool: generator_pool,
        idle_workers: Enum.to_list(0..(generator_count - 1)),
        max_in_flight_steps: max_in_flight_steps,
        max_send_buffer_queue: max_send_buffer_queue,
        dispatch_batch_floor: dispatch_batch_floor,
        dispatch_batch_ceiling: dispatch_batch_ceiling,
        send_buffer_queue_len: 0,
        send_buffer_backlog_bytes: 0,
        send_buffer_status_version: 0
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
         uplink_frame: uplink_frame,
         uplink_pipeline: uplink_pipeline,
         uplink_opts: uplink_opts,
         clcw_enabled: clcw_enabled,
         clcw_injector: clcw_injector,
         parallel_mode: parallel_mode,
         mode: mode,
         uplink_drop_every: uplink_drop_every,
         opts: opts
       }) do
    uplink_runtime = UplinkRuntime.build(uplink_opts, nil)

    state = %__MODULE__{
      mission_id: mission_id,
      target_id: target_id,
      provider_module: provider_module,
      provider_state: provider_state,
      encoder: encoder,
      output: output,
      rate_hz: rate_hz,
      frame: frame,
      uplink_frame: uplink_frame,
      uplink_pipeline: uplink_pipeline,
      uplink_opts: uplink_opts,
      uplink_ctx_base: uplink_runtime.ctx_base,
      uplink_encode_opts: uplink_runtime.encode_opts,
      uplink_sdu_base: uplink_runtime.sdu_base,
      clcw_enabled: clcw_enabled,
      clcw_injector: clcw_injector,
      farm: init_farm(clcw_enabled, frame),
      uplink_buffer: <<>>,
      parallel_mode: parallel_mode,
      mode: mode,
      uplink_drop_every: uplink_drop_every,
      listener: nil,
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
    steps_per_tick = parallel_steps_per_tick(state.rate_hz)
    interval_ms = parallel_interval_ms(state.rate_hz)

    # Schedule next tick
    timer_ref = TimeTimer.send_after(self(), :generate, interval_ms)

    new_state =
      state
      |> add_dispatch_budget(steps_per_tick)
      |> dispatch_parallel_batches()
      |> Map.put(:timer_ref, timer_ref)

    {:noreply, new_state}
  end

  def handle_info(
        {:generator_batch_complete, worker_id, dispatched_steps, generated_steps, _packet_count,
         buffer_status},
        %{parallel_mode: :parallel} = state
      ) do
    new_state =
      state
      |> maybe_apply_send_buffer_status(buffer_status)
      |> complete_parallel_batch(worker_id, dispatched_steps, generated_steps)
      |> dispatch_parallel_batches()

    {:noreply, new_state}
  end

  def handle_info(
        {:send_buffer_status, status_version, packets_buffered, buffer_bytes},
        %{parallel_mode: :parallel} = state
      ) do
    new_state =
      state
      |> maybe_apply_send_buffer_status(%{
        status_version: status_version,
        packets_buffered: packets_buffered,
        buffer_bytes: buffer_bytes
      })
      |> dispatch_parallel_batches()

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

    state = send_telemetry(state, values, state.step)

    # Schedule next generation
    interval_ms = max(trunc(1000 / state.rate_hz), 1)
    timer_ref = TimeTimer.send_after(self(), :generate, interval_ms)

    new_state = %{
      state
      | provider_state: provider_state,
        timer_ref: timer_ref,
        step: state.step + 1,
        packet_count: state.packet_count + 1
    }

    {:noreply, new_state}
  end

  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    {frames, buffer} = decode_uplink_frames(state, data)
    state = Enum.reduce(frames, state, &handle_uplink_frame/2)
    maybe_set_active_once(state)
    {:noreply, %{state | uplink_buffer: buffer}}
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    Logger.warning("Simulator uplink socket closed")
    state = maybe_detach_send_buffer(state)
    {:noreply, %{state | socket: nil}}
  end

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    Logger.warning("Simulator uplink socket error: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info(:accept, %{listener: nil} = state), do: {:noreply, state}

  def handle_info(:accept, %{listener: listener} = state) do
    case :gen_tcp.accept(listener, 100) do
      {:ok, socket} ->
        state = handle_client_accept(state, socket)
        send(self(), :accept)
        {:noreply, state}

      {:error, :timeout} ->
        send(self(), :accept)
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Simulator accept error: #{inspect(reason)}")
        TimeTimer.send_after(self(), :accept, 1000)
        {:noreply, state}
    end
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
      parallel_mode: state.parallel_mode,
      connection_mode: state.mode,
      uplink_frame: state.uplink_frame,
      clcw_enabled: state.clcw_enabled,
      sdlp_metrics: Metrics.get_stats(state.mission_id)
    }

    # Add parallel mode specific stats
    stats =
      case state.parallel_mode do
        :parallel ->
          parallel_stats = %{
            generator_count: length(state.generator_pool),
            in_flight_steps: state.in_flight_steps,
            max_in_flight_steps: state.max_in_flight_steps,
            dispatch_batch_floor: state.dispatch_batch_floor,
            dispatch_batch_ceiling: state.dispatch_batch_ceiling,
            pending_steps: state.pending_steps,
            next_step: state.next_step,
            max_send_buffer_queue: state.max_send_buffer_queue,
            send_buffer_queue_len: state.send_buffer_queue_len,
            send_buffer_backlog_bytes: state.send_buffer_backlog_bytes,
            backpressure_events: state.backpressure_events,
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
    if state.timer_ref, do: TimeTimer.cancel(state.timer_ref)

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
    Metrics.cleanup(state.mission_id)
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
    if state.listener, do: close_listener(state)
    Metrics.cleanup(state.mission_id)
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
        config = provider_config(provider, opts)
        {provider, config}

      # Default to BasicDynamics
      true ->
        config = Keyword.get(opts, :provider_config, %{})
        {BasicDynamics, config}
    end
  end

  defp provider_config(DatabaseDynamics, opts) do
    %{
      definitions_path: Keyword.get(opts, :definitions_path),
      noise_amplitude: Keyword.get(opts, :noise_amplitude, 1.0)
    }
  end

  defp provider_config(ScenarioProvider, opts) do
    cond do
      scenario_path = Keyword.get(opts, :scenario_path) ->
        %{scenario_path: scenario_path}

      scenario = Keyword.get(opts, :scenario) ->
        %{scenario: scenario}

      true ->
        Keyword.get(opts, :provider_config, %{})
    end
  end

  defp provider_config(_provider, opts), do: Keyword.get(opts, :provider_config, %{})

  defp normalize_parallel_mode(:parallel, provider_module, provider_config) do
    if provider_parallel_safe?(provider_module, provider_config) do
      :parallel
    else
      Logger.warning(
        "Provider #{inspect(provider_module)} is not parallel-safe; falling back to sequential mode"
      )

      :sequential
    end
  end

  defp normalize_parallel_mode(mode, _provider_module, _provider_config), do: mode

  defp provider_parallel_safe?(provider_module, provider_config) do
    if function_exported?(provider_module, :parallel_safe?, 1) do
      provider_module.parallel_safe?(provider_config)
    else
      provider_module != ScenarioProvider
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

  defp build_clcw_injector(_opts, false), do: nil

  defp build_clcw_injector(opts, true) do
    CLCWInjector.new(
      overrides: Keyword.get(opts, :clcw_overrides, %{}),
      schedule: Keyword.get(opts, :clcw_schedule, [])
    )
  end

  defp parse_uplink_drop(value) do
    case parse_integer(value) do
      value when is_integer(value) and value > 0 -> value
      _ -> nil
    end
  end

  defp connect_output(%{output: nil} = state), do: state
  defp connect_output(%{output: :pubsub} = state), do: state

  defp connect_output(%{mode: :listen, output: {:tcp, host, port}} = state) do
    listen_output(state, host, port)
  end

  defp connect_output(%{mode: :listen, output: {:udp, _, _}} = state) do
    Logger.warning("Listen mode does not support UDP output")
    state
  end

  defp connect_output(%{output: {:tcp, host, port}} = state) do
    active = if state.clcw_enabled, do: :once, else: false

    opts = [
      :binary,
      active: active,
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

  defp close_listener(%{listener: nil}), do: :ok
  defp close_listener(%{listener: listener}), do: :gen_tcp.close(listener)

  defp send_telemetry(state, values, _step) when map_size(values) == 0, do: state

  defp send_telemetry(%{encoder: encoder} = state, values, step) do
    # Use encoder for proper packet construction
    {:ok, packets, updated_encoder} = PacketEncoder.encode(encoder, state.target_id, values)

    state =
      Enum.reduce(packets, state, fn {_packet_name, binary}, acc_state ->
        send_packet(acc_state, binary, step)
      end)

    %{state | encoder: updated_encoder}
  end

  defp send_packet(state, binary, step) do
    {processed_packet, state} = encode_uplink(state, binary, step)
    send_frame(state, processed_packet)
    state
  end

  defp send_frame(%{parallel_mode: :parallel, send_buffer: send_buffer}, frame_data) do
    SendBuffer.send_packet(send_buffer, frame_data)
  end

  defp send_frame(%{output: {:tcp, _, _}, socket: nil}, _frame_data), do: :ok

  defp send_frame(%{output: {:tcp, _, _}, socket: socket}, frame_data) do
    case :gen_tcp.send(socket, frame_data) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("TCP send failed: #{inspect(reason)}")
    end
  end

  defp send_frame(%{output: {:udp, _, _}, socket: nil}, _frame_data), do: :ok

  defp send_frame(%{output: {:udp, host, port}, socket: socket}, frame_data) do
    case :gen_udp.send(socket, String.to_charlist(host), port, IO.iodata_to_binary(frame_data)) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("UDP send failed: #{inspect(reason)}")
    end
  end

  defp send_frame(_, _frame_data), do: :ok

  defp dispatch_parallel_batches(%{parallel_mode: :parallel} = state) do
    worker_count = length(state.generator_pool)
    {new_state, _dispatched_steps} = dispatch_parallel_batches(state, worker_count)
    new_state
  end

  defp dispatch_parallel_batches(state), do: state

  defp dispatch_parallel_batches(%{pending_steps: pending_steps} = state, worker_count)
       when worker_count <= 0 or pending_steps <= 0 do
    {state, 0}
  end

  defp dispatch_parallel_batches(state, worker_count) do
    if state.send_buffer_queue_len >= state.max_send_buffer_queue do
      {increment_backpressure(state), 0}
    else
      dispatch_available_parallel_batches(state, worker_count)
    end
  end

  defp dispatch_available_parallel_batches(state, worker_count) do
    available_workers = length(state.idle_workers || [])
    available_steps = max(state.max_in_flight_steps - state.in_flight_steps, 0)
    target_steps_per_worker = dispatch_target_steps_per_worker(state)
    dispatch_capacity = min(available_steps, available_workers * target_steps_per_worker)
    steps_to_dispatch = min(state.pending_steps, dispatch_capacity)

    throttled? =
      steps_to_dispatch < state.pending_steps or available_workers <= 0 or available_steps <= 0

    state = maybe_increment_backpressure(state, throttled?)

    if steps_to_dispatch <= 0 or available_workers <= 0 do
      {state, 0}
    else
      dispatch_parallel_work(
        state,
        steps_to_dispatch,
        worker_count,
        available_workers,
        target_steps_per_worker
      )
    end
  end

  defp dispatch_parallel_work(
         state,
         steps_to_dispatch,
         worker_count,
         available_workers,
         target_steps_per_worker
       ) do
    active_workers =
      min(
        min(worker_count, available_workers),
        max(ceil_div(steps_to_dispatch, max(target_steps_per_worker, 1)), 1)
      )

    base_batch_size = div(steps_to_dispatch, active_workers)
    remainder = rem(steps_to_dispatch, active_workers)
    {assigned_worker_ids, remaining_idle_workers} = Enum.split(state.idle_workers, active_workers)

    do_dispatch_parallel_work(
      state.generator_pool,
      assigned_worker_ids,
      state.next_step,
      base_batch_size,
      remainder
    )

    {
      %{
        state
        | idle_workers: remaining_idle_workers,
          dispatch_cursor: rem(state.dispatch_cursor + active_workers, worker_count),
          in_flight_steps: state.in_flight_steps + steps_to_dispatch,
          next_step: state.next_step + steps_to_dispatch,
          pending_steps: max(state.pending_steps - steps_to_dispatch, 0)
      },
      steps_to_dispatch
    }
  end

  defp do_dispatch_parallel_work(
         generator_pool,
         assigned_worker_ids,
         start_step,
         base_batch_size,
         remainder
       ) do
    Enum.reduce(Enum.with_index(assigned_worker_ids), start_step, fn {worker_id, index},
                                                                     next_step ->
      step_count = batch_step_count(index, base_batch_size, remainder)
      worker = Enum.at(generator_pool, worker_id)
      GeneratorWorker.generate_batch(worker, next_step, step_count)
      next_step + step_count
    end)
  end

  defp batch_step_count(index, base_batch_size, remainder) do
    base_batch_size + if(index < remainder, do: 1, else: 0)
  end

  defp dispatch_target_steps_per_worker(state) do
    floor = max(state.dispatch_batch_floor || @default_dispatch_batch_floor, 1)
    ceiling = max(state.dispatch_batch_ceiling || @default_dispatch_batch_ceiling, floor)

    cond do
      send_buffer_utilization(state) >= 0.75 ->
        1

      send_buffer_utilization(state) >= 0.5 ->
        max(div(floor, 2), 1)

      state.pending_steps >= ceiling ->
        ceiling

      state.pending_steps >= floor ->
        floor

      state.pending_steps >= 2 ->
        2

      true ->
        1
    end
  end

  defp send_buffer_utilization(%{max_send_buffer_queue: max_queue}) when max_queue in [nil, 0],
    do: 0.0

  defp send_buffer_utilization(%{
         send_buffer_queue_len: queue_len,
         max_send_buffer_queue: max_queue
       }) do
    queue_len / max(max_queue, 1)
  end

  defp increment_backpressure(state) do
    %{state | backpressure_events: state.backpressure_events + 1}
  end

  defp maybe_increment_backpressure(state, true), do: increment_backpressure(state)
  defp maybe_increment_backpressure(state, false), do: state

  defp add_dispatch_budget(state, steps_per_tick) when steps_per_tick > 0 do
    %{state | pending_steps: state.pending_steps + steps_per_tick}
  end

  defp add_dispatch_budget(state, _steps_per_tick), do: state

  defp complete_parallel_batch(state, worker_id, dispatched_steps, generated_steps) do
    state
    |> Map.merge(%{
      in_flight_steps: max(state.in_flight_steps - dispatched_steps, 0),
      packet_count: state.packet_count + generated_steps,
      step: state.step + dispatched_steps
    })
    |> release_worker(worker_id)
  end

  defp release_worker(%{idle_workers: idle_workers} = state, worker_id)
       when is_integer(worker_id) and is_list(idle_workers) do
    if worker_id in idle_workers do
      state
    else
      %{state | idle_workers: idle_workers ++ [worker_id]}
    end
  end

  defp release_worker(state, _worker_id), do: state

  defp maybe_apply_send_buffer_status(state, nil), do: state

  defp maybe_apply_send_buffer_status(
         state,
         %{
           status_version: status_version,
           packets_buffered: packets_buffered,
           buffer_bytes: buffer_bytes
         }
       )
       when is_integer(status_version) do
    if status_version >= state.send_buffer_status_version do
      %{
        state
        | send_buffer_status_version: status_version,
          send_buffer_queue_len: packets_buffered,
          send_buffer_backlog_bytes: buffer_bytes
      }
    else
      state
    end
  end

  defp parallel_steps_per_tick(rate_hz) when rate_hz <= 1000, do: 1
  defp parallel_steps_per_tick(rate_hz), do: ceil(rate_hz / 1000)

  defp parallel_interval_ms(rate_hz) when rate_hz <= 1000 do
    max(trunc(1000 / rate_hz), 1)
  end

  defp parallel_interval_ms(_rate_hz), do: 1

  defp encode_uplink(%{uplink_pipeline: nil} = state, packet, _step), do: {packet, state}

  defp encode_uplink(
         %{
           uplink_pipeline: pipeline,
           uplink_ctx_base: ctx_base,
           uplink_encode_opts: encode_opts,
           uplink_sdu_base: sdu_base
         } = state,
         packet,
         step
       ) do
    ctx = maybe_put_ocf(ctx_base, state, step)
    sdu = %{sdu_base | octets: packet}

    case UplinkPipeline.encode(sdu, ctx, pipeline, encode_opts) do
      {:ok, encoded, new_pipeline} ->
        {encoded, %{state | uplink_pipeline: new_pipeline}}

      {:error, reason, new_pipeline} ->
        Logger.warning("Uplink pipeline failed: #{inspect(reason)}, sending raw packet")
        {packet, %{state | uplink_pipeline: new_pipeline}}
    end
  end

  defp maybe_put_ocf(
         ctx,
         %{clcw_enabled: true, uplink_opts: opts, farm: %FARM{} = farm, clcw_injector: injector},
         step
       )
       when is_map(ctx) do
    put_ocf(ctx, clcw_binary_from_farm(opts, farm, injector, step))
  end

  defp maybe_put_ocf(ctx, %{clcw_enabled: true, uplink_opts: opts, clcw_injector: injector}, step)
       when is_map(ctx) do
    put_ocf(ctx, clcw_binary_from_step(opts, step, injector))
  end

  defp maybe_put_ocf(ctx, _state, _step), do: ctx

  defp clcw_binary_from_farm(nil, _farm, _injector, _step), do: :skip

  defp clcw_binary_from_farm(opts, farm, injector, step) do
    if Keyword.get(opts, :profile) == :tm do
      farm
      |> FARM.clcw()
      |> maybe_apply_injector(injector, step)
      |> CLCW.encode()
    else
      :skip
    end
  end

  defp clcw_binary_from_step(nil, _step, _injector), do: :skip

  defp clcw_binary_from_step(opts, step, injector) do
    if Keyword.get(opts, :profile) == :tm do
      vcid = opts[:uplink_vcid] || opts[:vcid] || 0
      report_value = rem(step, 256)

      %CLCW{vcid: vcid, report_value: report_value}
      |> maybe_apply_injector(injector, step)
      |> CLCW.encode()
    else
      :skip
    end
  end

  defp maybe_apply_injector(%CLCW{} = clcw, %CLCWInjector{} = injector, step) do
    CLCWInjector.apply(injector, clcw, step)
  end

  defp maybe_apply_injector(clcw, _injector, _step), do: clcw

  defp put_ocf(ctx, {:ok, ocf}) do
    Map.merge(ctx, %{ocf: ocf, ocf_length: byte_size(ocf)})
  end

  defp put_ocf(ctx, {:error, reason}) do
    Logger.warning("Failed to encode CLCW: #{inspect(reason)}")
    ctx
  end

  defp put_ocf(ctx, :skip), do: ctx

  defp decode_uplink_frames(state, data) do
    case uplink_frame_config(state) do
      %{format: :tm, frame_size: frame_size} ->
        decode_tm_uplink(state, data, frame_size)

      %{format: :tc, frame_size: frame_size} ->
        decode_tc_uplink(state, data, frame_size)

      _ ->
        Logger.debug("Uplink frame decode skipped; frame config missing")
        {[], state.uplink_buffer <> data}
    end
  end

  defp decode_tm_uplink(state, data, frame_size) do
    buffer = state.uplink_buffer <> data

    case TMFrameCodec.decode(buffer, frame_size: frame_size, metrics_scope: state.mission_id) do
      {:ok, frames, rest} ->
        {frames, rest}

      other ->
        Logger.warning("Failed to decode TM uplink frames: #{inspect(other)}")
        {[], <<>>}
    end
  end

  defp decode_tc_uplink(state, data, frame_size) do
    buffer = state.uplink_buffer <> data

    case TransferFrame.decode(buffer, frame_size: frame_size) do
      {:ok, frames, rest} ->
        {frames, rest}

      other ->
        Logger.warning("Failed to decode TC uplink frames: #{inspect(other)}")
        {[], <<>>}
    end
  end

  defp uplink_frame_config(%{uplink_frame: nil, frame: frame}), do: frame
  defp uplink_frame_config(%{uplink_frame: uplink_frame}), do: uplink_frame

  defp handle_uplink_frame(%{frame_seq: seq, vcid: vcid}, %{farm: %FARM{} = farm} = state)
       when is_integer(seq) do
    {state, drop?} = maybe_drop_uplink(state)

    if drop? do
      state
    else
      case FARM.ingest(farm, %{frame_seq: seq, vcid: vcid}) do
        {:ok, updated_farm} ->
          %{state | farm: updated_farm}

        _ ->
          state
      end
    end
  end

  defp handle_uplink_frame(_frame, state), do: state

  defp maybe_drop_uplink(%{uplink_drop_every: nil} = state), do: {state, false}

  defp maybe_drop_uplink(%{uplink_drop_every: every, uplink_seen: seen} = state)
       when is_integer(every) and every > 0 do
    next_seen = seen + 1
    drop? = rem(next_seen, every) == 0
    {%{state | uplink_seen: next_seen}, drop?}
  end

  defp maybe_drop_uplink(state), do: {state, false}

  defp maybe_set_active_once(%{clcw_enabled: true, socket: socket}) when not is_nil(socket) do
    :inet.setopts(socket, active: :once)
    :ok
  end

  defp maybe_set_active_once(_state), do: :ok

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

  defp init_farm(false, _frame), do: nil

  defp init_farm(true, %{format: :tm, vcid: vcid}) do
    case FARM.init(vcid: vcid) do
      {:ok, farm} ->
        farm

      {:error, reason} ->
        Logger.warning("Failed to initialize FARM: #{inspect(reason)}")
        nil
    end
  end

  defp init_farm(true, _frame), do: nil

  defp listen_output(state, host, port) do
    ip_tuple = parse_bind_address(host)

    opts = [
      :binary,
      active: false,
      reuseaddr: true,
      packet: :raw,
      ip: ip_tuple
    ]

    case :gen_tcp.listen(port, opts) do
      {:ok, listener} ->
        Logger.info("Listening on TCP #{host}:#{port} for simulator uplink")
        send(self(), :accept)
        %{state | listener: listener, socket: nil}

      {:error, reason} ->
        Logger.warning("Failed to listen on TCP #{host}:#{port}: #{inspect(reason)}")
        state
    end
  end

  defp handle_client_accept(%{socket: nil} = state, socket) do
    Logger.info("Simulator accepted TCP client")
    active = if state.clcw_enabled, do: :once, else: false
    :inet.setopts(socket, active: active)

    state
    |> maybe_attach_send_buffer(socket)
    |> Map.put(:socket, socket)
  end

  defp handle_client_accept(state, socket) do
    Logger.warning("Simulator already has a TCP client; closing new connection")
    :gen_tcp.close(socket)
    state
  end

  defp maybe_attach_send_buffer(%{send_buffer: nil} = state, _socket), do: state

  defp maybe_attach_send_buffer(%{send_buffer: send_buffer} = state, socket) do
    SendBuffer.attach_socket(send_buffer, socket)
    state
  end

  defp maybe_detach_send_buffer(%{send_buffer: nil} = state), do: state

  defp maybe_detach_send_buffer(%{send_buffer: send_buffer} = state) do
    SendBuffer.detach_socket(send_buffer)
    state
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_integer(_), do: nil

  defp normalize_generator_count(nil), do: @default_generator_count
  defp normalize_generator_count(count) when is_integer(count) and count > 0, do: count
  defp normalize_generator_count(_count), do: 1

  defp normalize_max_in_flight_steps(opts, generator_count, steps_per_tick) do
    case Keyword.get(opts, :max_in_flight_steps) do
      value when is_integer(value) and value > 0 ->
        value

      _ ->
        max(steps_per_tick * @default_in_flight_multiplier, generator_count * 2)
    end
  end

  defp normalize_max_send_buffer_queue(opts, generator_count) do
    case Keyword.get(opts, :max_send_buffer_queue) do
      value when is_integer(value) and value > 0 ->
        value

      _ ->
        max(generator_count * @default_in_flight_multiplier, @default_send_buffer_queue_floor)
    end
  end

  defp normalize_dispatch_batch_floor(opts) do
    case Keyword.get(opts, :dispatch_batch_floor) do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_dispatch_batch_floor
    end
  end

  defp normalize_dispatch_batch_ceiling(opts, dispatch_batch_floor, steps_per_tick) do
    case Keyword.get(opts, :dispatch_batch_ceiling) do
      value when is_integer(value) and value >= dispatch_batch_floor ->
        value

      _ ->
        max(@default_dispatch_batch_ceiling, max(dispatch_batch_floor, steps_per_tick * 2))
    end
  end

  defp ceil_div(value, divisor) when is_integer(value) and is_integer(divisor) and divisor > 0 do
    div(value + divisor - 1, divisor)
  end

  defp parse_bind_address(address) when is_binary(address) do
    case :inet.parse_address(String.to_charlist(address)) do
      {:ok, ip_tuple} -> ip_tuple
      {:error, _} -> {0, 0, 0, 0}
    end
  end

  defp parse_bind_address(address) when is_list(address) do
    case :inet.parse_address(address) do
      {:ok, ip_tuple} -> ip_tuple
      {:error, _} -> {0, 0, 0, 0}
    end
  end

  defp parse_bind_address(_), do: {0, 0, 0, 0}

  defp format_output(nil), do: "none"
  defp format_output({:tcp, host, port}), do: "tcp:#{host}:#{port}"
  defp format_output({:udp, host, port}), do: "udp:#{host}:#{port}"
  defp format_output(other), do: inspect(other)
end
