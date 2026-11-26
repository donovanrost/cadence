defmodule Cadence.IngressJournal.FileSystem do
  @moduledoc """
  Path-local, bounded, append-only ingress byte journal.

  The writer publishes an entry only after its complete record has been
  written. In `:sync` durability mode it also calls `fdatasync` before replying
  to the producer. Recovery validates every record checksum and truncates an
  incomplete or corrupt tail before accepting new writes.

  Consumer cursors are checkpointed independently. Segments are reclaimed only
  when every required cursor has durably advanced beyond the segment.

  Each consumer has a READ position (in memory: where `next_entries/4` reads; every ack moves it)
  and a durable RESUME point (domain's partial-frame fix, 11-15): a byte `resume` offset, where
  the consumer's work is truly done, and its `boundary`, the greatest entry start <= `resume`. A
  consumer holding a partial frame or packet acks the entries it has read with an earlier
  `resume_offset:`; the checkpoint persists boundary and resume, trimming and reclaim go by the
  boundary, and after a restart the read position is the boundary and `resume_offset/2` says how
  many leading bytes of that entry are already done. Without `resume_offset:` the resume point
  is the ack's end offset (boundary = resume = read position, as before).

  `cursors.term` stays version 1: `cursors` holds the boundaries (an older reader resumes there,
  re-reading at most a partial frame), and an optional `resume` map holds the resume points that
  differ from them (absent: resume = boundary).
  """

  use GenServer

  require Logger

  alias Cadence.IngressJournal.{Entry, Identity, IngestTelemetry}
  alias Cadence.Platform.DurableFile
  alias Cadence.Platform.SnapshotCall

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

  @spec acknowledge(GenServer.server(), consumer() | [consumer()], non_neg_integer(), keyword()) ::
          :ok | {:error, term()}
  def acknowledge(journal, consumers, end_offset, opts \\ [])
      when is_integer(end_offset) and end_offset >= 0 and is_list(opts) do
    consumers = if is_list(consumers), do: consumers, else: [consumers]
    call_if_running(journal, {:acknowledge, consumers, end_offset, opts[:resume_offset]})
  end

  @doc """
  The consumer's resume point: the byte offset its work is done to (see the moduledoc). After a
  restart its reading starts at the entry holding it; the bytes of that entry before it are done.
  """
  @spec resume_offset(GenServer.server(), consumer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def resume_offset(journal, consumer) when is_atom(consumer),
    do: call_if_running(journal, {:resume_offset, consumer})

  @spec snapshot(GenServer.server()) :: {:ok, map()} | {:error, term()}
  # #334: a read never takes its caller down.
  def snapshot(journal) do
    with {:ok, pid} <- lookup(journal) do
      SnapshotCall.call(pid, :snapshot, :component)
    end
  end

  @doc "Seals a drained journal and durably saves every consumer's final position."
  def seal(journal), do: GenServer.call(journal, :seal, :infinity)

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

  @doc """
  The journal streams on disk under `base_path`, as their contexts (`mission_id`,
  `realized_contact_id`, `path_id`, `provider_binding_id`), read from each stream's metadata
  without opening it. Replay finds ended contacts with journals this way (DECISIONS #71).
  """
  @spec stored_streams(binary()) :: [map()]
  def stored_streams(base_path) when is_binary(base_path) do
    case File.ls(base_path) do
      {:ok, names} ->
        names
        |> Enum.sort()
        |> Enum.flat_map(&stored_stream(Path.join([base_path, &1, "stream.term"])))

      {:error, _reason} ->
        []
    end
  end

  defp stored_stream(path) do
    with {:ok, binary} <- File.read(path),
         %{context: %{mission_id: _, realized_contact_id: _} = context} <-
           :erlang.binary_to_term(binary, [:safe]) do
      [context]
    else
      _other -> []
    end
  rescue
    ArgumentError -> []
  end

  @doc """
  Every stored stream under `base_path`: its directory, stream id and context (reclaim of
  completed streams, #71 follow-up). A directory whose `stream.term` can't be read isn't listed.
  """
  @spec stored_stream_directories(binary()) :: [
          %{directory: binary(), stream_id: binary(), context: map()}
        ]
  def stored_stream_directories(base_path) when is_binary(base_path) do
    case File.ls(base_path) do
      {:ok, names} ->
        names
        |> Enum.sort()
        |> Enum.flat_map(&stored_stream_directory(base_path, &1))

      {:error, _reason} ->
        []
    end
  end

  # The directory is named by its context's digest: a stream.term naming another context isn't
  # this directory's (it never steers a reclaim). stream_id is the incarnation the record headers
  # carry.
  defp stored_stream_directory(base_path, name) do
    directory = Path.join(base_path, name)

    with {:ok, %{stream_id: stream_id, context: context}} <-
           stored_stream_metadata(Path.join(directory, "stream.term")),
         true <- stream_id(context) == name do
      [%{directory: directory, stream_id: stream_id, context: context}]
    else
      _unreadable_or_foreign -> []
    end
  end

  defp stored_stream_metadata(path) do
    with {:ok, binary} <- File.read(path),
         %{stream_id: stream_id, context: %{mission_id: _, realized_contact_id: _}} = metadata
         when is_binary(stream_id) <- :erlang.binary_to_term(binary, [:safe]) do
      {:ok, metadata}
    else
      _other -> :error
    end
  rescue
    ArgumentError -> :error
  end

  @doc """
  Whether a stored stream (not open by a journal) is drained ON DISK: its checkpoint has every
  consumer (processing and archive) at its `next_offset`, and the segments, read without
  modifying them, end exactly there with no torn tail. `bytes` is the directory's size.
  """
  @spec stored_stream_drain(binary(), binary()) ::
          {:drained, non_neg_integer()} | {:not_drained, term(), non_neg_integer()}
  def stored_stream_drain(directory, stream_id)
      when is_binary(directory) and is_binary(stream_id) do
    bytes = directory_bytes(directory)

    with {:ok, checkpoint} <- load_checkpoint(directory, @default_consumers),
         {:ok, tail} <- read_only_tail(directory, stream_id, checkpoint.next_offset) do
      behind =
        for {consumer, offset} <- checkpoint.cursors,
            offset != tail or Map.fetch!(checkpoint.resume, consumer) != tail,
            do: {consumer, offset}

      cond do
        behind != [] -> {:not_drained, {:cursors_behind, behind, tail}, bytes}
        checkpoint.next_offset != tail -> {:not_drained, {:checkpoint_behind, tail}, bytes}
        true -> {:drained, bytes}
      end
    else
      {:error, reason} -> {:not_drained, reason, bytes}
    end
  end

  defp read_only_tail(directory, stream_id, checkpoint_next_offset) do
    case directory |> Path.join("segment-*.cij") |> Path.wildcard() |> Enum.sort() do
      [] ->
        {:ok, checkpoint_next_offset}

      [first | _rest] = paths ->
        segments_tail(paths, stream_id, segment_start_from_path(first))
    end
  end

  defp segments_tail(paths, stream_id, start_offset) do
    paths
    |> Enum.reduce_while({:ok, start_offset, nil}, fn path, {:ok, offset, sequence} ->
      case read_segment(path, stream_id, offset, sequence) do
        {:ok, next_offset, next_sequence} -> {:cont, {:ok, next_offset, next_sequence}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, tail, _sequence} -> {:ok, tail}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_segment(path, stream_id, expected_offset, expected_sequence) do
    with {:ok, file} <- :file.open(path, [:read, :binary, :raw]),
         {:ok, file_size} <- :file.position(file, :eof) do
      try do
        case parse_records(
               file,
               file_size,
               path,
               stream_id,
               expected_offset,
               expected_sequence,
               0,
               []
             ) do
          {:error, reason} ->
            {:error, reason}

          {_entries, _valid_bytes, true} ->
            {:error, {:torn_tail, path}}

          {entries, _valid_bytes, false} ->
            case List.last(entries) do
              nil -> {:ok, expected_offset, expected_sequence}
              last -> {:ok, last.end_offset, last.sequence + 1}
            end
        end
      after
        :file.close(file)
      end
    end
  end

  defp directory_bytes(directory) do
    directory
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      case File.stat(path) do
        {:ok, %{size: size}} -> size
        _gone -> 0
      end
    end)
    |> Enum.sum()
  end

  @doc """
  Removes a stored stream's directory, only if it is a direct child of `base_path` (a stored
  `stream.term` must never steer the removal elsewhere).
  """
  @spec reclaim_stored_stream(binary(), binary()) :: :ok | {:error, term()}
  def reclaim_stored_stream(base_path, directory)
      when is_binary(base_path) and is_binary(directory) do
    base = Path.expand(base_path)
    target = Path.expand(directory)

    if Path.dirname(target) == base and Path.basename(target) not in ["", ".", ".."] do
      case File.rm_rf(target) do
        {:ok, _removed} -> :ok
        {:error, reason, path} -> {:error, {:reclaim_failed, path, reason}}
      end
    else
      {:error, {:reclaim_outside_base_path, target}}
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
    # A runtime stop (its supervisor's shutdown) must run terminate/2, which checkpoints the
    # acknowledged cursors; otherwise acks since the last periodic checkpoint are lost and the next
    # start replays them (39LEY, 11-14). A linked process's abnormal exit still stops the journal
    # (handle_info {:EXIT, ...}).
    Process.flag(:trap_exit, true)

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
    context_id = stream_id(context)
    stream_path = Path.join(base_path, context_id)
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
         :ok <- DurableFile.mkdir_p(stream_path),
         {:ok, stream_id} <- ensure_stream_metadata(stream_path, context_id, context),
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
        sealed?: false,
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
        checkpoint_writer: Keyword.get(opts, :checkpoint_writer, &checkpoint_cursors/5),
        consumers: MapSet.new(consumers),
        cursors: checkpoint.cursors,
        boundaries: checkpoint.cursors,
        resume: checkpoint.resume,
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
        # #686: when the processing backlog was last reported (monotonic ms), at most once a second.
        backlog_reported_at: nil,
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
  def handle_call({operation, _, _, _, _}, _from, %{sealed?: true} = state)
      when operation in [:append, :append_stream],
      do: {:reply, {:error, :ingress_journal_sealed}, state}

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

  def handle_call({:acknowledge, consumers, end_offset, resume_offset}, _from, state) do
    with :ok <- validate_acknowledgement(state, consumers, end_offset),
         {:ok, resume} <- validate_resume(state, consumers, end_offset, resume_offset) do
      cursors = Enum.reduce(consumers, state.cursors, &Map.put(&2, &1, end_offset))

      {boundaries, resumes} =
        Enum.reduce(consumers, {state.boundaries, state.resume}, fn consumer, {bounds, rs} ->
          {Map.put(bounds, consumer, boundary_for(state, consumer, resume)),
           Map.put(rs, consumer, resume)}
        end)

      dirty? =
        state.cursors_dirty? or boundaries != state.boundaries or resumes != state.resume

      {:reply, :ok,
       %{
         state
         | cursors: cursors,
           boundaries: boundaries,
           resume: resumes,
           cursors_dirty?: dirty?
       }}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:resume_offset, consumer}, _from, state) do
    case Map.fetch(state.resume, consumer) do
      {:ok, resume} -> {:reply, {:ok, resume}, state}
      :error -> {:reply, {:error, {:unknown_ingress_journal_consumer, consumer}}, state}
    end
  end

  def handle_call(:seal, _from, state) do
    if drained?(state) do
      state = %{state | sealed?: true}

      with :ok <- cancel_checkpoint_worker(state.checkpoint_in_flight),
           :ok <- :file.datasync(state.active_file),
           :ok <- write_checkpoint(state, state.boundaries, state.resume) do
        summary = %{
          stream_id: state.stream_id,
          tail: state.next_offset,
          cursors: state.cursors
        }

        {:reply, {:ok, summary},
         %{
           state
           | checkpoint_in_flight: nil,
             durable_cursors: state.boundaries,
             cursors_dirty?: false
         }}
      else
        {:error, reason} -> {:reply, {:error, {:journal_seal_failed, reason}}, state}
      end
    else
      {:reply, {:error, {:journal_not_drained, state.resume, state.next_offset}}, state}
    end
  end

  def handle_call(:snapshot, _from, state) do
    min_cursor = minimum_cursor(state.cursors)

    {:reply,
     {:ok,
      Map.merge(state.context, %{
        stream_id: state.stream_id,
        sealed?: state.sealed?,
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
        resume_points:
          Map.new(state.boundaries, fn {consumer, boundary} ->
            {consumer, %{boundary: boundary, resume: Map.fetch!(state.resume, consumer)}}
          end),
        checkpoint_in_flight?: not is_nil(state.checkpoint_in_flight),
        lag_bytes:
          Map.new(state.cursors, fn {consumer, cursor} ->
            {consumer, state.next_offset - cursor}
          end),
        minimum_cursor: min_cursor,
        processing_backlog: processing_backlog(state),
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
    {:noreply, maybe_report_backlog(next_state)}
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

  # Trapping exits (init/1): a linked process ending normally changes nothing; any other exit stops
  # the journal with that reason, as it did before it trapped exits. Its supervisor's own exit is
  # handled by GenServer (terminate/2 runs).
  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}
  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}

  @impl true
  def terminate(_reason, state) do
    cancel_checkpoint_worker(state.checkpoint_in_flight)

    _ =
      checkpoint_cursors(
        state.stream_path,
        state.boundaries,
        state.next_offset,
        state.next_sequence,
        state.resume
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
    cursors = state.boundaries
    resume = state.resume

    writer_state =
      Map.take(state, [:checkpoint_writer, :stream_path, :next_offset, :next_sequence])

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        checkpoint_started_at = System.monotonic_time()
        result = write_checkpoint(writer_state, cursors, resume)

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
      resume: resume,
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
      |> Map.put(
        :cursors_dirty?,
        state.boundaries != checkpoint.cursors or state.resume != checkpoint.resume
      )
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
        durable_processing_offset: Map.get(state.durable_cursors, :processing),
        reclaimed_entries: reclaimed.entries,
        reclaimed_segments: reclaimed.segments,
        reclaimed_bytes: reclaimed.bytes
      },
      %{outcome: outcome}
    )
  end

  # An injected writer may take the resume points (arity 5) or not (arity 4, tests).
  defp write_checkpoint(%{checkpoint_writer: writer} = state, boundaries, resume)
       when is_function(writer, 5),
       do: writer.(state.stream_path, boundaries, state.next_offset, state.next_sequence, resume)

  defp write_checkpoint(%{checkpoint_writer: writer} = state, boundaries, _resume),
    do: writer.(state.stream_path, boundaries, state.next_offset, state.next_sequence)

  defp checkpoint_cursors(stream_path, cursors, next_offset, next_sequence, resume) do
    # Only the resume points that differ from their boundary; none means the file is exactly the
    # one older code writes.
    differing =
      for {consumer, r} <- resume, r != Map.get(cursors, consumer), into: %{}, do: {consumer, r}

    contents =
      %{
        version: 1,
        cursors: cursors,
        next_offset: next_offset,
        next_sequence: next_sequence
      }
      |> then(&if(differing == %{}, do: &1, else: Map.put(&1, :resume, differing)))
      |> :erlang.term_to_binary()

    cursor_path = Path.join(stream_path, "cursors.term")
    DurableFile.replace(cursor_path, contents)
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
        {:error, :checkpoint_worker_stop_timeout}
    end
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

  defp validate_resume(_state, _consumers, end_offset, nil), do: {:ok, end_offset}

  defp validate_resume(state, [consumer], end_offset, resume) when is_integer(resume) do
    current = Map.fetch!(state.resume, consumer)

    cond do
      resume > end_offset ->
        {:error, {:ingress_journal_resume_beyond_ack, resume, end_offset}}

      resume < current ->
        {:error, {:ingress_journal_resume_regression, consumer, resume, current}}

      true ->
        {:ok, resume}
    end
  end

  defp validate_resume(_state, consumers, _end_offset, resume) when is_integer(resume),
    do: {:error, {:ingress_journal_resume_requires_one_consumer, consumers}}

  defp validate_resume(_state, _consumers, _end_offset, resume),
    do: {:error, {:invalid_ingress_journal_resume_offset, resume}}

  # The greatest entry start <= resume, walking forward from the consumer's current boundary
  # (only the entries since its last resume point).
  defp boundary_for(state, consumer, resume) do
    if valid_entry_boundary?(state, resume) do
      resume
    else
      state.boundaries
      |> Map.fetch!(consumer)
      |> :gb_trees.iterator_from(state.entries)
      |> floor_start(resume, Map.fetch!(state.boundaries, consumer))
    end
  end

  defp floor_start(iterator, resume, best) do
    case :gb_trees.next(iterator) do
      {offset, _entry, next} when offset <= resume -> floor_start(next, resume, offset)
      _past_or_end -> best
    end
  end

  defp drained?(state) do
    Enum.all?(state.consumers, fn consumer ->
      Map.fetch!(state.cursors, consumer) == state.next_offset and
        Map.fetch!(state.resume, consumer) == state.next_offset
    end)
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

  # #686: the processing backlog as a :telemetry event, at most once a second. O(1) bytes and one
  # O(log n) lookup for the oldest unacknowledged entry: never the entry count, which walks the
  # whole backlog (`processing_backlog/1`, for snapshots only). It is measured from the in-memory
  # processing cursor ("not yet acknowledged"), which is what lag means; the snapshot's
  # `processing_backlog/1` starts from the lower of the durable and in-memory cursors.
  @backlog_report_ms 1_000

  defp maybe_report_backlog(state) do
    now = System.monotonic_time(:millisecond)

    cond do
      not MapSet.member?(state.consumers, :processing) ->
        state

      is_integer(state.backlog_reported_at) and
          now - state.backlog_reported_at < @backlog_report_ms ->
        state

      true ->
        cursor = Map.get(state.cursors, :processing, state.next_offset)

        oldest =
          case :gb_trees.next(:gb_trees.iterator_from(cursor, state.entries)) do
            {_offset, %Entry{receipt_time: receipt_time}, _next} -> receipt_time
            :none -> nil
          end

        IngestTelemetry.journal_backlog(state.context, max(state.next_offset - cursor, 0), oldest)
        %{state | backlog_reported_at: now}
    end
  end

  # What the processing consumer hasn't durably passed (DECISIONS #71): a restart resumes from
  # the durable cursor, so that is where the not-yet-stored entries start.
  defp processing_backlog(state) do
    from =
      [Map.get(state.durable_cursors, :processing), Map.get(state.cursors, :processing)]
      |> Enum.reject(&is_nil/1)
      |> Enum.min(fn -> state.next_offset end)

    %{
      from_offset: from,
      to_offset: state.next_offset,
      bytes: max(state.next_offset - from, 0),
      entries: count_entries_from(:gb_trees.iterator_from(from, state.entries), 0)
    }
  end

  defp count_entries_from(iterator, count) do
    case :gb_trees.next(iterator) do
      {_offset, _entry, next} -> count_entries_from(next, count + 1)
      :none -> count
    end
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
          file
          |> parse_records(file_size, path, stream_id, expected_offset, expected_sequence, 0, [])
          |> settle_parsed_segment(file)
        after
          :file.close(file)
        end

      result
    end
  end

  defp settle_parsed_segment({:error, reason}, _file), do: {:error, reason}

  defp settle_parsed_segment({entries, valid_bytes, true}, file) do
    with {:ok, _position} <- :file.position(file, valid_bytes),
         :ok <- :file.truncate(file),
         :ok <- :file.sync(file) do
      {:ok, entries, valid_bytes, true}
    end
  end

  defp settle_parsed_segment({entries, valid_bytes, false}, _file),
    do: {:ok, entries, valid_bytes, false}

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
         true <- :crypto.hash(:sha256, payload) == header.checksum,
         {:ok, metadata} <- record_metadata(metadata_binary, context),
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
      {:error, {:ingress_journal_metadata_undecodable, _path, _offset}} = undecodable ->
        undecodable

      _invalid ->
        invalid_record(context)
    end
  end

  defp invalid_record(context), do: {Enum.reverse(context.entries), context.file_offset, true}

  # A complete record whose payload checksum matches is intact: if its metadata won't decode,
  # that is the VM (an atom whose module isn't loaded yet), not a torn write. Load the app's
  # modules and retry once (as Terms.decode does, 98c8b5a6); if it still fails, recovery stops
  # WITHOUT truncating, so the journal refuses to open and keeps every byte (api-ops, 11-14).
  defp record_metadata(binary, context) do
    case safe_metadata(binary) do
      {:ok, metadata} ->
        {:ok, metadata}

      {:error, :invalid_metadata} ->
        load_application_modules()

        case safe_metadata(binary) do
          {:ok, metadata} ->
            {:ok, metadata}

          {:error, :invalid_metadata} ->
            {:error, {:ingress_journal_metadata_undecodable, context.path, context.file_offset}}
        end
    end
  end

  defp load_application_modules do
    case :application.get_key(:cadence, :modules) do
      {:ok, modules} -> Enum.each(modules, &Code.ensure_loaded/1)
      :undefined -> :ok
    end
  end

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
      cursors = Map.new(consumers, &{&1, Map.get(stored, &1, 0)})
      stored_resume = Map.get(checkpoint, :resume, %{})

      {:ok,
       %{
         cursors: cursors,
         # A resume point is never before its boundary (an older writer: equal).
         resume: Map.new(cursors, fn {c, b} -> {c, max(Map.get(stored_resume, c, b), b)} end),
         next_offset: Map.get(checkpoint, :next_offset, 0),
         next_sequence: Map.get(checkpoint, :next_sequence, 0)
       }}
    else
      {:error, :enoent} ->
        zero = Map.new(consumers, &{&1, 0})
        {:ok, %{cursors: zero, resume: zero, next_offset: 0, next_sequence: 0}}

      _invalid ->
        {:error, :invalid_ingress_journal_cursor_checkpoint}
    end
  rescue
    ArgumentError -> {:error, :invalid_ingress_journal_cursor_checkpoint}
  end

  defp ensure_stream_metadata(stream_path, context_id, context) do
    path = Path.join(stream_path, "stream.term")

    case File.read(path) do
      {:ok, binary} ->
        read_stream_metadata(binary, context_id, context)

      {:error, :enoent} ->
        if Path.wildcard(Path.join(stream_path, "*.cij")) != [] or
             File.exists?(Path.join(stream_path, "cursors.term")) do
          {:error, :ingress_journal_stream_metadata_missing}
        else
          create_stream_metadata(path, context)
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    ArgumentError -> {:error, :invalid_ingress_journal_stream_metadata}
  end

  defp read_stream_metadata(binary, context_id, context) do
    case :erlang.binary_to_term(binary, [:safe]) do
      %{version: 1, stream_id: ^context_id, context: ^context} ->
        # Existing journal bytes retain their original replay identities.
        {:ok, context_id}

      %{version: 2, stream_id: stream_id, context: ^context}
      when is_binary(stream_id) and byte_size(stream_id) > 0 ->
        {:ok, stream_id}

      _other ->
        {:error, :ingress_journal_stream_identity_mismatch}
    end
  end

  defp create_stream_metadata(path, context) do
    # Context selects the directory; the persisted incarnation selects the
    # identity. An empty replacement disk must never reuse old byte IDs.
    stream_id = "stream-" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
    metadata = %{version: 2, stream_id: stream_id, context: context}

    with :ok <- DurableFile.write_new(path, :erlang.term_to_binary(metadata)) do
      {:ok, stream_id}
    end
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
    with {:ok, file} <-
           :file.open(segment_path(stream_path, start_offset), [:append, :binary, :raw]) do
      case DurableFile.sync_directory(stream_path) do
        :ok ->
          {:ok, file}

        error ->
          :file.close(file)
          error
      end
    end
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
