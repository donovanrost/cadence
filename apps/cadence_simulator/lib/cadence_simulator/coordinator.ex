defmodule CadenceSimulator.Coordinator do
  @moduledoc """
  Simulator coordinator for the extracted simulator app.

  It drives a `DynamicsProvider`, encodes telemetry values into CCSDS space
  packets, optionally wraps them in fixed-size TM frames, and writes the
  result to network output through `CadenceSimulator.SendBuffer`.

  It supports:
  - `:sequential` mode for framed or unframed output
  - `:parallel` mode for high-rate packet generation with ordered post-worker
    framing when TM output is enabled

  Parallel mode collapses to sequential semantics when only one generator is
  configured. For TM output, workers may plan framing work in parallel, but the
  coordinator remains the sole owner of final frame sequencing and emission.
  """

  use GenServer

  require Logger

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDLP.TM.Segmentation
  alias CadenceSimulator.Coordinator.Configuration

  alias CadenceSimulator.{
    GeneratorWorker,
    PacketEncoder,
    SendBuffer,
    SequenceAllocator,
    SimulatorMetrics,
    TMFramePlan
  }

  @default_rate_hz 1.0
  @default_target_id "SIM-1"
  @default_send_batch_timeout 10
  @default_send_batch_size 65_536
  @default_dispatch_batch_floor 4
  @default_dispatch_batch_ceiling 32

  # credo:disable-for-next-line Credo.Check.Warning.StructFieldAmount
  defstruct [
    :target_id,
    :provider_module,
    :provider_state,
    :packet_value_provider?,
    :encoder,
    :sequence_allocator,
    :output,
    :send_buffer,
    :metrics_id,
    :metrics_sample_rate,
    :send_batch_size,
    :rate_hz,
    :interval_ms,
    :steps_per_tick,
    :timer_ref,
    :frame,
    :frame_state,
    :parallel_mode,
    :parallel_delivery_mode,
    :generator_pool,
    :max_in_flight_steps,
    :max_send_buffer_queue,
    :dispatch_batch_floor,
    :dispatch_batch_ceiling,
    :send_buffer_queue_len,
    :send_buffer_backlog_bytes,
    :send_buffer_backpressure_mode,
    :send_buffer_status_version,
    :send_buffer_packets_sent,
    :send_buffer_bytes_sent,
    :send_buffer_flushes,
    :idle_workers,
    :completed_batches,
    :next_emit_step,
    :max_send_buffer_backlog_bytes,
    in_flight_steps: 0,
    backpressure_events: 0,
    next_step: 0,
    pending_steps: 0,
    step: 0,
    packet_count: 0
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    case Keyword.get(opts, :name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec stop(GenServer.server()) :: :ok
  def stop(server), do: GenServer.stop(server)

  @spec set_rate(GenServer.server(), number()) :: :ok | {:error, :invalid_rate_hz}
  def set_rate(server, rate_hz), do: GenServer.call(server, {:set_rate, rate_hz})

  @spec stats(GenServer.server()) :: map()
  def stats(server), do: GenServer.call(server, :stats)

  @impl true
  def init(opts) do
    target_id = Keyword.get(opts, :target_id, @default_target_id)
    rate_hz = Keyword.get(opts, :rate_hz, @default_rate_hz)
    output = Keyword.get(opts, :output)
    frame = Configuration.normalize_frame(Keyword.get(opts, :frame))
    requested_parallel_mode = Keyword.get(opts, :parallel_mode, :sequential)
    {provider_module, provider_config} = Configuration.determine_provider(opts)
    send_batch_timeout = Keyword.get(opts, :send_batch_timeout, @default_send_batch_timeout)
    send_batch_size = Keyword.get(opts, :send_batch_size, @default_send_batch_size)

    generator_count = Configuration.normalize_generator_count(opts[:generator_count])

    with {:ok, provider_state} <- provider_module.init(provider_config),
         {:ok, encoder} <- Configuration.require_encoder(opts),
         {:ok, frame_state} <- Configuration.init_frame_state(frame) do
      parallel_mode =
        Configuration.normalize_parallel_mode(
          requested_parallel_mode,
          provider_module,
          provider_config,
          generator_count
        )

      parallel_delivery_mode = Configuration.parallel_delivery_mode(parallel_mode, frame, opts)
      metrics_id = make_ref()

      metrics_sample_rate =
        Configuration.normalize_metrics_sample_rate(opts[:metrics_sample_rate])

      :ok = SimulatorMetrics.init(metrics_id)

      send_buffer_opts =
        [
          output: output,
          runtime_resolver: Keyword.get(opts, :runtime_resolver),
          batch_timeout: send_batch_timeout,
          batch_size: send_batch_size,
          metrics_id: metrics_id,
          metrics_sample_rate: metrics_sample_rate,
          coordinator_pid: self(),
          fault_profile: Keyword.get(opts, :fault_profile, %{})
        ]

      {:ok, send_buffer} = SendBuffer.start_link(send_buffer_opts)
      sequence_allocator = SequenceAllocator.new(PacketEncoder.apids(encoder))
      {interval_ms, steps_per_tick} = Configuration.schedule_config(rate_hz)

      base_state =
        %__MODULE__{
          target_id: target_id,
          provider_module: provider_module,
          provider_state: provider_state,
          packet_value_provider?: Configuration.packet_value_provider?(provider_module),
          encoder: encoder,
          sequence_allocator: sequence_allocator,
          output: output,
          send_buffer: send_buffer,
          metrics_id: metrics_id,
          metrics_sample_rate: metrics_sample_rate,
          send_batch_size: send_batch_size,
          rate_hz: rate_hz,
          interval_ms: interval_ms,
          steps_per_tick: steps_per_tick,
          frame: frame,
          frame_state: frame_state,
          parallel_mode: parallel_mode,
          parallel_delivery_mode: parallel_delivery_mode,
          send_buffer_queue_len: 0,
          send_buffer_backlog_bytes: 0,
          send_buffer_status_version: 0,
          send_buffer_packets_sent: 0,
          send_buffer_bytes_sent: 0,
          send_buffer_flushes: 0
        }
        |> maybe_init_parallel_mode(opts, provider_state, generator_count)

      timer_ref = Process.send_after(self(), :generate, interval_ms)
      {:ok, %{base_state | timer_ref: timer_ref}}
    else
      {:error, :missing_definitions} ->
        {:stop, {:missing_definitions, "definitions_path or definitions_content is required"}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:generate, %{parallel_mode: :parallel} = state) do
    timer_ref = Process.send_after(self(), :generate, state.interval_ms)

    new_state =
      state
      |> add_dispatch_budget(state.steps_per_tick)
      |> dispatch_parallel_batches()
      |> Map.put(:timer_ref, timer_ref)

    {:noreply, new_state}
  end

  def handle_info(
        {:generator_batch_complete, worker_id, _start_step, dispatched_steps, packet_count,
         {:buffered, buffer_status}},
        %{parallel_mode: :parallel, parallel_delivery_mode: parallel_delivery_mode} = state
      ) do
    if parallel_delivery_mode != :send_buffer do
      raise "unexpected buffered delivery result for #{inspect(parallel_delivery_mode)}"
    end

    new_state =
      state
      |> maybe_apply_send_buffer_status(buffer_status)
      |> complete_parallel_batch(worker_id, dispatched_steps, packet_count)
      |> dispatch_parallel_batches()

    {:noreply, new_state}
  end

  def handle_info(
        {:generator_batch_complete, worker_id, start_step, dispatched_steps, packet_count,
         {:generated, packets, total_bytes}},
        %{parallel_mode: :parallel, parallel_delivery_mode: :ordered_framer} = state
      ) do
    new_state =
      state
      |> store_completed_parallel_batch(
        start_step,
        dispatched_steps,
        packet_count,
        {:packets, packets},
        total_bytes
      )
      |> release_parallel_worker(worker_id, dispatched_steps)
      |> emit_completed_parallel_batches()
      |> dispatch_parallel_batches()

    {:noreply, new_state}
  end

  def handle_info(
        {:generator_batch_complete, worker_id, start_step, dispatched_steps, packet_count,
         {:planned_frames, frame_plans, total_bytes}},
        %{parallel_mode: :parallel, parallel_delivery_mode: :ordered_frame_plan} = state
      ) do
    new_state =
      state
      |> store_completed_parallel_batch(
        start_step,
        dispatched_steps,
        packet_count,
        {:frame_plans, frame_plans},
        total_bytes
      )
      |> release_parallel_worker(worker_id, dispatched_steps)
      |> emit_completed_parallel_batches()
      |> dispatch_parallel_batches()

    {:noreply, new_state}
  end

  def handle_info({:send_buffer_status, status}, %{parallel_mode: :parallel} = state) do
    new_state =
      state
      |> maybe_apply_send_buffer_status(status)
      |> dispatch_parallel_batches()

    {:noreply, new_state}
  end

  def handle_info({:send_buffer_status, status}, state) do
    {:noreply, maybe_apply_send_buffer_status(state, status)}
  end

  def handle_info(:generate, state) do
    {outputs, total_bytes, next_state} = generate_steps(state, state.steps_per_tick)

    if outputs != [] do
      SendBuffer.send_packets(state.send_buffer, outputs, total_bytes)
    end

    timer_ref = Process.send_after(self(), :generate, state.interval_ms)
    {:noreply, %{next_state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, stats_snapshot(state), state}
  end

  def handle_call({:set_rate, rate_hz}, _from, state) when is_number(rate_hz) do
    if rate_hz > 0 do
      if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

      {interval_ms, steps_per_tick} = Configuration.schedule_config(rate_hz * 1.0)
      timer_ref = Process.send_after(self(), :generate, interval_ms)

      {:reply, :ok,
       %{
         state
         | rate_hz: rate_hz * 1.0,
           interval_ms: interval_ms,
           steps_per_tick: steps_per_tick,
           timer_ref: timer_ref
       }}
    else
      {:reply, {:error, :invalid_rate_hz}, state}
    end
  end

  defp stats_snapshot(state) do
    state
    |> base_stats()
    |> maybe_merge_parallel_stats(state)
  end

  defp base_stats(state) do
    %{
      target_id: state.target_id,
      provider: state.provider_module,
      rate_hz: state.rate_hz,
      metrics_sample_rate: state.metrics_sample_rate,
      interval_ms: state.interval_ms,
      steps_per_tick: state.steps_per_tick,
      step: state.step,
      packet_count: state.packet_count,
      frame: state.frame,
      output: state.output,
      parallel_mode: state.parallel_mode,
      simulator_metrics: SimulatorMetrics.snapshot(state.metrics_id),
      send_buffer_stats: send_buffer_stats(state)
    }
  end

  defp send_buffer_stats(state) do
    %{
      packets_buffered: state.send_buffer_queue_len || 0,
      buffer_bytes: state.send_buffer_backlog_bytes || 0,
      packets_sent: state.send_buffer_packets_sent || 0,
      bytes_sent: state.send_buffer_bytes_sent || 0,
      flushes: state.send_buffer_flushes || 0
    }
  end

  defp maybe_merge_parallel_stats(base_stats, %{parallel_mode: :parallel} = state) do
    Map.merge(base_stats, parallel_stats(state))
  end

  defp maybe_merge_parallel_stats(base_stats, _state), do: base_stats

  defp parallel_stats(state) do
    %{
      generator_count: length(state.generator_pool || []),
      in_flight_steps: state.in_flight_steps,
      max_in_flight_steps: state.max_in_flight_steps,
      dispatch_batch_floor: state.dispatch_batch_floor,
      dispatch_batch_ceiling: state.dispatch_batch_ceiling,
      pending_steps: state.pending_steps,
      next_step: state.next_step,
      send_buffer_backpressure_mode: state.send_buffer_backpressure_mode,
      max_send_buffer_queue: state.max_send_buffer_queue,
      max_send_buffer_backlog_bytes: state.max_send_buffer_backlog_bytes,
      send_buffer_queue_len: state.send_buffer_queue_len,
      send_buffer_backlog_bytes: state.send_buffer_backlog_bytes,
      backpressure_events: state.backpressure_events,
      parallel_delivery_mode: state.parallel_delivery_mode,
      next_emit_step: state.next_emit_step,
      completed_batch_count: map_size(state.completed_batches || %{})
    }
  end

  @impl true
  def terminate(_reason, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    Enum.each(state.generator_pool || [], fn pid ->
      if Process.alive?(pid), do: GeneratorWorker.stop(pid)
    end)

    if state.send_buffer, do: SendBuffer.stop(state.send_buffer)
    if state.metrics_id, do: SimulatorMetrics.cleanup(state.metrics_id)
    :ok
  end

  defp maybe_init_parallel_mode(
         %{parallel_mode: :parallel} = state,
         opts,
         provider_state,
         generator_count
       ) do
    max_in_flight_steps =
      Configuration.normalize_max_in_flight_steps(opts, generator_count, state.steps_per_tick)

    {send_buffer_backpressure_mode, max_send_buffer_queue, max_send_buffer_backlog_bytes} =
      Configuration.normalize_send_buffer_backpressure(
        opts,
        generator_count,
        state.send_batch_size
      )

    dispatch_batch_floor = Configuration.normalize_dispatch_batch_floor(opts)

    dispatch_batch_ceiling =
      Configuration.normalize_dispatch_batch_ceiling(
        opts,
        dispatch_batch_floor,
        state.steps_per_tick
      )

    generator_pool =
      for worker_id <- 0..(generator_count - 1) do
        {:ok, pid} =
          GeneratorWorker.start_link(
            worker_id: worker_id,
            coordinator_pid: self(),
            provider_module: state.provider_module,
            provider_state: provider_state,
            encoder: state.encoder,
            target_id: state.target_id,
            sequence_allocator: state.sequence_allocator,
            send_buffer: state.send_buffer,
            delivery_mode: state.parallel_delivery_mode,
            frame: state.frame,
            metrics_id: state.metrics_id,
            metrics_sample_rate: state.metrics_sample_rate
          )

        pid
      end

    %{
      state
      | generator_pool: generator_pool,
        idle_workers: Enum.to_list(0..(generator_count - 1)),
        max_in_flight_steps: max_in_flight_steps,
        send_buffer_backpressure_mode: send_buffer_backpressure_mode,
        max_send_buffer_queue: max_send_buffer_queue,
        max_send_buffer_backlog_bytes: max_send_buffer_backlog_bytes,
        dispatch_batch_floor: dispatch_batch_floor,
        dispatch_batch_ceiling: dispatch_batch_ceiling,
        send_buffer_queue_len: 0,
        send_buffer_backlog_bytes: 0,
        send_buffer_status_version: 0,
        send_buffer_packets_sent: 0,
        send_buffer_bytes_sent: 0,
        send_buffer_flushes: 0,
        completed_batches: %{},
        next_emit_step: 0
    }
  end

  defp maybe_init_parallel_mode(state, _opts, _provider_state, _generator_count), do: state

  defp generate_steps(state, step_count) do
    Enum.reduce(1..step_count, {[], 0, state}, fn _index, {outputs_acc, bytes_acc, acc_state} ->
      generation_sample? =
        SimulatorMetrics.sample_timing?(acc_state.metrics_sample_rate, acc_state.step)

      generation_start =
        if generation_sample?, do: System.monotonic_time(:microsecond), else: nil

      case generate_packets_for_step(acc_state, acc_state.step) do
        {:ok, packets, next_generation_state} ->
          append_generated_step_outputs(
            packets,
            next_generation_state,
            generation_sample?,
            generation_start,
            outputs_acc,
            bytes_acc,
            acc_state
          )

        {:error, reason, next_generation_state} ->
          Logger.warning("Simulator provider error at step #{acc_state.step}: #{inspect(reason)}")

          {outputs_acc, bytes_acc,
           %{next_generation_state | step: next_generation_state.step + 1}}
      end
    end)
  end

  defp append_generated_step_outputs(
         packets,
         next_generation_state,
         generation_sample?,
         generation_start,
         outputs_acc,
         bytes_acc,
         acc_state
       ) do
    next_generation_state = %{next_generation_state | step: next_generation_state.step + 1}

    maybe_record_generation_timing(
      generation_sample?,
      next_generation_state.metrics_id,
      generation_start
    )

    framing_start =
      if generation_sample?, do: System.monotonic_time(:microsecond), else: nil

    {framed_outputs, framed_bytes, next_state} =
      Enum.reduce(
        packets,
        {[], 0, next_generation_state},
        fn {_name, packet}, {packet_acc, packet_bytes, packet_state} ->
          {output_binary, updated_packet_state} = encode_output(packet_state, packet)

          {[output_binary | packet_acc], packet_bytes + byte_size(output_binary),
           updated_packet_state}
        end
      )

    maybe_record_framing_timing(generation_sample?, acc_state.metrics_id, framing_start)

    {
      :lists.reverse(framed_outputs, outputs_acc),
      bytes_acc + framed_bytes,
      %{
        next_state
        | packet_count: next_state.packet_count + length(packets)
      }
    }
  end

  defp maybe_record_generation_timing(false, _metrics_id, _generation_start), do: :ok

  defp maybe_record_generation_timing(true, metrics_id, generation_start) do
    SimulatorMetrics.record_timing(
      metrics_id,
      :generation,
      System.monotonic_time(:microsecond) - generation_start
    )
  end

  defp maybe_record_framing_timing(false, _metrics_id, _framing_start), do: :ok

  defp maybe_record_framing_timing(true, metrics_id, framing_start) do
    SimulatorMetrics.record_timing(
      metrics_id,
      :framing,
      System.monotonic_time(:microsecond) - framing_start
    )
  end

  defp generate_packets_for_step(%{packet_value_provider?: true} = state, step) do
    case state.provider_module.generate_packet_values(state.provider_state, step) do
      {:ok, packet_values, provider_state} ->
        {:ok, packets} =
          PacketEncoder.encode_packet_values_with_sequence(
            state.encoder,
            state.target_id,
            packet_values,
            fn apid -> SequenceAllocator.next(state.sequence_allocator, apid) end
          )

        {:ok, packets, %{state | provider_state: provider_state}}

      {:error, reason, provider_state} ->
        {:error, reason, %{state | provider_state: provider_state}}
    end
  end

  defp generate_packets_for_step(state, step) do
    case state.provider_module.generate_values(state.provider_state, step) do
      {:ok, values, provider_state} ->
        {:ok, packets} =
          PacketEncoder.encode_with_sequence(
            state.encoder,
            state.target_id,
            values,
            fn apid -> SequenceAllocator.next(state.sequence_allocator, apid) end
          )

        {:ok, packets, %{state | provider_state: provider_state}}

      {:error, reason, provider_state} ->
        {:error, reason, %{state | provider_state: provider_state}}
    end
  end

  defp encode_output(%{frame: nil} = state, packet), do: {packet, state}

  defp encode_output(
         %{frame: %{format: :tm} = frame, frame_state: frame_state} = state,
         packet
       ) do
    sdu = %SDUOctets{
      profile: :tm,
      scid: frame.scid,
      vcid: frame.vcid,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: packet,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, framed_output, next_frame_state} =
      Segmentation.segment_encode(
        sdu,
        %{frame_size: frame.frame_size, scid: frame.scid, vcid: frame.vcid, ocf_length: 0},
        frame_state,
        []
      )

    {framed_output, %{state | frame_state: next_frame_state}}
  end

  defp dispatch_parallel_batches(%{parallel_mode: :parallel} = state) do
    worker_count = length(state.generator_pool || [])
    {new_state, _dispatched_steps} = dispatch_parallel_batches(state, worker_count)
    new_state
  end

  defp dispatch_parallel_batches(state), do: state

  defp dispatch_parallel_batches(%{pending_steps: pending_steps} = state, worker_count)
       when worker_count <= 0 or pending_steps <= 0 do
    {state, 0}
  end

  defp dispatch_parallel_batches(state, worker_count) do
    if send_buffer_saturated?(state) do
      {increment_backpressure(state), 0}
    else
      dispatch_available_parallel_batches(state, worker_count)
    end
  end

  defp dispatch_available_parallel_batches(state, worker_count) do
    available_workers = length(state.idle_workers || [])
    available_steps = max(state.max_in_flight_steps - state.in_flight_steps, 0)
    tentative_steps_to_dispatch = min(state.pending_steps, available_steps)

    target_steps_per_worker =
      dispatch_target_steps_per_worker(state, tentative_steps_to_dispatch, available_workers)

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

    next_step =
      Enum.reduce(Enum.with_index(assigned_worker_ids), state.next_step, fn {worker_id, index},
                                                                            acc_next_step ->
        step_count = batch_step_count(index, base_batch_size, remainder)
        worker = Enum.at(state.generator_pool, worker_id)
        GeneratorWorker.generate_batch(worker, acc_next_step, step_count)
        acc_next_step + step_count
      end)

    {
      %{
        state
        | idle_workers: remaining_idle_workers,
          in_flight_steps: state.in_flight_steps + steps_to_dispatch,
          next_step: next_step,
          pending_steps: max(state.pending_steps - steps_to_dispatch, 0)
      },
      steps_to_dispatch
    }
  end

  defp batch_step_count(index, base_batch_size, remainder) do
    base_batch_size + if(index < remainder, do: 1, else: 0)
  end

  defp dispatch_target_steps_per_worker(_state, _steps_to_dispatch, available_workers)
       when available_workers <= 0,
       do: 0

  defp dispatch_target_steps_per_worker(state, steps_to_dispatch, available_workers) do
    floor = max(state.dispatch_batch_floor || @default_dispatch_batch_floor, 1)
    ceiling = max(state.dispatch_batch_ceiling || @default_dispatch_batch_ceiling, floor)
    evenly_split_steps = max(ceil_div(max(steps_to_dispatch, 1), available_workers), 1)

    cond do
      send_buffer_utilization(state) >= 0.75 ->
        1

      send_buffer_utilization(state) >= 0.5 ->
        max(1, min(floor, evenly_split_steps))

      true ->
        min(ceiling, evenly_split_steps)
    end
  end

  defp send_buffer_saturated?(%{send_buffer_backpressure_mode: :queue} = state) do
    state.send_buffer_queue_len >= max(state.max_send_buffer_queue || 0, 1)
  end

  defp send_buffer_saturated?(%{send_buffer_backpressure_mode: :bytes} = state) do
    state.send_buffer_backlog_bytes >= max(state.max_send_buffer_backlog_bytes || 0, 1)
  end

  defp send_buffer_saturated?(_state), do: false

  defp send_buffer_utilization(%{
         send_buffer_backpressure_mode: :queue,
         max_send_buffer_queue: max_queue
       })
       when max_queue in [nil, 0],
       do: 0.0

  defp send_buffer_utilization(%{
         send_buffer_backpressure_mode: :queue,
         send_buffer_queue_len: queue_len,
         max_send_buffer_queue: max_queue
       }) do
    queue_len / max(max_queue, 1)
  end

  defp send_buffer_utilization(%{
         send_buffer_backpressure_mode: :bytes,
         send_buffer_backlog_bytes: backlog_bytes,
         max_send_buffer_backlog_bytes: max_backlog_bytes
       })
       when max_backlog_bytes in [nil, 0] do
    if backlog_bytes > 0, do: 1.0, else: 0.0
  end

  defp send_buffer_utilization(%{
         send_buffer_backpressure_mode: :bytes,
         send_buffer_backlog_bytes: backlog_bytes,
         max_send_buffer_backlog_bytes: max_backlog_bytes
       }) do
    backlog_bytes / max(max_backlog_bytes, 1)
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

  defp complete_parallel_batch(state, worker_id, dispatched_steps, packet_count) do
    %{
      state
      | in_flight_steps: max(state.in_flight_steps - dispatched_steps, 0),
        packet_count: state.packet_count + packet_count,
        step: state.step + dispatched_steps
    }
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

  defp release_parallel_worker(state, worker_id, dispatched_steps) do
    %{
      state
      | in_flight_steps: max(state.in_flight_steps - dispatched_steps, 0)
    }
    |> release_worker(worker_id)
  end

  defp store_completed_parallel_batch(
         %{completed_batches: completed_batches} = state,
         start_step,
         step_count,
         packet_count,
         delivery,
         total_bytes
       ) do
    batch = %{
      step_count: step_count,
      packet_count: packet_count,
      delivery: delivery,
      total_bytes: total_bytes
    }

    %{state | completed_batches: Map.put(completed_batches, start_step, batch)}
  end

  defp emit_completed_parallel_batches(
         %{
           parallel_delivery_mode: parallel_delivery_mode,
           completed_batches: completed_batches,
           next_emit_step: next_emit_step
         } = state
       ) do
    if parallel_delivery_mode in [:ordered_framer, :ordered_frame_plan] do
      case Map.pop(completed_batches, next_emit_step) do
        {nil, _remaining_batches} ->
          state

        {batch, remaining_batches} ->
          state
          |> Map.put(:completed_batches, remaining_batches)
          |> emit_completed_parallel_batch(batch)
          |> emit_completed_parallel_batches()
      end
    else
      state
    end
  end

  defp emit_completed_parallel_batches(state), do: state

  defp emit_completed_parallel_batch(state, %{
         step_count: step_count,
         packet_count: packet_count,
         delivery: {:packets, packets},
         total_bytes: total_bytes
       }) do
    {outputs, output_bytes, next_state} = ordered_parallel_outputs(state, packets, total_bytes)

    next_state =
      if outputs == [] do
        next_state
      else
        SendBuffer.send_packets(next_state.send_buffer, outputs, output_bytes)
        next_state
      end

    %{
      next_state
      | next_emit_step: next_state.next_emit_step + step_count,
        step: next_state.step + step_count,
        packet_count: next_state.packet_count + packet_count
    }
  end

  defp emit_completed_parallel_batch(state, %{
         step_count: step_count,
         packet_count: packet_count,
         delivery: {:frame_plans, frame_plans},
         total_bytes: total_bytes
       }) do
    {outputs, output_bytes, next_state} =
      ordered_parallel_frame_plans(state, frame_plans, total_bytes)

    next_state =
      if outputs == [] do
        next_state
      else
        SendBuffer.send_packets(next_state.send_buffer, outputs, output_bytes)
        next_state
      end

    %{
      next_state
      | next_emit_step: next_state.next_emit_step + step_count,
        step: next_state.step + step_count,
        packet_count: next_state.packet_count + packet_count
    }
  end

  defp ordered_parallel_outputs(%{frame: nil} = state, packets, total_bytes) do
    {packets, total_bytes, state}
  end

  defp ordered_parallel_outputs(state, packets, _total_bytes) do
    framing_sample? =
      SimulatorMetrics.sample_timing?(state.metrics_sample_rate, state.next_emit_step)

    framing_start =
      if framing_sample?, do: System.monotonic_time(:microsecond), else: nil

    Enum.reduce(packets, {[], 0, state}, fn packet, {outputs_acc, bytes_acc, acc_state} ->
      {output_binary, next_state} = encode_output(acc_state, packet)

      {[output_binary | outputs_acc], bytes_acc + byte_size(output_binary), next_state}
    end)
    |> then(fn {outputs_reversed, output_bytes, next_state} ->
      if framing_sample? do
        SimulatorMetrics.record_timing(
          next_state.metrics_id,
          :framing,
          System.monotonic_time(:microsecond) - framing_start
        )
      end

      {Enum.reverse(outputs_reversed), output_bytes, next_state}
    end)
  end

  defp ordered_parallel_frame_plans(
         %{frame: %{format: :tm} = frame, frame_state: frame_state} = state,
         frame_plans,
         _total_bytes
       ) do
    framing_sample? =
      SimulatorMetrics.sample_timing?(state.metrics_sample_rate, state.next_emit_step)

    framing_start =
      if framing_sample?, do: System.monotonic_time(:microsecond), else: nil

    {outputs, output_bytes, next_frame_state} =
      TMFramePlan.encode_many(frame_plans, frame, frame_state)

    if framing_sample? do
      SimulatorMetrics.record_timing(
        state.metrics_id,
        :framing,
        System.monotonic_time(:microsecond) - framing_start
      )
    end

    {outputs, output_bytes, %{state | frame_state: next_frame_state}}
  end

  defp maybe_apply_send_buffer_status(state, nil), do: state

  defp maybe_apply_send_buffer_status(
         state,
         %{
           status_version: status_version,
           packets_buffered: packets_buffered,
           buffer_bytes: buffer_bytes,
           packets_sent: packets_sent,
           bytes_sent: bytes_sent,
           flushes: flushes
         }
       )
       when is_integer(status_version) do
    if status_version >= state.send_buffer_status_version do
      %{
        state
        | send_buffer_status_version: status_version,
          send_buffer_queue_len: packets_buffered,
          send_buffer_backlog_bytes: buffer_bytes,
          send_buffer_packets_sent: packets_sent,
          send_buffer_bytes_sent: bytes_sent,
          send_buffer_flushes: flushes
      }
    else
      state
    end
  end

  defp ceil_div(value, divisor) when is_integer(value) and is_integer(divisor) and divisor > 0 do
    div(value + divisor - 1, divisor)
  end
end
