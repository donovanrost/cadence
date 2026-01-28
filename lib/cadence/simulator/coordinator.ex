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

  alias Cadence.CCSDS.Core.SDUOctets
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
    SimulatorMetrics
  }

  alias Cadence.Simulator.Providers.{BasicDynamics, DatabaseDynamics, ScenarioProvider}
  alias Cadence.Time.Timer, as: TimeTimer

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
    :uplink_frame,
    :uplink_pipeline,
    :uplink_opts,
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
    parallel_mode = Keyword.get(opts, :parallel_mode, :sequential)
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
    generator_count = Keyword.get(opts, :generator_count, @default_generator_count)
    batch_timeout = Keyword.get(opts, :send_batch_timeout, @default_send_batch_timeout)
    batch_size = Keyword.get(opts, :send_batch_size, @default_send_batch_size)

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
        mode: state.mode
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
    timer_ref = TimeTimer.send_after(self(), :generate, interval_ms)

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

  defp send_frame(%{parallel_mode: :parallel, send_buffer: send_buffer}, frame_binary) do
    SendBuffer.send_packet(send_buffer, frame_binary)
  end

  defp send_frame(%{output: {:tcp, _, _}, socket: nil}, _frame_binary), do: :ok

  defp send_frame(%{output: {:tcp, _, _}, socket: socket}, frame_binary) do
    case :gen_tcp.send(socket, frame_binary) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("TCP send failed: #{inspect(reason)}")
    end
  end

  defp send_frame(%{output: {:udp, _, _}, socket: nil}, _frame_binary), do: :ok

  defp send_frame(%{output: {:udp, host, port}, socket: socket}, frame_binary) do
    case :gen_udp.send(socket, String.to_charlist(host), port, frame_binary) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("UDP send failed: #{inspect(reason)}")
    end
  end

  defp send_frame(_, _frame_binary), do: :ok

  defp encode_uplink(%{uplink_pipeline: nil} = state, packet, _step), do: {packet, state}

  defp encode_uplink(%{uplink_pipeline: pipeline, uplink_opts: opts} = state, packet, step) do
    ctx =
      %{
        frame_size: opts[:frame_size],
        scid: opts[:uplink_scid] || opts[:scid],
        vcid: opts[:uplink_vcid] || opts[:vcid],
        map_id: opts[:uplink_map_id]
      }
      |> maybe_put_ocf(state, step)

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
