defmodule Cadence.Protocol.RecordArchive.FileSystem.Writer do
  @moduledoc false
  # The archive's writers (#688): one `Writer.Mission` process per partition, started on demand
  # under a DynamicSupervisor and found through a Registry, so a slow or failing flush stalls only
  # its own partition. `partition_key/1` is the one place that decides the partition (a mission
  # today); moving to a finer key (a path) changes only that function.

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.{PacketRecord, TransferFrameRecord}
  alias Cadence.Protocol.RecordArchive.FileSystem
  alias Cadence.Protocol.RecordArchive.FileSystem.Writer.Mission
  alias Cadence.Repo

  @default_flush_interval_ms 250
  @default_flush_count 250

  @type batch :: [{RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()]}]

  @doc "The partition one piece of evidence is archived under: `{mission_id, partition}`."
  @spec partition_key(RawEvidence.t()) :: {binary(), term()}
  def partition_key(%RawEvidence{mission_id: mission_id}), do: {mission_id, nil}

  def child_spec(opts) when is_list(opts) do
    %{
      id: Keyword.get(opts, :child_id, server(opts)),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  def start_link(opts) when is_list(opts) do
    Supervisor.start_link(
      [
        {Registry, keys: :unique, name: registry(opts)},
        {DynamicSupervisor, strategy: :one_for_one, name: writers(opts)}
      ],
      strategy: :one_for_all,
      name: server(opts)
    )
  end

  @spec enqueue(RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()]) ::
          :ok | {:error, term()}
  def enqueue(raw_evidence, transfer_frame_records, packet_records),
    do: enqueue(raw_evidence, transfer_frame_records, packet_records, [])

  @spec enqueue(RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()], keyword()) ::
          :ok | {:error, term()}
  def enqueue(%RawEvidence{} = raw_evidence, transfer_frame_records, packet_records, opts)
      when is_list(transfer_frame_records) and is_list(packet_records) and is_list(opts),
      do: enqueue_many([{raw_evidence, transfer_frame_records, packet_records}], opts)

  @spec enqueue_many(batch()) :: :ok | {:error, term()}
  def enqueue_many(records_batch), do: enqueue_many(records_batch, [])

  @spec enqueue_many(batch(), keyword()) :: :ok | {:error, term()}
  def enqueue_many(records_batch, opts) when is_list(records_batch) and is_list(opts) do
    with {:ok, by_partition} <- build_entries(records_batch),
         :ok <- check_backpressure(by_partition, opts) do
      enqueue_partitions(by_partition, opts)
    end
  end

  defp enqueue_partitions(by_partition, opts) do
    Enum.reduce_while(by_partition, :ok, fn {key, entries}, :ok ->
      case call(opts, key, {:enqueue, entries}, 5_000) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec flush(binary() | nil) :: :ok | {:error, term()}
  def flush(mission_id \\ nil), do: flush(mission_id, [])

  @spec flush(binary() | nil, keyword()) :: :ok | {:error, term()}
  def flush(mission_id, opts)
      when (is_binary(mission_id) or is_nil(mission_id)) and is_list(opts) do
    mission_id
    |> running(opts)
    |> Enum.reduce_while(:ok, fn key, :ok ->
      case call_running(opts, key, :flush, :infinity) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec stats(binary()) :: map()
  def stats(mission_id), do: stats(mission_id, [])

  @spec stats(binary(), keyword()) :: map()
  def stats(mission_id, opts) when is_binary(mission_id) and is_list(opts) do
    case running(mission_id, opts) do
      [] -> Mission.idle_stats()
      keys -> keys |> Enum.map(&call_running(opts, &1, :stats, 5_000)) |> merge_stats()
    end
  end

  @spec reset_stats(binary()) :: :ok
  def reset_stats(mission_id), do: reset_stats(mission_id, [])

  @spec reset_stats(binary(), keyword()) :: :ok
  def reset_stats(mission_id, opts) when is_binary(mission_id) and is_list(opts) do
    mission_id |> running(opts) |> Enum.each(&call_running(opts, &1, :reset_stats, 5_000))
  end

  @spec reset() :: :ok
  def reset, do: reset([])

  @spec reset(keyword()) :: :ok
  def reset(opts) when is_list(opts) do
    nil |> running(opts) |> Enum.each(&call_running(opts, &1, :reset, :infinity))
    _ = File.rm_rf(Keyword.fetch!(opts, :base_path))
    :ok
  end

  # One batch can name several missions: they are checked first, so a backpressured partition
  # refuses the whole batch before any other partition has taken a copy of it.
  defp check_backpressure(by_partition, _opts) when length(by_partition) < 2, do: :ok

  defp check_backpressure(by_partition, opts) do
    Enum.find_value(by_partition, :ok, fn {{mission_id, _partition} = key, _entries} ->
      if call_running(opts, key, :backpressured?, 5_000) == true,
        do: {:error, {:protocol_archive_backpressured, mission_id}}
    end)
  end

  # The caller builds the entries, so the writer only buffers and writes.
  defp build_entries(records_batch) do
    records_batch
    |> Enum.reduce_while({:ok, []}, fn
      {%RawEvidence{} = raw_evidence, transfer_frame_records, packet_records}, {:ok, acc}
      when is_list(transfer_frame_records) and is_list(packet_records) ->
        entries = FileSystem.build_entries(raw_evidence, transfer_frame_records, packet_records)
        {:cont, {:ok, [{partition_key(raw_evidence), entries} | acc]}}

      _other, {:ok, _acc} ->
        {:halt, {:error, :invalid_protocol_record_batch}}
    end)
    |> case do
      {:ok, keyed} ->
        {:ok,
         keyed
         |> Enum.reverse()
         |> Enum.reject(fn {_key, entries} -> entries == [] end)
         |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
         |> Enum.map(fn {key, lists} -> {key, Enum.concat(lists)} end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Starts the partition's writer if needed; a writer that idled out between the lookup and the
  # call is started again once.
  defp call(opts, key, message, timeout, attempts \\ 2) do
    pid = ensure_started(opts, key)
    GenServer.call(pid, message, timeout)
  catch
    :exit, {reason, _call} when reason in [:noproc, :normal] and attempts > 1 ->
      call(opts, key, message, timeout, attempts - 1)
  end

  defp call_running(opts, key, message, timeout) do
    case Registry.lookup(registry(opts), key) do
      [{pid, _value}] ->
        try do
          GenServer.call(pid, message, timeout)
        catch
          :exit, {reason, _call} when reason in [:noproc, :normal] -> idle_reply(message)
        end

      [] ->
        idle_reply(message)
    end
  end

  defp idle_reply(:stats), do: Mission.idle_stats()
  defp idle_reply(:backpressured?), do: false
  defp idle_reply(_message), do: :ok

  defp ensure_started(opts, {mission_id, _partition} = key) do
    case Registry.lookup(registry(opts), key) do
      [{pid, _value}] ->
        pid

      [] ->
        child =
          {Mission,
           name: {:via, Registry, {registry(opts), key}},
           mission_id: mission_id,
           base_path: Keyword.fetch!(opts, :base_path),
           repo: Keyword.get(opts, :repo, Repo),
           archive_backend: FileSystem.archive_backend(opts),
           flush_interval_ms: Keyword.get(opts, :flush_interval_ms, @default_flush_interval_ms),
           flush_count: Keyword.get(opts, :flush_count, @default_flush_count)}

        case DynamicSupervisor.start_child(writers(opts), child) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end
    end
  end

  # The keys of the running writers: a mission's, or all of them for `nil`.
  defp running(mission_id, opts) do
    guard = if mission_id, do: [{:==, {:element, 1, :"$1"}, mission_id}], else: []
    Registry.select(registry(opts), [{{:"$1", :_, :_}, guard, [:"$1"]}])
  end

  defp merge_stats([one]), do: one

  defp merge_stats(many) do
    sum = fn field -> many |> Enum.map(& &1[field]) |> Enum.sum() end
    flushes = sum.(:flush_count)
    segments = sum.(:segment_count)

    many
    |> hd()
    |> Map.merge(%{
      queue_depth: sum.(:queue_depth),
      processing?: Enum.any?(many, & &1.processing?),
      backpressured?: Enum.any?(many, & &1.backpressured?),
      oldest_buffered_age_ms: many |> Enum.map(& &1.oldest_buffered_age_ms) |> Enum.max(),
      flush_count: flushes,
      flush_failure_count: sum.(:flush_failure_count),
      flushed_count: sum.(:flushed_count),
      batches_flushed: sum.(:batches_flushed),
      avg_batches_per_flush: ratio(sum.(:batches_flushed), flushes),
      segment_count: segments,
      flush_total_us: sum.(:flush_total_us),
      avg_flush_us: ratio(sum.(:flush_total_us), flushes),
      flushed_bytes_total: sum.(:flushed_bytes_total),
      avg_segment_bytes: ratio(sum.(:flushed_bytes_total), segments)
    })
  end

  defp ratio(_total, 0), do: 0.0
  defp ratio(total, count), do: total / count

  defp server(opts), do: Keyword.get(opts, :name, __MODULE__)
  defp registry(opts), do: Module.concat(server(opts), Registry)
  defp writers(opts), do: Module.concat(server(opts), Writers)
end
