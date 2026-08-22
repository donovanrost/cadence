# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule Cadence.Protocol.RecordArchive.FileSystem.Writer do
  @moduledoc false

  use GenServer

  require Logger

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Protocol.{PacketRecord, TransferFrameRecord}
  alias Cadence.Protocol.RecordArchive.FileSystem
  alias Cadence.Repo

  @default_flush_interval_ms 250
  @default_flush_count 250

  def child_spec(opts) when is_list(opts) do
    %{
      id: Keyword.get(opts, :child_id, server(opts)),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: server(opts))
  end

  @spec enqueue(RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()]) ::
          :ok | {:error, term()}
  def enqueue(%RawEvidence{} = raw_evidence, transfer_frame_records, packet_records)
      when is_list(transfer_frame_records) and is_list(packet_records) do
    enqueue(raw_evidence, transfer_frame_records, packet_records, [])
  end

  @spec enqueue(RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()], keyword()) ::
          :ok | {:error, term()}
  def enqueue(%RawEvidence{} = raw_evidence, transfer_frame_records, packet_records, opts)
      when is_list(transfer_frame_records) and is_list(packet_records) and is_list(opts) do
    GenServer.call(
      server(opts),
      {:enqueue, raw_evidence, transfer_frame_records, packet_records}
    )
  end

  @spec enqueue_many([{RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()]}]) ::
          :ok | {:error, term()}
  def enqueue_many(records_batch) when is_list(records_batch) do
    enqueue_many(records_batch, [])
  end

  @spec enqueue_many(
          [{RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()]}],
          keyword()
        ) :: :ok | {:error, term()}
  def enqueue_many(records_batch, opts) when is_list(records_batch) and is_list(opts) do
    GenServer.call(server(opts), {:enqueue_many, records_batch})
  end

  @spec flush(binary() | nil) :: :ok | {:error, term()}
  def flush(mission_id \\ nil) do
    flush(mission_id, [])
  end

  @spec flush(binary() | nil, keyword()) :: :ok | {:error, term()}
  def flush(mission_id, opts)
      when (is_binary(mission_id) or is_nil(mission_id)) and is_list(opts) do
    GenServer.call(server(opts), {:flush, mission_id}, :infinity)
  end

  @spec stats(binary()) :: map()
  def stats(mission_id) when is_binary(mission_id) do
    stats(mission_id, [])
  end

  @spec stats(binary(), keyword()) :: map()
  def stats(mission_id, opts) when is_binary(mission_id) and is_list(opts) do
    GenServer.call(server(opts), {:stats, mission_id})
  end

  @spec reset_stats(binary()) :: :ok
  def reset_stats(mission_id) when is_binary(mission_id) do
    reset_stats(mission_id, [])
  end

  @spec reset_stats(binary(), keyword()) :: :ok
  def reset_stats(mission_id, opts) when is_binary(mission_id) and is_list(opts) do
    GenServer.call(server(opts), {:reset_stats, mission_id})
  end

  @spec reset() :: :ok
  def reset do
    reset([])
  end

  @spec reset(keyword()) :: :ok
  def reset(opts) when is_list(opts) do
    GenServer.call(server(opts), :reset, :infinity)
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       base_path: Keyword.fetch!(opts, :base_path),
       repo: Keyword.get(opts, :repo, Repo),
       archive_backend: FileSystem.archive_backend(opts),
       flush_interval_ms: Keyword.get(opts, :flush_interval_ms, @default_flush_interval_ms),
       flush_count: Keyword.get(opts, :flush_count, @default_flush_count),
       buffers: %{},
       buffer_sizes: %{},
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
    state = normalize_state(state)
    entries = FileSystem.build_entries(raw_evidence, transfer_frame_records, packet_records)

    if entries == [] do
      {:reply, :ok, state}
    else
      {:reply, :ok, enqueue_entries(state, [{raw_evidence.mission_id, entries}])}
    end
  end

  def handle_call({:enqueue_many, records_batch}, _from, state) when is_list(records_batch) do
    state = normalize_state(state)

    case normalize_records_batch(records_batch) do
      {:ok, mission_entries} ->
        {:reply, :ok, enqueue_entries(state, mission_entries)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:flush, nil}, _from, state) do
    state = normalize_state(state)

    case flush_all_missions(state) do
      {:ok, next_state} ->
        {:reply, :ok, next_state}

      {:error, mission_id, reason, next_state} ->
        {:reply, {:error, reason},
         reschedule_flush(next_state, mission_id, next_state.flush_interval_ms)}
    end
  end

  def handle_call({:flush, mission_id}, _from, state) when is_binary(mission_id) do
    state = normalize_state(state)

    case flush_mission(state, mission_id) do
      {:ok, next_state} ->
        {:reply, :ok, next_state}

      {:error, reason, next_state} ->
        {:reply, {:error, reason},
         reschedule_flush(next_state, mission_id, next_state.flush_interval_ms)}
    end
  end

  def handle_call({:stats, mission_id}, _from, state) when is_binary(mission_id) do
    state = normalize_state(state)
    {:reply, build_stats(state, mission_id), state}
  end

  def handle_call({:reset_stats, mission_id}, _from, state) when is_binary(mission_id) do
    state = normalize_state(state)
    {:reply, :ok, put_in(state.metrics[mission_id], zero_metrics())}
  end

  def handle_call(:reset, _from, state) do
    state = normalize_state(state)
    _ = File.rm_rf(state.base_path)

    {:reply, :ok,
     %{
       state
       | buffers: %{},
         buffer_sizes: %{},
         timer_refs: %{},
         buffer_started_at_ms: %{},
         metrics: %{}
     }}
  end

  defp flush_all_missions(state) do
    Enum.reduce_while(Map.keys(state.buffers), {:ok, state}, fn mission_id, {:ok, acc_state} ->
      flush_mission_entry(acc_state, mission_id)
    end)
  end

  defp flush_mission_entry(acc_state, mission_id) do
    case flush_mission(acc_state, mission_id) do
      {:ok, next_state} -> {:cont, {:ok, next_state}}
      {:error, reason, next_state} -> {:halt, {:error, mission_id, reason, next_state}}
    end
  end

  @impl true
  def handle_info({:flush_mission, mission_id, flush_ref}, state) do
    state = normalize_state(state)

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
    case Map.get(state.buffers, mission_id) do
      nil ->
        {:ok, cancel_flush_timer(state, mission_id)}

      queue ->
        state = cancel_flush_timer(state, mission_id)
        entries = :queue.to_list(queue)
        segment_id = FileSystem.new_segment_id()
        organization_id = OrganizationScope.organization_id_for_mission(mission_id)
        flush_started_us = System.monotonic_time(:microsecond)

        with {:ok, object_key, segment_size_bytes} <-
               FileSystem.store_segment_object(segment_id, entries, base_path: state.base_path),
             :ok <-
               FileSystem.persist_segment(segment_id, entries,
                 object_key: object_key,
                 organization_id: organization_id,
                 archive_backend: state.archive_backend,
                 repo: state.repo
               ) do
          flush_duration_us = System.monotonic_time(:microsecond) - flush_started_us

          completed_at = DateTime.utc_now()

          next_state =
            state
            |> update_in([:buffers], &Map.delete(&1, mission_id))
            |> update_in([:buffer_sizes], &Map.delete(&1, mission_id))
            |> update_in([:buffer_started_at_ms], &Map.delete(&1, mission_id))
            |> update_in([:metrics, mission_id], fn metrics ->
              metrics
              |> ensure_metrics()
              |> Map.update!(:flush_count, &(&1 + 1))
              |> Map.update!(:flushed_count, &(&1 + length(entries)))
              |> Map.update!(:segment_count, &(&1 + 1))
              |> Map.update!(:flushed_bytes_total, &(&1 + segment_size_bytes))
              |> Map.update!(:flush_total_us, &(&1 + flush_duration_us))
              |> Map.put(:last_completed_at, completed_at)
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

  defp maybe_mark_buffer_started(state, mission_id, buffered_size, enqueue_ms)
       when is_integer(buffered_size) do
    if buffered_size == 0 do
      put_in(state.buffer_started_at_ms[mission_id], enqueue_ms)
    else
      state
    end
  end

  defp build_stats(state, mission_id) do
    metrics = ensure_metrics(Map.get(state.metrics, mission_id))
    queue_depth = Map.get(state.buffer_sizes, mission_id, 0)

    oldest_buffered_age_ms =
      case Map.get(state.buffer_started_at_ms, mission_id) do
        nil -> 0
        started_at_ms -> max(System.monotonic_time(:millisecond) - started_at_ms, 0)
      end

    %{
      queue_depth: queue_depth,
      processing?: Map.has_key?(state.timer_refs, mission_id),
      backpressured?: false,
      oldest_buffered_age_ms: oldest_buffered_age_ms,
      flush_count: metrics.flush_count,
      flush_failure_count: metrics.flush_failure_count,
      last_error: metrics.last_flush_error,
      last_flush_error: metrics.last_flush_error,
      last_completed_at: metrics.last_completed_at,
      flushed_count: metrics.flushed_count,
      segment_count: metrics.segment_count,
      flush_total_us: metrics.flush_total_us,
      avg_flush_us: average(metrics.flush_total_us, metrics.flush_count),
      flushed_bytes_total: metrics.flushed_bytes_total,
      avg_segment_bytes: average(metrics.flushed_bytes_total, metrics.segment_count)
    }
  end

  defp ensure_metrics(nil), do: zero_metrics()
  defp ensure_metrics(metrics), do: Map.merge(zero_metrics(), metrics)

  defp normalize_state(state) do
    buffers =
      state
      |> Map.get(:buffers, %{})
      |> Enum.into(%{}, fn {mission_id, buffer} -> {mission_id, normalize_buffer(buffer)} end)

    buffer_sizes =
      case Map.get(state, :buffer_sizes) do
        nil ->
          build_buffer_sizes(buffers)

        buffer_sizes ->
          Enum.reduce(buffers, buffer_sizes, fn {mission_id, buffer}, acc ->
            Map.put_new(acc, mission_id, buffer_length(buffer))
          end)
      end

    state
    |> Map.put(:buffers, buffers)
    |> Map.put(:buffer_sizes, buffer_sizes)
  end

  defp normalize_buffer(buffer) when is_list(buffer), do: :queue.from_list(buffer)

  defp normalize_buffer({front, rear} = queue) when is_list(front) and is_list(rear), do: queue

  defp build_buffer_sizes(buffers) do
    Enum.into(buffers, %{}, fn {mission_id, buffer} -> {mission_id, buffer_length(buffer)} end)
  end

  defp buffer_length(buffer) when is_list(buffer), do: length(buffer)

  defp buffer_length({front, rear}) when is_list(front) and is_list(rear),
    do: :queue.len({front, rear})

  defp normalize_records_batch(records_batch) do
    Enum.reduce_while(records_batch, {:ok, []}, fn
      {%RawEvidence{} = raw_evidence, transfer_frame_records, packet_records}, {:ok, acc}
      when is_list(transfer_frame_records) and is_list(packet_records) ->
        entries = FileSystem.build_entries(raw_evidence, transfer_frame_records, packet_records)
        {:cont, {:ok, [{raw_evidence.mission_id, entries} | acc]}}

      _other, {:ok, _acc} ->
        {:halt, {:error, :invalid_protocol_record_batch}}
    end)
    |> case do
      {:ok, mission_entries} -> {:ok, Enum.reverse(mission_entries)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp enqueue_entries(state, []), do: state

  defp enqueue_entries(state, mission_entries) do
    enqueue_ms = System.monotonic_time(:millisecond)

    mission_entries
    |> Enum.reject(fn {_mission_id, entries} -> entries == [] end)
    |> Enum.group_by(fn {mission_id, _entries} -> mission_id end, fn {_mission_id, entries} ->
      entries
    end)
    |> Enum.reduce(state, fn {mission_id, entry_lists}, acc ->
      merged_entries = List.flatten(entry_lists)
      buffered_queue = Map.get(acc.buffers, mission_id, :queue.new())
      buffered_size = Map.get(acc.buffer_sizes, mission_id, 0)
      next_queue = queue_join(buffered_queue, merged_entries)
      next_size = buffered_size + length(merged_entries)

      next_state =
        acc
        |> put_in([:buffers, mission_id], next_queue)
        |> put_in([:buffer_sizes, mission_id], next_size)
        |> maybe_mark_buffer_started(mission_id, buffered_size, enqueue_ms)
        |> maybe_schedule_flush(mission_id)

      if next_size >= next_state.flush_count do
        reschedule_flush(next_state, mission_id, 0)
      else
        next_state
      end
    end)
  end

  defp queue_join(queue, []), do: queue

  defp queue_join(queue, entries) do
    :queue.join(queue, :queue.from_list(entries))
  end

  defp zero_metrics do
    %{
      flush_count: 0,
      flush_failure_count: 0,
      last_flush_error: nil,
      last_completed_at: nil,
      flushed_count: 0,
      segment_count: 0,
      flush_total_us: 0,
      flushed_bytes_total: 0
    }
  end

  defp average(_total, 0), do: 0.0
  defp average(total, count), do: total / count

  defp server(opts), do: Keyword.get(opts, :name, __MODULE__)
end
