defmodule Cadence.IngressJournal.FileSystem do
  @moduledoc """
  Path-local, bounded, append-only ingress byte journal.

  The writer publishes an entry only after its complete record has been
  written. In `:sync` durability mode it also calls `fdatasync` before replying
  to the producer. Recovery validates every record checksum and truncates an
  incomplete or corrupt tail before accepting new writes.

  Consumer cursors are checkpointed independently. Segments are reclaimed only
  when every required cursor has durably advanced beyond the segment.
  """

  use GenServer

  require Logger

  alias Cadence.IngressJournal.{Entry, Identity}

  @record_magic "CIJR"
  @record_version 1
  @record_header_bytes 70
  @default_max_bytes 8 * 1_024 * 1_024 * 1_024
  @default_segment_bytes 256 * 1_024 * 1_024
  @default_capture_record_bytes 256 * 1_024
  @default_checkpoint_interval_ms 250
  @default_consumers [:processing, :archive]
  @event_prefix [:cadence, :ingress_journal]
  @file_system_policy_keys [
    :base_path,
    :durability,
    :consumers,
    :capture_record_bytes,
    :checkpoint_interval_ms,
    :max_bytes,
    :segment_bytes
  ]
  @consumer_policy_keys [
    :processing_poll_interval_ms,
    :processing_max_batch_entries,
    :processing_max_batch_bytes
  ]

  @type consumer :: atom()
  @type durability :: :sync | :page_cache
  @type policy :: %{
          required(:enabled?) => boolean(),
          required(:file_system_opts) => keyword(),
          required(:consumer_opts) => keyword()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    case Keyword.get(opts, :name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: {:ingress_journal, Keyword.fetch!(opts, :provider_binding_id)},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 10_000
    }
  end

  @spec append(GenServer.server(), binary(), DateTime.t(), map()) ::
          {:ok, Entry.t()} | {:error, term()}
  def append(journal, payload, %DateTime{} = receipt_time, metadata \\ %{})
      when is_binary(payload) and byte_size(payload) > 0 and is_map(metadata) do
    call_if_running(
      journal,
      {:append, payload, receipt_time, metadata, System.monotonic_time()},
      :infinity
    )
  end

  @doc """
  Appends stream bytes as one admitted batch of bounded logical records.

  Capacity is checked for the complete batch before any record is written.
  The returned entries preserve the exact byte order and absolute offsets of
  the input, independently of the producer's receive boundary.
  """
  @spec append_stream(GenServer.server(), binary(), DateTime.t(), map()) ::
          {:ok, [Entry.t()]} | {:error, term()}
  def append_stream(journal, payload, %DateTime{} = receipt_time, metadata \\ %{})
      when is_binary(payload) and byte_size(payload) > 0 and is_map(metadata) do
    call_if_running(
      journal,
      {:append_stream, payload, receipt_time, metadata, System.monotonic_time()},
      :infinity
    )
  end

  @spec next_entry(GenServer.server(), consumer()) ::
          {:ok, Entry.t()} | :empty | {:error, term()}
  def next_entry(journal, consumer) when is_atom(consumer) do
    call_if_running(journal, {:next_entry, consumer})
  end

  @spec next_entries(GenServer.server(), consumer(), pos_integer(), pos_integer()) ::
          {:ok, [Entry.t()]} | :empty | {:error, term()}
  def next_entries(journal, consumer, max_entries, max_bytes)
      when is_atom(consumer) and is_integer(max_entries) and max_entries > 0 and
             is_integer(max_bytes) and max_bytes > 0 do
    call_if_running(journal, {:next_entries, consumer, max_entries, max_bytes})
  end

  @spec acknowledge(GenServer.server(), consumer() | [consumer()], non_neg_integer()) ::
          :ok | {:error, term()}
  def acknowledge(journal, consumers, end_offset)
      when is_integer(end_offset) and end_offset >= 0 do
    consumers = if is_list(consumers), do: consumers, else: [consumers]
    call_if_running(journal, {:acknowledge, consumers, end_offset})
  end

  @spec snapshot(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def snapshot(journal), do: call_if_running(journal, :snapshot)

  @spec lookup(GenServer.server()) :: {:ok, pid()} | {:error, term()}
  def lookup(server)

  def lookup(server) when is_pid(server) do
    if Process.alive?(server),
      do: {:ok, server},
      else: {:error, :ingress_journal_not_running}
  end

  def lookup(server) do
    case GenServer.whereis(server) do
      nil -> {:error, :ingress_journal_not_running}
      pid -> {:ok, pid}
    end
  end

  @doc false
  @spec policy(keyword() | map()) :: policy()
  def policy(config) when is_list(config) or is_map(config) do
    config = if is_map(config), do: Map.to_list(config), else: config

    %{
      enabled?: Keyword.get(config, :enabled?, false),
      file_system_opts: Keyword.take(config, @file_system_policy_keys),
      consumer_opts: Keyword.take(config, @consumer_policy_keys)
    }
  end

  @doc false
  @spec configured_policy() :: policy()
  def configured_policy do
    :cadence
    |> Application.get_env(:ingress_journal, [])
    |> policy()
  end

  @impl true
  def init(opts) do
    context = %{
      mission_id: Keyword.fetch!(opts, :mission_id),
      realized_contact_id: Keyword.fetch!(opts, :realized_contact_id),
      path_id: Keyword.fetch!(opts, :path_id),
      provider_binding_id: Keyword.fetch!(opts, :provider_binding_id)
    }

    config =
      opts
      |> Keyword.get_lazy(:policy, &configured_policy/0)
      |> Map.fetch!(:file_system_opts)

    base_path = Keyword.get_lazy(opts, :base_path, fn -> Keyword.fetch!(config, :base_path) end)
    stream_id = stream_id(context)
    stream_path = Path.join(base_path, stream_id)
    durability = Keyword.get(opts, :durability, Keyword.get(config, :durability, :sync))
    consumers = Keyword.get(opts, :consumers, Keyword.get(config, :consumers, @default_consumers))

    capture_record_bytes =
      Keyword.get(
        opts,
        :capture_record_bytes,
        Keyword.get(config, :capture_record_bytes, @default_capture_record_bytes)
      )

    with :ok <- validate_durability(durability),
         :ok <- validate_positive_integer(:capture_record_bytes, capture_record_bytes),
         :ok <- File.mkdir_p(stream_path),
         :ok <- ensure_stream_metadata(stream_path, stream_id, context),
         {:ok, checkpoint} <- load_checkpoint(stream_path, consumers),
         {:ok, recovered} <- recover_segments(stream_path, stream_id, checkpoint),
         {:ok, file} <- open_active_segment(stream_path, recovered.active_segment_start) do
      checkpoint_interval_ms =
        Keyword.get(
          opts,
          :checkpoint_interval_ms,
          Keyword.get(config, :checkpoint_interval_ms, @default_checkpoint_interval_ms)
        )

      state = %{
        context: context,
        stream_id: stream_id,
        stream_path: stream_path,
        durability: durability,
        max_bytes:
          Keyword.get(opts, :max_bytes, Keyword.get(config, :max_bytes, @default_max_bytes)),
        segment_bytes:
          Keyword.get(
            opts,
            :segment_bytes,
            Keyword.get(config, :segment_bytes, @default_segment_bytes)
          ),
        capture_record_bytes: capture_record_bytes,
        checkpoint_interval_ms: checkpoint_interval_ms,
        checkpoint_writer: Keyword.get(opts, :checkpoint_writer, &checkpoint_cursors/4),
        consumers: MapSet.new(consumers),
        cursors: checkpoint.cursors,
        durable_cursors: checkpoint.cursors,
        cursors_dirty?: false,
        checkpoint_in_flight: nil,
        entries: recovered.entries,
        segments: recovered.segments,
        active_segment_start: recovered.active_segment_start,
        active_segment_path: recovered.active_segment_path,
        active_file: file,
        active_file_bytes: recovered.active_file_bytes,
        retained_bytes: recovered.retained_bytes,
        next_offset: recovered.next_offset,
        next_sequence: recovered.next_sequence,
        appended_entries: recovered.entry_count,
        appended_bytes: recovered.next_offset,
        max_appended_entry_bytes: max_entry_bytes(recovered.entries),
        reclaimed_segments: recovered.reclaimed_segments,
        full_count: 0,
        recovery_truncations: recovered.recovery_truncations,
        last_append_at: nil,
        last_error: nil
      }

      schedule_checkpoint(checkpoint_interval_ms)
      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:append, payload, receipt_time, metadata, queued_at}, _from, state) do
    started_at = System.monotonic_time()
    metadata = put_capture_batch_metadata(metadata, state, byte_size(payload))
    metadata_binary = :erlang.term_to_binary(metadata, [:compressed])
    record_bytes = @record_header_bytes + byte_size(metadata_binary) + byte_size(payload)

    if state.retained_bytes + record_bytes > state.max_bytes do
      emit(:capacity_exhausted, state, %{retained_bytes: state.retained_bytes}, %{})
      {:reply, {:error, :ingress_journal_full}, %{state | full_count: state.full_count + 1}}
    else
      case append_record(
             state,
             payload,
             receipt_time,
             metadata,
             metadata_binary,
             record_bytes,
             true
           ) do
        {:ok, entry, next_state} ->
          emit_append(next_state, [entry], queued_at, started_at)
          {:reply, {:ok, entry}, next_state}

        {:error, reason, next_state} ->
          {:reply, {:error, reason}, next_state}
      end
    end
  end

  def handle_call({:append_stream, payload, receipt_time, metadata, queued_at}, _from, state) do
    started_at = System.monotonic_time()
    metadata = put_capture_batch_metadata(metadata, state, byte_size(payload))
    metadata_binary = :erlang.term_to_binary(metadata, [:compressed])
    chunks = split_payload(payload, state.capture_record_bytes)

    batch_record_bytes =
      Enum.reduce(chunks, 0, fn chunk, total ->
        total + @record_header_bytes + byte_size(metadata_binary) + byte_size(chunk)
      end)

    if state.retained_bytes + batch_record_bytes > state.max_bytes do
      emit(:capacity_exhausted, state, %{retained_bytes: state.retained_bytes}, %{})
      {:reply, {:error, :ingress_journal_full}, %{state | full_count: state.full_count + 1}}
    else
      case append_stream_records(state, chunks, receipt_time, metadata, metadata_binary, []) do
        {:ok, entries, next_state} ->
          emit_append(next_state, entries, queued_at, started_at)
          {:reply, {:ok, entries}, next_state}

        {:error, reason, next_state} ->
          {:reply, {:error, reason}, next_state}
      end
    end
  end

  def handle_call({:next_entry, consumer}, _from, state) do
    if MapSet.member?(state.consumers, consumer) do
      cursor = Map.fetch!(state.cursors, consumer)

      reply =
        case :gb_trees.lookup(cursor, state.entries) do
          {:value, entry} -> {:ok, entry}
          :none when cursor == state.next_offset -> :empty
          :none -> {:error, {:ingress_journal_cursor_gap, consumer, cursor}}
        end

      {:reply, reply, state}
    else
      {:reply, {:error, {:unknown_ingress_journal_consumer, consumer}}, state}
    end
  end

  def handle_call({:next_entries, consumer, max_entries, max_bytes}, _from, state) do
    if MapSet.member?(state.consumers, consumer) do
      cursor = Map.fetch!(state.cursors, consumer)

      reply =
        case :gb_trees.lookup(cursor, state.entries) do
          {:value, _entry} ->
            entries =
              cursor
              |> :gb_trees.iterator_from(state.entries)
              |> take_entries(max_entries, max_bytes, [], 0, 0)

            {:ok, entries}

          :none when cursor == state.next_offset ->
            :empty

          :none ->
            {:error, {:ingress_journal_cursor_gap, consumer, cursor}}
        end

      {:reply, reply, state}
    else
      {:reply, {:error, {:unknown_ingress_journal_consumer, consumer}}, state}
    end
  end

  def handle_call({:acknowledge, consumers, end_offset}, _from, state) do
    case validate_acknowledgement(state, consumers, end_offset) do
      :ok ->
        cursors = Enum.reduce(consumers, state.cursors, &Map.put(&2, &1, end_offset))
        {:reply, :ok, %{state | cursors: cursors, cursors_dirty?: true}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:snapshot, _from, state) do
    min_cursor = minimum_cursor(state.cursors)

    {:reply,
     {:ok,
      Map.merge(state.context, %{
        stream_id: state.stream_id,
        stream_path: state.stream_path,
        durability: state.durability,
        max_bytes: state.max_bytes,
        segment_bytes: state.segment_bytes,
        capture_record_bytes: state.capture_record_bytes,
        retained_bytes: state.retained_bytes,
        utilization_ratio: state.retained_bytes / state.max_bytes,
        next_offset: state.next_offset,
        cursors: state.cursors,
        durable_cursors: state.durable_cursors,
        checkpoint_in_flight?: not is_nil(state.checkpoint_in_flight),
        lag_bytes:
          Map.new(state.cursors, fn {consumer, cursor} ->
            {consumer, state.next_offset - cursor}
          end),
        minimum_cursor: min_cursor,
        entry_count: :gb_trees.size(state.entries),
        segment_count: length(state.segments),
        appended_entries: state.appended_entries,
        appended_bytes: state.appended_bytes,
        max_appended_entry_bytes: state.max_appended_entry_bytes,
        reclaimed_segments: state.reclaimed_segments,
        full_count: state.full_count,
        recovery_truncations: state.recovery_truncations,
        last_append_at: state.last_append_at,
        last_error: state.last_error
      })}, state}
  end

  @impl true
  def handle_info({:checkpoint, scheduled_at}, state) do
    next_state =
      maybe_start_checkpoint(
        state,
        checkpoint_queue_wait_us(scheduled_at, state.checkpoint_interval_ms),
        message_queue_len()
      )

    schedule_checkpoint(state.checkpoint_interval_ms)
    {:noreply, next_state}
  end

  def handle_info(
        {:checkpoint_complete, operation_ref, result, checkpoint_duration_us},
        %{checkpoint_in_flight: %{operation_ref: operation_ref} = checkpoint} = state
      ) do
    Process.demonitor(checkpoint.monitor_ref, [:flush])

    {:noreply,
     finish_checkpoint(
       %{state | checkpoint_in_flight: nil},
       checkpoint,
       result,
       checkpoint_duration_us
     )}
  end

  def handle_info({:checkpoint_complete, _operation_ref, _result, _duration_us}, state),
    do: {:noreply, state}

  def handle_info(
        {:DOWN, monitor_ref, :process, _pid, reason},
        %{checkpoint_in_flight: %{monitor_ref: monitor_ref} = checkpoint} = state
      ) do
    duration_us = elapsed_us(checkpoint.started_at)

    {:noreply,
     finish_checkpoint(
       %{state | checkpoint_in_flight: nil},
       checkpoint,
       {:error, {:checkpoint_worker_exit, reason}},
       duration_us
     )}
  end

  def handle_info({:DOWN, _monitor_ref, :process, _pid, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cancel_checkpoint_worker(state.checkpoint_in_flight)

    _ =
      checkpoint_cursors(
        state.stream_path,
        state.cursors,
        state.next_offset,
        state.next_sequence
      )

    _ = maybe_sync(state.active_file, state.durability)
    _ = :file.close(state.active_file)
    :ok
  end

  defp append_record(
         state,
         payload,
         receipt_time,
         metadata,
         metadata_binary,
         record_bytes,
         sync?
       ) do
    case maybe_rotate(state, record_bytes) do
      {:ok, state} ->
        write_record(
          state,
          payload,
          receipt_time,
          metadata,
          metadata_binary,
          record_bytes,
          sync?
        )

      {:error, reason} ->
        {:error, reason, %{state | last_error: inspect(reason)}}
    end
  end

  defp write_record(
         state,
         payload,
         receipt_time,
         metadata,
         metadata_binary,
         record_bytes,
         sync?
       ) do
    checksum = :crypto.hash(:sha256, payload)
    receipt_unix_us = DateTime.to_unix(receipt_time, :microsecond)

    header =
      <<@record_magic::binary, @record_version::unsigned-big-16,
        state.next_sequence::unsigned-big-64, state.next_offset::unsigned-big-64,
        receipt_unix_us::signed-big-64, byte_size(payload)::unsigned-big-32,
        byte_size(metadata_binary)::unsigned-big-32, checksum::binary-size(32)>>

    payload_file_offset =
      state.active_file_bytes + @record_header_bytes + byte_size(metadata_binary)

    with :ok <- :file.write(state.active_file, [header, metadata_binary, payload]),
         :ok <- maybe_sync_record(state.active_file, state.durability, sync?) do
      entry = %Entry{
        stream_id: state.stream_id,
        sequence: state.next_sequence,
        start_offset: state.next_offset,
        end_offset: state.next_offset + byte_size(payload),
        payload_length: byte_size(payload),
        receipt_time: receipt_time,
        metadata: metadata,
        segment_path: state.active_segment_path,
        payload_file_offset: payload_file_offset,
        checksum: checksum
      }

      segments =
        put_segment_entry(state.segments, state.active_segment_start, entry, record_bytes)

      next_state = %{
        state
        | entries: :gb_trees.insert(entry.start_offset, entry, state.entries),
          segments: segments,
          active_file_bytes: state.active_file_bytes + record_bytes,
          retained_bytes: state.retained_bytes + record_bytes,
          next_offset: entry.end_offset,
          next_sequence: state.next_sequence + 1,
          appended_entries: state.appended_entries + 1,
          appended_bytes: state.appended_bytes + entry.payload_length,
          max_appended_entry_bytes: max(state.max_appended_entry_bytes, entry.payload_length),
          last_append_at: receipt_time,
          last_error: nil
      }

      {:ok, entry, next_state}
    else
      {:error, reason} ->
        {:error, {:ingress_journal_append_failed, reason}, %{state | last_error: inspect(reason)}}
    end
  end

  defp append_stream_records(state, [], _receipt_time, _metadata, _metadata_binary, entries) do
    case maybe_sync(state.active_file, state.durability) do
      :ok ->
        {:ok, Enum.reverse(entries), state}

      {:error, reason} ->
        {:error, {:ingress_journal_append_failed, reason}, %{state | last_error: inspect(reason)}}
    end
  end

  defp append_stream_records(
         state,
         [payload | rest],
         receipt_time,
         metadata,
         metadata_binary,
         entries
       ) do
    record_bytes = @record_header_bytes + byte_size(metadata_binary) + byte_size(payload)

    case append_record(
           state,
           payload,
           receipt_time,
           metadata,
           metadata_binary,
           record_bytes,
           false
         ) do
      {:ok, entry, next_state} ->
        append_stream_records(
          next_state,
          rest,
          receipt_time,
          metadata,
          metadata_binary,
          [entry | entries]
        )

      {:error, reason, next_state} ->
        {:error, reason, next_state}
    end
  end

  defp maybe_rotate(state, incoming_bytes)
       when state.active_file_bytes > 0 and
              state.active_file_bytes + incoming_bytes > state.segment_bytes do
    with :ok <- maybe_sync(state.active_file, state.durability),
         :ok <- :file.close(state.active_file),
         {:ok, file} <- open_active_segment(state.stream_path, state.next_offset) do
      path = segment_path(state.stream_path, state.next_offset)

      segments =
        state.segments ++
          [
            %{
              start_offset: state.next_offset,
              end_offset: state.next_offset,
              path: path,
              bytes: 0
            }
          ]

      {:ok,
       %{
         state
         | active_segment_start: state.next_offset,
           active_segment_path: path,
           active_file: file,
           active_file_bytes: 0,
           segments: segments
       }}
    end
  end

  defp maybe_rotate(state, _incoming_bytes), do: {:ok, state}

  defp put_segment_entry(segments, segment_start, %Entry{} = entry, record_bytes) do
    Enum.map(segments, fn
      %{start_offset: ^segment_start} = segment ->
        %{segment | end_offset: entry.end_offset, bytes: segment.bytes + record_bytes}

      segment ->
        segment
    end)
  end

  defp maybe_start_checkpoint(%{cursors_dirty?: false} = state, _queue_wait_us, _queue_depth),
    do: state

  defp maybe_start_checkpoint(%{checkpoint_in_flight: checkpoint} = state, _queue_wait_us, _depth)
       when not is_nil(checkpoint),
       do: state

  defp maybe_start_checkpoint(state, queue_wait_us, queue_depth) do
    started_at = System.monotonic_time()
    operation_ref = make_ref()
    parent = self()
    cursors = state.cursors
    stream_path = state.stream_path
    next_offset = state.next_offset
    next_sequence = state.next_sequence

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        checkpoint_started_at = System.monotonic_time()
        result = state.checkpoint_writer.(stream_path, cursors, next_offset, next_sequence)

        send(
          parent,
          {:checkpoint_complete, operation_ref, result, elapsed_us(checkpoint_started_at)}
        )
      end)

    checkpoint = %{
      operation_ref: operation_ref,
      pid: pid,
      monitor_ref: monitor_ref,
      cursors: cursors,
      started_at: started_at,
      queue_wait_us: queue_wait_us,
      queue_depth: queue_depth,
      entry_count_before: :gb_trees.size(state.entries)
    }

    %{state | checkpoint_in_flight: checkpoint}
  end

  defp finish_checkpoint(state, checkpoint, :ok, checkpoint_duration_us) do
    reclaim_started_at = System.monotonic_time()

    {next_state, reclaimed} =
      state
      |> Map.put(:durable_cursors, checkpoint.cursors)
      |> Map.put(:cursors_dirty?, state.cursors != checkpoint.cursors)
      |> reclaim_segments()

    emit_checkpoint(
      next_state,
      checkpoint,
      checkpoint_duration_us,
      elapsed_us(reclaim_started_at),
      reclaimed,
      :ok
    )

    next_state
  end

  defp finish_checkpoint(state, checkpoint, {:error, reason}, checkpoint_duration_us) do
    Logger.error("Ingress journal cursor checkpoint failed: #{inspect(reason)}")
    next_state = %{state | last_error: inspect(reason), cursors_dirty?: true}

    emit_checkpoint(
      next_state,
      checkpoint,
      checkpoint_duration_us,
      0,
      %{bytes: 0, entries: 0, segments: 0},
      :error
    )

    next_state
  end

  defp emit_checkpoint(
         state,
         checkpoint,
         checkpoint_duration_us,
         reclaim_duration_us,
         reclaimed,
         outcome
       ) do
    emit(
      :maintenance,
      state,
      %{
        duration_us: elapsed_us(checkpoint.started_at),
        queue_wait_us: checkpoint.queue_wait_us,
        checkpoint_duration_us: checkpoint_duration_us,
        reclaim_duration_us: reclaim_duration_us,
        queue_depth: checkpoint.queue_depth,
        entry_count_before: checkpoint.entry_count_before,
        entry_count_after: :gb_trees.size(state.entries),
        reclaimed_entries: reclaimed.entries,
        reclaimed_segments: reclaimed.segments,
        reclaimed_bytes: reclaimed.bytes
      },
      %{outcome: outcome}
    )
  end

  defp checkpoint_cursors(stream_path, cursors, next_offset, next_sequence) do
    contents =
      :erlang.term_to_binary(%{
        version: 1,
        cursors: cursors,
        next_offset: next_offset,
        next_sequence: next_sequence
      })

    temp_path = Path.join(stream_path, "cursors.tmp")
    cursor_path = Path.join(stream_path, "cursors.term")

    with :ok <- File.write(temp_path, contents, [:binary]),
         {:ok, file} <- :file.open(temp_path, [:read, :write, :binary, :raw]),
         :ok <- :file.sync(file),
         :ok <- :file.close(file) do
      File.rename(temp_path, cursor_path)
    end
  end

  defp cancel_checkpoint_worker(nil), do: :ok

  defp cancel_checkpoint_worker(checkpoint) do
    Process.exit(checkpoint.pid, :kill)

    receive do
      {:DOWN, monitor_ref, :process, pid, _reason}
      when monitor_ref == checkpoint.monitor_ref and pid == checkpoint.pid ->
        :ok
    after
      1_000 ->
        Process.demonitor(checkpoint.monitor_ref, [:flush])
        :ok
    end

    :ok
  end

  defp reclaim_segments(state) do
    cursor = minimum_cursor(state.durable_cursors)

    {reclaimable, retained} =
      Enum.split_while(state.segments, fn segment ->
        segment.start_offset != state.active_segment_start and segment.end_offset <= cursor
      end)

    {removed, not_removed} = remove_reclaimable_segments(reclaimable)
    reclaimed_bytes = Enum.sum(Enum.map(removed, & &1.bytes))

    {entries, reclaimed_entries} =
      case List.last(removed) do
        nil -> {state.entries, 0}
        segment -> drop_entries_through(state.entries, segment.end_offset, 0)
      end

    if removed != [] do
      emit(
        :reclaim,
        state,
        %{bytes: reclaimed_bytes, entries: reclaimed_entries, segments: length(removed)},
        %{}
      )
    end

    next_state = %{
      state
      | entries: entries,
        segments: not_removed ++ retained,
        retained_bytes: max(state.retained_bytes - reclaimed_bytes, 0),
        reclaimed_segments: state.reclaimed_segments + length(removed)
    }

    {next_state, %{bytes: reclaimed_bytes, entries: reclaimed_entries, segments: length(removed)}}
  end

  defp remove_reclaimable_segments([]), do: {[], []}

  defp remove_reclaimable_segments([segment | rest]) do
    case File.rm(segment.path) do
      :ok ->
        {removed, not_removed} = remove_reclaimable_segments(rest)
        {[segment | removed], not_removed}

      {:error, :enoent} ->
        {removed, not_removed} = remove_reclaimable_segments(rest)
        {[segment | removed], not_removed}

      {:error, reason} ->
        Logger.warning("Ingress journal segment reclaim failed: #{inspect(reason)}")
        {[], [segment | rest]}
    end
  end

  defp drop_entries_through(entries, end_offset, reclaimed_entries) do
    if :gb_trees.is_empty(entries) do
      {entries, reclaimed_entries}
    else
      {_start_offset, entry, remaining} = :gb_trees.take_smallest(entries)

      if entry.end_offset <= end_offset do
        drop_entries_through(remaining, end_offset, reclaimed_entries + 1)
      else
        {entries, reclaimed_entries}
      end
    end
  end

  defp validate_acknowledgement(state, consumers, end_offset) do
    cond do
      consumers == [] ->
        {:error, :ingress_journal_ack_requires_consumer}

      Enum.any?(consumers, &(not MapSet.member?(state.consumers, &1))) ->
        {:error, {:unknown_ingress_journal_consumer, consumers}}

      end_offset > state.next_offset ->
        {:error, {:ingress_journal_ack_beyond_tail, end_offset, state.next_offset}}

      Enum.any?(consumers, &(end_offset < Map.fetch!(state.cursors, &1))) ->
        {:error, {:ingress_journal_cursor_regression, consumers, end_offset}}

      not valid_entry_boundary?(state, end_offset) ->
        {:error, {:ingress_journal_ack_not_entry_boundary, end_offset}}

      true ->
        :ok
    end
  end

  defp valid_entry_boundary?(state, end_offset) do
    end_offset == 0 or end_offset == state.next_offset or
      :gb_trees.is_defined(end_offset, state.entries)
  end

  defp split_payload(payload, record_bytes) when byte_size(payload) <= record_bytes, do: [payload]

  defp split_payload(payload, record_bytes) do
    <<chunk::binary-size(^record_bytes), rest::binary>> = payload
    [chunk | split_payload(rest, record_bytes)]
  end

  defp max_entry_bytes(entries) do
    entries
    |> :gb_trees.values()
    |> Enum.reduce(0, fn entry, largest -> max(largest, entry.payload_length) end)
  end

  defp put_capture_batch_metadata(metadata, state, payload_bytes) do
    start_offset = state.next_offset
    end_offset = start_offset + payload_bytes

    metadata
    |> Map.put(
      :journal_capture_batch_id,
      Identity.capture_batch_id(state.stream_id, start_offset, end_offset)
    )
    |> Map.put(:journal_capture_batch_start_offset, start_offset)
    |> Map.put(:journal_capture_batch_end_offset, end_offset)
  end

  defp minimum_cursor(cursors) do
    cursors |> Map.values() |> Enum.min(fn -> 0 end)
  end

  defp take_entries(iterator, max_entries, max_bytes, acc, count, bytes) do
    case :gb_trees.next(iterator) do
      :none ->
        Enum.reverse(acc)

      {_offset, %Entry{} = entry, next_iterator} ->
        exceeds_count? = count >= max_entries
        exceeds_bytes? = count > 0 and bytes + entry.payload_length > max_bytes

        if exceeds_count? or exceeds_bytes? do
          Enum.reverse(acc)
        else
          take_entries(
            next_iterator,
            max_entries,
            max_bytes,
            [entry | acc],
            count + 1,
            bytes + entry.payload_length
          )
        end
    end
  end

  defp recover_segments(stream_path, stream_id, checkpoint) do
    segment_paths = Path.wildcard(Path.join(stream_path, "segment-*.cij")) |> Enum.sort()

    initial = %{
      entries: [],
      segments: [],
      next_offset: if(segment_paths == [], do: checkpoint.next_offset, else: 0),
      next_sequence: if(segment_paths == [], do: checkpoint.next_sequence, else: nil),
      retained_bytes: 0,
      entry_count: 0,
      recovery_truncations: 0
    }

    with {:ok, recovered} <-
           Enum.reduce_while(segment_paths, {:ok, initial}, &recover_segment(&1, stream_id, &2)) do
      min_cursor = minimum_cursor(checkpoint.cursors)

      entries =
        recovered.entries
        |> Enum.filter(&(&1.end_offset > min_cursor))
        |> Enum.map(&{&1.start_offset, &1})
        |> :gb_trees.from_orddict()

      {segments, reclaimed_segments} = remove_recovered_segments(recovered.segments, min_cursor)

      {active_segment_start, active_segment_path, active_file_bytes, segments} =
        case List.last(segments) do
          nil ->
            path = segment_path(stream_path, recovered.next_offset)

            segment = %{
              start_offset: recovered.next_offset,
              end_offset: recovered.next_offset,
              path: path,
              bytes: 0
            }

            {recovered.next_offset, path, 0, [segment]}

          segment ->
            {segment.start_offset, segment.path, segment.bytes, segments}
        end

      {:ok,
       %{
         entries: entries,
         segments: segments,
         active_segment_start: active_segment_start,
         active_segment_path: active_segment_path,
         active_file_bytes: active_file_bytes,
         retained_bytes: Enum.sum(Enum.map(segments, & &1.bytes)),
         next_offset: recovered.next_offset,
         next_sequence: recovered.next_sequence || 0,
         entry_count: recovered.entry_count,
         recovery_truncations: recovered.recovery_truncations,
         reclaimed_segments: reclaimed_segments
       }}
    end
  end

  defp recover_segment(path, stream_id, {:ok, recovered}) do
    expected_offset =
      if recovered.segments == [],
        do: segment_start_from_path(path),
        else: recovered.next_offset

    case parse_segment(path, stream_id, expected_offset, recovered.next_sequence) do
      {:ok, entries, valid_bytes, truncated?} ->
        last_entry = List.last(entries)
        next_offset = if last_entry, do: last_entry.end_offset, else: expected_offset
        next_sequence = if last_entry, do: last_entry.sequence + 1, else: recovered.next_sequence

        segment = %{
          start_offset: expected_offset,
          end_offset: next_offset,
          path: path,
          bytes: valid_bytes
        }

        {:cont,
         {:ok,
          %{
            recovered
            | entries: recovered.entries ++ entries,
              segments: recovered.segments ++ [segment],
              next_offset: next_offset,
              next_sequence: next_sequence,
              retained_bytes: recovered.retained_bytes + valid_bytes,
              entry_count: recovered.entry_count + length(entries),
              recovery_truncations:
                recovered.recovery_truncations + if(truncated?, do: 1, else: 0)
          }}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp parse_segment(path, stream_id, expected_offset, expected_sequence) do
    with {:ok, file} <- :file.open(path, [:read, :write, :binary, :raw]),
         {:ok, file_size} <- :file.position(file, :eof) do
      result =
        try do
          {entries, valid_bytes, truncated?} =
            parse_records(
              file,
              file_size,
              path,
              stream_id,
              expected_offset,
              expected_sequence,
              0,
              []
            )

          if truncated? do
            with {:ok, _position} <- :file.position(file, valid_bytes),
                 :ok <- :file.truncate(file),
                 :ok <- :file.sync(file) do
              {:ok, entries, valid_bytes, true}
            end
          else
            {:ok, entries, valid_bytes, false}
          end
        after
          :file.close(file)
        end

      result
    end
  end

  defp parse_records(
         _file,
         file_size,
         _path,
         _stream_id,
         _offset,
         _sequence,
         file_offset,
         entries
       )
       when file_offset == file_size,
       do: {Enum.reverse(entries), file_offset, false}

  defp parse_records(
         file,
         file_size,
         path,
         stream_id,
         expected_offset,
         expected_sequence,
         file_offset,
         entries
       )
       when file_size - file_offset >= @record_header_bytes do
    context = %{
      file_size: file_size,
      path: path,
      stream_id: stream_id,
      expected_offset: expected_offset,
      expected_sequence: expected_sequence,
      file_offset: file_offset,
      entries: entries
    }

    case :file.pread(file, file_offset, @record_header_bytes) do
      {:ok, header} -> parse_record_header(header, file, context)
      _read_failure -> invalid_record(context)
    end
  end

  defp parse_records(
         _file,
         _file_size,
         _path,
         _stream_id,
         _offset,
         _sequence,
         file_offset,
         entries
       ),
       do: {Enum.reverse(entries), file_offset, true}

  defp parse_record_header(header, file, context) do
    case header do
      <<@record_magic::binary, @record_version::unsigned-big-16, sequence::unsigned-big-64,
        start_offset::unsigned-big-64, receipt_unix_us::signed-big-64,
        payload_length::unsigned-big-32, metadata_length::unsigned-big-32,
        checksum::binary-size(32)>>
      when (is_nil(context.expected_sequence) or sequence == context.expected_sequence) and
             start_offset == context.expected_offset and
             payload_length > 0 ->
        parse_record_body(file, context, %{
          sequence: sequence,
          start_offset: start_offset,
          receipt_unix_us: receipt_unix_us,
          payload_length: payload_length,
          metadata_length: metadata_length,
          checksum: checksum
        })

      _invalid_header ->
        invalid_record(context)
    end
  end

  defp parse_record_body(file, context, header) do
    record_body_bytes = header.metadata_length + header.payload_length
    body_offset = context.file_offset + @record_header_bytes

    if context.file_size - body_offset >= record_body_bytes do
      decode_record_body(file, context, header, body_offset, record_body_bytes)
    else
      invalid_record(context)
    end
  end

  defp decode_record_body(file, context, header, body_offset, record_body_bytes) do
    metadata_length = header.metadata_length
    payload_length = header.payload_length

    with {:ok, body} <- :file.pread(file, body_offset, record_body_bytes),
         <<metadata_binary::binary-size(^metadata_length), payload::binary-size(^payload_length)>> <-
           body,
         {:ok, metadata} <- safe_metadata(metadata_binary),
         true <- :crypto.hash(:sha256, payload) == header.checksum,
         {:ok, receipt_time} <- DateTime.from_unix(header.receipt_unix_us, :microsecond) do
      entry = %Entry{
        stream_id: context.stream_id,
        sequence: header.sequence,
        start_offset: header.start_offset,
        end_offset: header.start_offset + header.payload_length,
        payload_length: header.payload_length,
        receipt_time: receipt_time,
        metadata: metadata,
        segment_path: context.path,
        payload_file_offset: body_offset + header.metadata_length,
        checksum: header.checksum
      }

      parse_records(
        file,
        context.file_size,
        context.path,
        context.stream_id,
        entry.end_offset,
        header.sequence + 1,
        context.file_offset + @record_header_bytes + record_body_bytes,
        [entry | context.entries]
      )
    else
      _invalid -> invalid_record(context)
    end
  end

  defp invalid_record(context), do: {Enum.reverse(context.entries), context.file_offset, true}

  defp safe_metadata(binary) do
    case :erlang.binary_to_term(binary, [:safe]) do
      metadata when is_map(metadata) -> {:ok, metadata}
      _other -> {:error, :invalid_metadata}
    end
  rescue
    ArgumentError -> {:error, :invalid_metadata}
  end

  defp remove_recovered_segments(segments, min_cursor) do
    {removable, retained} =
      Enum.split_with(segments, fn segment -> segment.end_offset <= min_cursor end)

    Enum.each(removable, fn segment -> _ = File.rm(segment.path) end)
    {retained, length(removable)}
  end

  defp load_checkpoint(stream_path, consumers) do
    cursor_path = Path.join(stream_path, "cursors.term")

    with {:ok, binary} <- File.read(cursor_path),
         %{version: 1, cursors: stored} = checkpoint when is_map(stored) <-
           :erlang.binary_to_term(binary, [:safe]) do
      {:ok,
       %{
         cursors: Map.new(consumers, &{&1, Map.get(stored, &1, 0)}),
         next_offset: Map.get(checkpoint, :next_offset, 0),
         next_sequence: Map.get(checkpoint, :next_sequence, 0)
       }}
    else
      {:error, :enoent} ->
        {:ok, %{cursors: Map.new(consumers, &{&1, 0}), next_offset: 0, next_sequence: 0}}

      _invalid ->
        {:error, :invalid_ingress_journal_cursor_checkpoint}
    end
  rescue
    ArgumentError -> {:error, :invalid_ingress_journal_cursor_checkpoint}
  end

  defp ensure_stream_metadata(stream_path, stream_id, context) do
    path = Path.join(stream_path, "stream.term")
    expected = %{version: 1, stream_id: stream_id, context: context}

    case File.read(path) do
      {:ok, binary} ->
        if :erlang.binary_to_term(binary, [:safe]) == expected,
          do: :ok,
          else: {:error, :ingress_journal_stream_identity_mismatch}

      {:error, :enoent} ->
        File.write(path, :erlang.term_to_binary(expected), [:binary, :exclusive])

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    ArgumentError -> {:error, :invalid_ingress_journal_stream_metadata}
  end

  defp stream_id(context) do
    digest =
      [
        context.mission_id,
        context.realized_contact_id,
        context.path_id,
        context.provider_binding_id
      ]
      |> Enum.join("\0")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "stream-" <> digest
  end

  defp open_active_segment(stream_path, start_offset) do
    :file.open(segment_path(stream_path, start_offset), [:append, :binary, :raw])
  end

  defp segment_path(stream_path, start_offset) do
    Path.join(
      stream_path,
      "segment-#{String.pad_leading(Integer.to_string(start_offset), 20, "0")}.cij"
    )
  end

  defp segment_start_from_path(path) do
    path
    |> Path.basename(".cij")
    |> String.replace_prefix("segment-", "")
    |> String.to_integer()
  end

  defp maybe_sync(file, :sync), do: :file.datasync(file)
  defp maybe_sync(_file, :page_cache), do: :ok

  defp maybe_sync_record(file, durability, true), do: maybe_sync(file, durability)
  defp maybe_sync_record(_file, _durability, false), do: :ok

  defp validate_durability(mode) when mode in [:sync, :page_cache], do: :ok
  defp validate_durability(mode), do: {:error, {:invalid_ingress_journal_durability, mode}}

  defp validate_positive_integer(_name, value) when is_integer(value) and value > 0, do: :ok

  defp validate_positive_integer(name, value),
    do: {:error, {:invalid_ingress_journal_config, name, value}}

  defp schedule_checkpoint(interval_ms) do
    Process.send_after(self(), {:checkpoint, System.monotonic_time()}, interval_ms)
  end

  defp checkpoint_queue_wait_us(scheduled_at, interval_ms) do
    expected_delay = System.convert_time_unit(interval_ms, :millisecond, :native)

    System.monotonic_time()
    |> Kernel.-(scheduled_at)
    |> Kernel.-(expected_delay)
    |> max(0)
    |> System.convert_time_unit(:native, :microsecond)
  end

  defp message_queue_len do
    case Process.info(self(), :message_queue_len) do
      {:message_queue_len, length} -> length
      nil -> 0
    end
  end

  defp elapsed_us(started_at) do
    elapsed_us(started_at, System.monotonic_time())
  end

  defp elapsed_us(started_at, ended_at) do
    System.convert_time_unit(ended_at - started_at, :native, :microsecond)
  end

  defp call_if_running(server, request, timeout \\ 5_000) do
    with {:ok, pid} <- lookup(server) do
      GenServer.call(pid, request, timeout)
    end
  end

  defp emit(event, state, measurements, metadata) do
    :telemetry.execute(
      @event_prefix ++ [event],
      measurements,
      state.context
      |> Map.merge(%{durability: state.durability, stream_id: state.stream_id})
      |> Map.merge(metadata)
    )
  end

  defp emit_append(state, entries, queued_at, started_at) do
    emit(
      :append,
      state,
      %{
        bytes: Enum.sum(Enum.map(entries, & &1.payload_length)),
        record_count: length(entries),
        queue_wait_us: elapsed_us(queued_at, started_at),
        duration_us: elapsed_us(started_at),
        retained_bytes: state.retained_bytes
      },
      %{}
    )

    Enum.each(entries, fn entry ->
      emit(:record, state, %{bytes: entry.payload_length}, %{})
    end)
  end
end
