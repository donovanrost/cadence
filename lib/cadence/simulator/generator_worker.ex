defmodule Cadence.Simulator.GeneratorWorker do
  @moduledoc """
  Parallel telemetry generation worker.

  Each GeneratorWorker handles value generation and encoding for assigned steps,
  working in parallel with other workers. The worker:

  1. Receives step assignments from the Coordinator
  2. Generates values using the configured provider
  3. Encodes packets using shared encoder state
  4. Allocates sequence numbers via SequenceAllocator (lock-free)
  5. Sends encoded packets to SendBuffer (non-blocking)

  ## Usage

  Workers are spawned and managed by the Coordinator when running in parallel mode.

      {:ok, worker} = GeneratorWorker.start_link(
        worker_id: 0,
        provider_module: BasicDynamics,
        provider_state: provider_state,
        encoder: encoder,
        target_id: "SIM-1",
        sequence_allocator: allocator,
        send_buffer: send_buffer_pid
      )

      # Coordinator dispatches steps
      GeneratorWorker.generate(worker, step)
  """

  use GenServer
  require Logger

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.CCSDS.Uplink.Pipeline, as: UplinkPipeline
  alias Cadence.Simulator.COP1.CLCWInjector
  alias Cadence.Simulator.{PacketEncoder, SendBuffer, SequenceAllocator, SimulatorMetrics}
  alias Cadence.Time, as: CadenceTime

  defstruct [
    :worker_id,
    :coordinator_id,
    :provider_module,
    :provider_state,
    :encoder,
    :target_id,
    :uplink_pipeline,
    :uplink_opts,
    :sequence_allocator,
    :send_buffer,
    :clcw_enabled,
    :clcw_injector,
    :sample_rate
  ]

  @default_sample_rate 100

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts a generator worker.

  ## Options

  - `:worker_id` - Worker identifier (required)
  - `:coordinator_id` - ID for metrics tracking
  - `:provider_module` - Provider module (e.g., BasicDynamics)
  - `:provider_state` - Initial provider state
  - `:encoder` - PacketEncoder struct (required)
  - `:target_id` - Target identifier
  - `:sequence_allocator` - SequenceAllocator struct
  - `:send_buffer` - SendBuffer PID
  - `:sample_rate` - Timing sample rate (default: 100)
  - `:clcw_injector` - Optional CLCW override config for error injection
  """
  def start_link(opts) do
    worker_id = Keyword.fetch!(opts, :worker_id)

    name =
      Keyword.get(
        opts,
        :name,
        {:via, Registry, {Cadence.MissionRegistry, {:generator_worker, worker_id}}}
      )

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Dispatches a step to the worker for generation. Non-blocking cast.

  The worker will generate values for this step, encode them, and send
  to the SendBuffer.
  """
  @spec generate(GenServer.server(), non_neg_integer()) :: :ok
  def generate(pid, step) when is_integer(step) do
    GenServer.cast(pid, {:generate, step})
  end

  @doc """
  Synchronous generation for testing. Blocks until complete.
  """
  @spec generate_sync(GenServer.server(), non_neg_integer()) :: :ok | {:error, term()}
  def generate_sync(pid, step) when is_integer(step) do
    GenServer.call(pid, {:generate, step})
  end

  @doc """
  Gets worker statistics.
  """
  @spec stats(GenServer.server()) :: map()
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  @doc """
  Stops the worker.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(pid) do
    GenServer.stop(pid)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    worker_id = Keyword.fetch!(opts, :worker_id)
    coordinator_id = Keyword.get(opts, :coordinator_id, :default)
    provider_module = Keyword.fetch!(opts, :provider_module)
    provider_state = Keyword.fetch!(opts, :provider_state)
    encoder = Keyword.get(opts, :encoder)
    target_id = Keyword.fetch!(opts, :target_id)
    uplink_opts = Keyword.get(opts, :uplink_opts)
    uplink_pipeline = init_uplink_pipeline(uplink_opts)
    sequence_allocator = Keyword.fetch!(opts, :sequence_allocator)
    send_buffer = Keyword.fetch!(opts, :send_buffer)
    clcw_enabled = Keyword.get(opts, :clcw_enabled, false)
    clcw_injector = Keyword.get(opts, :clcw_injector)
    sample_rate = Keyword.get(opts, :sample_rate, @default_sample_rate)

    state = %__MODULE__{
      worker_id: worker_id,
      coordinator_id: coordinator_id,
      provider_module: provider_module,
      provider_state: provider_state,
      encoder: encoder,
      target_id: target_id,
      uplink_pipeline: uplink_pipeline,
      uplink_opts: uplink_opts,
      sequence_allocator: sequence_allocator,
      send_buffer: send_buffer,
      clcw_enabled: clcw_enabled,
      clcw_injector: clcw_injector,
      sample_rate: sample_rate
    }

    Logger.debug(
      "GeneratorWorker #{worker_id} started, uplink_pipeline: #{if uplink_pipeline, do: "initialized", else: "none (raw packets)"}"
    )

    {:ok, state}
  end

  @impl true
  def handle_cast({:generate, step}, state) do
    {_result, new_state} = do_generate(state, step)
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:generate, step}, _from, state) do
    {result, new_state} = do_generate(state, step)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      worker_id: state.worker_id,
      provider: state.provider_module,
      target_id: state.target_id,
      has_encoder: state.encoder != nil
    }

    {:reply, stats, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_generate(state, step) do
    %{
      provider_module: provider_module,
      provider_state: provider_state,
      sequence_allocator: sequence_allocator,
      send_buffer: send_buffer,
      coordinator_id: coordinator_id,
      sample_rate: sample_rate
    } = state

    # Sample timing
    should_time = rem(step, sample_rate) == 0
    start_time = if should_time, do: CadenceTime.monotonic(:microsecond)

    # Generate values from provider
    case provider_module.generate_values(provider_state, step) do
      {:ok, values, _new_provider_state} ->
        maybe_record_generation(coordinator_id, should_time, start_time)
        SimulatorMetrics.inc(coordinator_id, :packets_generated)

        encode_start = if should_time, do: CadenceTime.monotonic(:microsecond)

        {result, updated_state} =
          encode_and_send_values(state, values, sequence_allocator, send_buffer, step)

        maybe_record_encoding(coordinator_id, should_time, encode_start)

        {result, updated_state}

      {:error, reason, _new_provider_state} ->
        Logger.warning(
          "GeneratorWorker #{state.worker_id} generation error at step #{step}: #{inspect(reason)}"
        )

        {{:error, reason}, state}
    end
  end

  defp maybe_record_generation(_coordinator_id, false, _start_time), do: :ok

  defp maybe_record_generation(coordinator_id, true, start_time) do
    gen_time = CadenceTime.monotonic(:microsecond) - start_time
    SimulatorMetrics.record_timing(coordinator_id, :generation, gen_time)
  end

  defp maybe_record_encoding(_coordinator_id, false, _start_time), do: :ok

  defp maybe_record_encoding(coordinator_id, true, start_time) do
    encode_time = CadenceTime.monotonic(:microsecond) - start_time
    SimulatorMetrics.record_timing(coordinator_id, :encoding, encode_time)
  end

  defp encode_and_send_values(state, values, sequence_allocator, send_buffer, step) do
    case state.encoder do
      nil ->
        Logger.error(
          "GeneratorWorker #{state.worker_id} missing encoder; skipping telemetry generation"
        )

        {{:error, :missing_encoder}, state}

      encoder ->
        {:ok, updated_state} =
          encode_and_send(
            encoder,
            state.target_id,
            values,
            sequence_allocator,
            send_buffer,
            state,
            step
          )

        {:ok, updated_state}
    end
  end

  defp encode_and_send(
         encoder,
         target_id,
         values,
         sequence_allocator,
         send_buffer,
         state,
         step
       ) do
    # Use encoder with external sequence allocation
    sequence_fn = fn apid ->
      SequenceAllocator.next(sequence_allocator, apid)
    end

    {:ok, packets} = PacketEncoder.encode_with_sequence(encoder, target_id, values, sequence_fn)

    updated_state =
      Enum.reduce(packets, state, fn {_packet_name, binary}, acc_state ->
        {processed, next_state} = encode_uplink(acc_state, binary, step)
        SendBuffer.send_packet(send_buffer, processed)
        next_state
      end)

    {:ok, updated_state}
  end

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

  defp maybe_put_ocf(ctx, %{clcw_enabled: true, uplink_opts: nil}, _step) when is_map(ctx) do
    ctx
  end

  defp maybe_put_ocf(
         ctx,
         %{clcw_enabled: true, uplink_opts: opts, clcw_injector: injector},
         step
       )
       when is_map(ctx) do
    if opts[:profile] == :tm do
      vcid = opts[:uplink_vcid] || opts[:vcid] || 0
      report_value = rem(step, 256)

      clcw =
        %CLCW{vcid: vcid, report_value: report_value}
        |> maybe_apply_injector(injector, step)

      case CLCW.encode(clcw) do
        {:ok, ocf} ->
          Map.merge(ctx, %{ocf: ocf, ocf_length: byte_size(ocf)})

        {:error, reason} ->
          Logger.warning("Failed to encode CLCW: #{inspect(reason)}")
          ctx
      end
    else
      ctx
    end
  end

  defp maybe_put_ocf(ctx, _state, _step), do: ctx

  defp maybe_apply_injector(%CLCW{} = clcw, %CLCWInjector{} = injector, step) do
    CLCWInjector.apply(injector, clcw, step)
  end

  defp maybe_apply_injector(clcw, _injector, _step), do: clcw

  defp init_uplink_pipeline(nil) do
    Logger.debug("GeneratorWorker init_uplink_pipeline: opts is nil")
    nil
  end

  defp init_uplink_pipeline(opts) do
    case UplinkPipeline.init(opts) do
      {:ok, pipeline} ->
        Logger.debug(
          "GeneratorWorker init_uplink_pipeline: initialized with opts=#{inspect(opts)}"
        )

        pipeline

      {:error, reason} ->
        Logger.warning(
          "GeneratorWorker init_uplink_pipeline: failed with reason=#{inspect(reason)}"
        )

        nil
    end
  end
end
