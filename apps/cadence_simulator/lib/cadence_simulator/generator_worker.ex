defmodule CadenceSimulator.GeneratorWorker do
  @moduledoc """
  Parallel simulator worker for raw space-packet generation.

  Workers generate values for assigned steps, encode them into space packets,
  then either buffer those packets into the shared `SendBuffer` or hand them
  back to the coordinator for ordered post-processing.
  """

  use GenServer

  require Logger

  alias CadenceSimulator.{PacketEncoder, SendBuffer, SequenceAllocator, SimulatorMetrics, TMFramePlan}

  defstruct [
    :worker_id,
    :coordinator_pid,
    :provider_module,
    :provider_state,
    :encoder,
    :target_id,
    :sequence_allocator,
    :send_buffer,
    :delivery_mode,
    :frame,
    :tm_frame_state,
    :frame_counter_step,
    :frame_plan_cache,
    :metrics_id,
    :metrics_sample_rate
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    case Keyword.get(opts, :name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec generate_batch(GenServer.server(), non_neg_integer(), pos_integer()) :: :ok
  def generate_batch(pid, start_step, step_count)
      when is_integer(start_step) and is_integer(step_count) and step_count > 0 do
    GenServer.cast(pid, {:generate_batch, start_step, step_count})
  end

  @spec stop(GenServer.server()) :: :ok
  def stop(pid), do: GenServer.stop(pid)

  @impl true
  def init(opts) do
    {:ok,
     %__MODULE__{
       worker_id: Keyword.fetch!(opts, :worker_id),
       coordinator_pid: Keyword.get(opts, :coordinator_pid),
       provider_module: Keyword.fetch!(opts, :provider_module),
       provider_state: Keyword.fetch!(opts, :provider_state),
       encoder: Keyword.fetch!(opts, :encoder),
       target_id: Keyword.fetch!(opts, :target_id),
       sequence_allocator: Keyword.fetch!(opts, :sequence_allocator),
       send_buffer: Keyword.get(opts, :send_buffer),
       delivery_mode: Keyword.get(opts, :delivery_mode, :send_buffer),
       frame: Keyword.get(opts, :frame),
       tm_frame_state: init_tm_frame_state(opts),
       frame_counter_step: Keyword.get(opts, :frame_counter_step, 1),
       frame_plan_cache: %{},
       metrics_id: Keyword.get(opts, :metrics_id),
       metrics_sample_rate: Keyword.get(opts, :metrics_sample_rate, 100)
     }}
  end

  @impl true
  def handle_cast({:generate_batch, start_step, step_count}, state) do
    generation_sample? =
      SimulatorMetrics.sample_timing?(state.metrics_sample_rate, start_step)

    generation_start =
      if generation_sample?, do: System.monotonic_time(:microsecond), else: nil

    {outputs, total_bytes, packet_count, next_state} =
      Enum.reduce(
        0..(step_count - 1),
        {[], 0, 0, state},
        fn offset, {outputs_acc, bytes_acc, packet_count_acc, acc_state} ->
          step = start_step + offset

          case acc_state.provider_module.generate_values(acc_state.provider_state, step) do
            {:ok, values, provider_state} ->
              {:ok, packets} =
                PacketEncoder.encode_with_sequence(
                  acc_state.encoder,
                  acc_state.target_id,
                  values,
                  fn apid -> SequenceAllocator.next(acc_state.sequence_allocator, apid) end
                )

              binaries = Enum.map(packets, &elem(&1, 1))

              {delivery_outputs, output_bytes, delivery_state} =
                prepare_delivery_outputs(
                  %{acc_state | provider_state: provider_state},
                  binaries,
                  step
                )

              {
                :lists.reverse(delivery_outputs, outputs_acc),
                bytes_acc + output_bytes,
                packet_count_acc + length(binaries),
                delivery_state
              }

            {:error, reason, provider_state} ->
              Logger.warning(
                "Simulator worker #{acc_state.worker_id} generation error at step #{step}: #{inspect(reason)}"
              )

              {outputs_acc, bytes_acc, packet_count_acc,
               %{acc_state | provider_state: provider_state}}
          end
        end
      )

    if generation_sample? do
      SimulatorMetrics.record_timing(
        next_state.metrics_id,
        :generation,
        System.monotonic_time(:microsecond) - generation_start
      )
    end

    delivery_result =
      case state.delivery_mode do
        delivery_mode when delivery_mode in [:send_buffer, :worker_tm_fast_path] ->
          buffer_status =
            if outputs != [] do
              SendBuffer.buffer_packets(state.send_buffer, Enum.reverse(outputs), total_bytes)
            else
              nil
            end

          {:buffered, buffer_status}

        :ordered_framer ->
          {:generated, Enum.reverse(outputs), total_bytes}

        :ordered_frame_plan ->
          {:planned_frames, Enum.reverse(outputs), total_bytes}
      end

    notify_batch_complete(next_state, start_step, step_count, packet_count, delivery_result)
    {:noreply, next_state}
  end

  defp prepare_delivery_outputs(
         %{delivery_mode: :ordered_frame_plan, frame: frame} = state,
         binaries,
         sample_ordinal
       ) do
    framing_sample? =
      SimulatorMetrics.sample_timing?(state.metrics_sample_rate, sample_ordinal)

    framing_start =
      if framing_sample?, do: System.monotonic_time(:microsecond), else: nil

    {plans_reversed, total_bytes, cache} =
      Enum.reduce(binaries, {[], 0, state.frame_plan_cache}, fn packet, {plans_acc, bytes_acc, cache} ->
        {:ok, packet_plans, next_cache} = TMFramePlan.plan(packet, frame, cache)

        {
          :lists.reverse(packet_plans, plans_acc),
          bytes_acc + length(packet_plans) * frame.frame_size,
          next_cache
        }
      end)

    if framing_sample? do
      SimulatorMetrics.record_timing(
        state.metrics_id,
        :framing,
        System.monotonic_time(:microsecond) - framing_start
      )
    end

    {plans_reversed, total_bytes, %{state | frame_plan_cache: cache}}
  end

  defp prepare_delivery_outputs(
         %{delivery_mode: :worker_tm_fast_path, frame: %{format: :tm} = frame} = state,
         binaries,
         sample_ordinal
       ) do
    framing_sample? =
      SimulatorMetrics.sample_timing?(state.metrics_sample_rate, sample_ordinal)

    framing_start =
      if framing_sample?, do: System.monotonic_time(:microsecond), else: nil

    {plans_reversed, cache} =
      Enum.reduce(binaries, {[], state.frame_plan_cache}, fn packet, {plans_acc, cache} ->
        {:ok, packet_plans, next_cache} = TMFramePlan.plan(packet, frame, cache)
        {:lists.reverse(packet_plans, plans_acc), next_cache}
      end)

    {frames, total_bytes, next_frame_state} =
      TMFramePlan.encode_many(
        Enum.reverse(plans_reversed),
        frame,
        state.tm_frame_state
      )

    if framing_sample? do
      SimulatorMetrics.record_timing(
        state.metrics_id,
        :framing,
        System.monotonic_time(:microsecond) - framing_start
      )
    end

    {frames, total_bytes, %{state | frame_plan_cache: cache, tm_frame_state: next_frame_state}}
  end

  defp prepare_delivery_outputs(state, binaries, _sample_ordinal) do
    {binaries, Enum.reduce(binaries, 0, fn binary, acc -> acc + byte_size(binary) end), state}
  end

  defp init_tm_frame_state(opts) do
    case {Keyword.get(opts, :delivery_mode), Keyword.get(opts, :frame)} do
      {:worker_tm_fast_path, %{format: :tm}} ->
        worker_id = Keyword.fetch!(opts, :worker_id)
        counter_step = Keyword.get(opts, :frame_counter_step, 1)

        %{
          mcfc: rem(worker_id, 256),
          vcfc: rem(worker_id, 256),
          counter_step: max(counter_step, 1)
        }

      _other ->
        nil
    end
  end

  defp notify_batch_complete(
         %{coordinator_pid: pid, worker_id: worker_id},
         start_step,
         step_count,
         packet_count,
         delivery_result
       )
       when is_pid(pid) do
    send(
      pid,
      {:generator_batch_complete, worker_id, start_step, step_count, packet_count, delivery_result}
    )
  end

  defp notify_batch_complete(_state, _start_step, _step_count, _packet_count, _delivery_result),
    do: :ok
end
