defmodule Cadence.Protocol.RecordArchive.FileSystem.Writer do
  @moduledoc false

  use GenServer

  require Logger

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Protocol.{PacketRecord, TransferFrameRecord}
  alias Cadence.Protocol.RecordArchive.FileSystem

  @default_flush_interval_ms 250
  @default_flush_count 250

  def child_spec(opts) when is_list(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec enqueue(RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()]) ::
          :ok | {:error, term()}
  def enqueue(%RawEvidence{} = raw_evidence, transfer_frame_records, packet_records)
      when is_list(transfer_frame_records) and is_list(packet_records) do
    GenServer.call(__MODULE__, {:enqueue, raw_evidence, transfer_frame_records, packet_records})
  end

  @spec flush(binary() | nil) :: :ok | {:error, term()}
  def flush(mission_id \\ nil) do
    GenServer.call(__MODULE__, {:flush, mission_id}, :infinity)
  end

  @spec stats(binary()) :: map()
  def stats(mission_id) when is_binary(mission_id) do
    GenServer.call(__MODULE__, {:stats, mission_id})
  end

  @spec reset_stats(binary()) :: :ok
  def reset_stats(mission_id) when is_binary(mission_id) do
    GenServer.call(__MODULE__, {:reset_stats, mission_id})
  end

  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset, :infinity)
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       base_path: Keyword.fetch!(opts, :base_path),
       flush_interval_ms: Keyword.get(opts, :flush_interval_ms, @default_flush_interval_ms),
       flush_count: Keyword.get(opts, :flush_count, @default_flush_count),
       buffers: %{},
       timer_refs: %{},
       buffer_started_at_ms: %{},
       metrics: %{}
     }}
  end

  @impl true
  def handle_call(
        {:enqueue, %RawEvidence{} = raw_evidence, transfer_frame_records, packet_records},
        _from,
        state
      ) do
    entries = FileSystem.build_entries(raw_evidence, transfer_frame_records, packet_records)

    if entries == [] do
      {:reply, :ok, state}
    else
      mission_id = raw_evidence.mission_id
      buffered = Map.get(state.buffers, mission_id, [])
      next_buffer = buffered ++ entries
      enqueue_ms = System.monotonic_time(:millisecond)

      state =
        state
        |> put_in([:buffers, mission_id], next_buffer)
        |> maybe_mark_buffer_started(mission_id, buffered, enqueue_ms)
        |> maybe_schedule_flush(mission_id)

      state =
        if length(next_buffer) >= state.flush_count do
          reschedule_flush(state, mission_id, 0)
        else
          state
        end

      {:reply, :ok, state}
    end
  end

  def handle_call({:flush, nil}, _from, state) do
    case Enum.reduce_while(Map.keys(state.buffers), {:ok, state}, fn mission_id,
                                                                     {:ok, acc_state} ->
           case flush_mission(acc_state, mission_id) do
             {:ok, next_state} -> {:cont, {:ok, next_state}}
             {:error, reason, next_state} -> {:halt, {:error, mission_id, reason, next_state}}
           end
         end) do
      {:ok, next_state} ->
        {:reply, :ok, next_state}

      {:error, mission_id, reason, next_state} ->
        {:reply, {:error, reason},
         reschedule_flush(next_state, mission_id, next_state.flush_interval_ms)}
    end
  end

  def handle_call({:flush, mission_id}, _from, state) when is_binary(mission_id) do
    case flush_mission(state, mission_id) do
      {:ok, next_state} ->
        {:reply, :ok, next_state}

      {:error, reason, next_state} ->
        {:reply, {:error, reason},
         reschedule_flush(next_state, mission_id, next_state.flush_interval_ms)}
    end
  end

  def handle_call({:stats, mission_id}, _from, state) when is_binary(mission_id) do
    {:reply, build_stats(state, mission_id), state}
  end

  def handle_call({:reset_stats, mission_id}, _from, state) when is_binary(mission_id) do
    {:reply, :ok, put_in(state.metrics[mission_id], zero_metrics())}
  end

  def handle_call(:reset, _from, state) do
    _ = File.rm_rf(state.base_path)

    {:reply, :ok,
     %{state | buffers: %{}, timer_refs: %{}, buffer_started_at_ms: %{}, metrics: %{}}}
  end

  @impl true
  def handle_info({:flush_mission, mission_id, flush_ref}, state) do
    state =
      case Map.get(state.timer_refs, mission_id) do
        {timer_ref, ^flush_ref} ->
          _ = Process.cancel_timer(timer_ref)
          update_in(state.timer_refs, &Map.delete(&1, mission_id))

        _other ->
          state
      end

    case flush_mission(state, mission_id) do
      {:ok, next_state} ->
        {:noreply, next_state}

      {:error, reason, next_state} ->
        Logger.error("protocol record archive flush failed for #{mission_id}: #{inspect(reason)}")

        {:noreply, reschedule_flush(next_state, mission_id, next_state.flush_interval_ms)}
    end
  end

  defp maybe_schedule_flush(state, mission_id) do
    if Map.has_key?(state.timer_refs, mission_id) do
      state
    else
      schedule_flush(state, mission_id, state.flush_interval_ms)
    end
  end

  defp reschedule_flush(state, mission_id, delay_ms)
       when is_integer(delay_ms) and delay_ms >= 0 do
    state
    |> cancel_flush_timer(mission_id)
    |> schedule_flush(mission_id, delay_ms)
  end

  defp schedule_flush(state, mission_id, delay_ms) when is_integer(delay_ms) and delay_ms >= 0 do
    flush_ref = make_ref()
    timer_ref = Process.send_after(self(), {:flush_mission, mission_id, flush_ref}, delay_ms)
    put_in(state.timer_refs[mission_id], {timer_ref, flush_ref})
  end

  defp flush_mission(state, mission_id) do
    case Map.get(state.buffers, mission_id, []) do
      [] ->
        {:ok, cancel_flush_timer(state, mission_id)}

      entries ->
        state = cancel_flush_timer(state, mission_id)
        segment_id = FileSystem.new_segment_id()
        organization_id = OrganizationScope.organization_id_for_mission(mission_id)
        flush_started_us = System.monotonic_time(:microsecond)

        with {:ok, object_key, segment_size_bytes} <-
               FileSystem.store_segment_object(segment_id, entries, base_path: state.base_path),
             :ok <-
               FileSystem.persist_segment(segment_id, entries,
                 object_key: object_key,
                 organization_id: organization_id
               ) do
          flush_duration_us = System.monotonic_time(:microsecond) - flush_started_us

          next_state =
            state
            |> update_in([:buffers], &Map.delete(&1, mission_id))
            |> update_in([:buffer_started_at_ms], &Map.delete(&1, mission_id))
            |> update_in([:metrics, mission_id], fn metrics ->
              metrics
              |> ensure_metrics()
              |> Map.update!(:flush_count, &(&1 + 1))
              |> Map.update!(:flushed_count, &(&1 + length(entries)))
              |> Map.update!(:segment_count, &(&1 + 1))
              |> Map.update!(:flushed_bytes_total, &(&1 + segment_size_bytes))
              |> Map.update!(:flush_total_us, &(&1 + flush_duration_us))
              |> Map.put(:last_flush_error, nil)
            end)

          {:ok, next_state}
        else
          {:error, reason} ->
            next_state =
              update_in(state.metrics[mission_id], fn metrics ->
                metrics
                |> ensure_metrics()
                |> Map.update!(:flush_failure_count, &(&1 + 1))
                |> Map.put(:last_flush_error, inspect(reason))
              end)

            {:error, reason, next_state}
        end
    end
  end

  defp cancel_flush_timer(state, mission_id) do
    case Map.pop(state.timer_refs, mission_id) do
      {nil, _timer_refs} ->
        state

      {{timer_ref, _flush_ref}, timer_refs} ->
        _ = Process.cancel_timer(timer_ref)
        %{state | timer_refs: timer_refs}
    end
  end

  defp maybe_mark_buffer_started(state, mission_id, [], enqueue_ms) do
    put_in(state.buffer_started_at_ms[mission_id], enqueue_ms)
  end

  defp maybe_mark_buffer_started(state, _mission_id, _buffered, _enqueue_ms), do: state

  defp build_stats(state, mission_id) do
    metrics = ensure_metrics(Map.get(state.metrics, mission_id))
    queue_depth = length(Map.get(state.buffers, mission_id, []))

    oldest_buffered_age_ms =
      case Map.get(state.buffer_started_at_ms, mission_id) do
        nil -> 0
        started_at_ms -> max(System.monotonic_time(:millisecond) - started_at_ms, 0)
      end

    %{
      queue_depth: queue_depth,
      oldest_buffered_age_ms: oldest_buffered_age_ms,
      flush_count: metrics.flush_count,
      flush_failure_count: metrics.flush_failure_count,
      last_flush_error: metrics.last_flush_error,
      flushed_count: metrics.flushed_count,
      segment_count: metrics.segment_count,
      flush_total_us: metrics.flush_total_us,
      avg_flush_us: average(metrics.flush_total_us, metrics.flush_count),
      flushed_bytes_total: metrics.flushed_bytes_total,
      avg_segment_bytes: average(metrics.flushed_bytes_total, metrics.segment_count)
    }
  end

  defp ensure_metrics(nil), do: zero_metrics()
  defp ensure_metrics(metrics), do: metrics

  defp zero_metrics do
    %{
      flush_count: 0,
      flush_failure_count: 0,
      last_flush_error: nil,
      flushed_count: 0,
      segment_count: 0,
      flush_total_us: 0,
      flushed_bytes_total: 0
    }
  end

  defp average(_total, 0), do: 0.0
  defp average(total, count), do: total / count
end
