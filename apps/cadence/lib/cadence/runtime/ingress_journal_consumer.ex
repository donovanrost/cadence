defmodule Cadence.Runtime.IngressJournalConsumer do
  @moduledoc """
  Replays captured ingress byte ranges into the ordered path executor.

  Only semantic-persistence completion advances the processing cursor. Raw
  archive custody has an independent consumer and acknowledgement. This
  consumer has at most one bounded contiguous range in flight, which makes the
  cursor protocol explicit and bounds replay work after a process restart.

  The journal's DURABLE resume point also waits for the semantic snapshot of every partition
  that consumed the stream (`SnapshotGate`, DECISIONS #94/#96), so a restart replays at most
  what the snapshots do not cover. The read cursor, and so flow control, does not wait.
  """

  use GenServer

  require Logger

  alias Cadence.IngressJournal.{Entry, Evidence, FileSystem, IngestTelemetry}
  alias Cadence.Platform.SnapshotCall
  alias Cadence.Runtime.IngressJournalConsumer.SnapshotGate
  alias Cadence.Runtime.{ProviderIngressExecutor, SemanticSnapshotNotifier}

  @default_poll_interval_ms 10
  @default_max_batch_entries 8
  @default_max_batch_bytes 2 * 1_024 * 1_024
  # How long quiescing waits for the partition's end-of-pass snapshot before it gives up on the
  # gate and acks what was read (the journal can then drain; a crash loses at most that tail).
  @default_quiesce_snapshot_wait_ms 10_000

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
      id: {:ingress_journal_consumer, Keyword.fetch!(opts, :provider_binding_id)},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @spec snapshot(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def snapshot(consumer) do
    # #334: a read never takes its caller down.
    with {:ok, pid} <- lookup(consumer) do
      SnapshotCall.call(pid, :snapshot, :component)
    end
  end

  @spec quiesce(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def quiesce(consumer) do
    with {:ok, pid} <- lookup(consumer) do
      GenServer.call(pid, :quiesce, :infinity)
    end
  end

  @spec lookup(GenServer.server()) :: {:ok, pid()} | {:error, term()}
  def lookup(server) when is_pid(server) do
    if Process.alive?(server),
      do: {:ok, server},
      else: {:error, :ingress_journal_consumer_not_running}
  end

  def lookup(server) do
    case GenServer.whereis(server) do
      nil -> {:error, :ingress_journal_consumer_not_running}
      pid -> {:ok, pid}
    end
  end

  @impl true
  def init(opts) do
    # #270: as IngressPersistenceProjector, trap exits so a supervisor's :shutdown lets the
    # current step finish within the declared 5 s; other linked exits are handled below.
    Process.flag(:trap_exit, true)

    config =
      opts
      |> Keyword.get_lazy(:policy, &FileSystem.configured_policy/0)
      |> Map.fetch!(:consumer_opts)

    state = %{
      mission_id: Keyword.fetch!(opts, :mission_id),
      realized_contact_id: Keyword.fetch!(opts, :realized_contact_id),
      path_id: Keyword.fetch!(opts, :path_id),
      provider_binding_id: Keyword.fetch!(opts, :provider_binding_id),
      journal_name: Keyword.fetch!(opts, :journal_name),
      executor_name: Keyword.fetch!(opts, :executor_name),
      poll_interval_ms:
        Keyword.get(
          opts,
          :poll_interval_ms,
          Keyword.get(config, :processing_poll_interval_ms, @default_poll_interval_ms)
        ),
      max_batch_entries:
        positive_option(
          opts,
          config,
          :processing_max_batch_entries,
          @default_max_batch_entries
        ),
      max_batch_bytes:
        positive_option(opts, config, :processing_max_batch_bytes, @default_max_batch_bytes),
      retry_initial_ms: positive_option(opts, config, :retry_initial_ms, 250),
      retry_max_ms: positive_option(opts, config, :retry_max_ms, 30_000),
      retry_scheduler: Keyword.get(opts, :retry_scheduler, &Process.send_after/3),
      retry_ref: nil,
      retry_delay_ms: 0,
      consecutive_failures: 0,
      lifecycle_status: :active,
      quiesce_waiters: [],
      in_flight: nil,
      delivered_batches: 0,
      delivered_entries: 0,
      delivered_bytes: 0,
      acknowledged_batches: 0,
      acknowledged_entries: 0,
      acknowledged_bytes: 0,
      max_delivered_batch_entries: 0,
      max_delivered_batch_bytes: 0,
      failed_count: 0,
      last_completed_at: nil,
      last_error: nil,
      # The journal's durable resume point when it lies inside the first entry read after a start
      # (bytes already decoded before a restart; dropped once), then nil.
      resume_slice: :unread,
      # Never ack a resume point below the journal's durable one (api-ops: a regression error
      # would retry forever); raised by each ack.
      resume_floor: 0,
      last_incomplete: nil,
      # The semantic snapshots gating the durable resume point (see SnapshotGate); `stream_id`
      # is learned from the first batch, `last_finished` is the last acked batch's end offset and where its
      # processing finished (the resume point the journal gets once the snapshots cover it).
      snapshot_gate: SnapshotGate.new(),
      stream_id: nil,
      last_finished: nil,
      quiesce_started_at: nil,
      quiesce_snapshot_wait_ms:
        Keyword.get(opts, :quiesce_snapshot_wait_ms, @default_quiesce_snapshot_wait_ms),
      incomplete_at_end: %{frame_bytes: 0, packet_octets: 0, journal_bytes: 0},
      # The frame-SCID cross-check's running tally for this stream (DECISIONS #102): nil until a
      # batch reports one (no expected SCID: never).
      scid_check: nil
    }

    send(self(), :consume)
    {:ok, state}
  end

  @impl true
  def handle_call(:quiesce, _from, %{lifecycle_status: :quiesced} = state) do
    {:reply, {:ok, quiescence_settlement(state)}, state}
  end

  def handle_call(:quiesce, from, state) do
    send(self(), :consume)

    {:noreply,
     %{
       state
       | lifecycle_status: :quiescing,
         quiesce_started_at: state.quiesce_started_at || System.monotonic_time(:millisecond),
         quiesce_waiters: [from | state.quiesce_waiters]
     }}
  end

  def handle_call(:snapshot, _from, state) do
    in_flight =
      case state.in_flight do
        %{first: first, last: last, entry_count: entry_count, byte_count: byte_count} ->
          %{
            first_sequence: first.sequence,
            last_sequence: last.sequence,
            start_offset: first.start_offset,
            end_offset: last.end_offset,
            entry_count: entry_count,
            byte_count: byte_count
          }

        nil ->
          nil
      end

    {:reply,
     {:ok,
      %{
        provider_binding_id: state.provider_binding_id,
        lifecycle_status: state.lifecycle_status,
        max_batch_entries: state.max_batch_entries,
        max_batch_bytes: state.max_batch_bytes,
        in_flight: in_flight,
        delivered_batches: state.delivered_batches,
        delivered_entries: state.delivered_entries,
        delivered_bytes: state.delivered_bytes,
        acknowledged_batches: state.acknowledged_batches,
        acknowledged_entries: state.acknowledged_entries,
        acknowledged_bytes: state.acknowledged_bytes,
        max_delivered_batch_entries: state.max_delivered_batch_entries,
        max_delivered_batch_bytes: state.max_delivered_batch_bytes,
        failed_count: state.failed_count,
        consecutive_failures: state.consecutive_failures,
        retry_delay_ms: state.retry_delay_ms,
        phase: if(state.in_flight, do: state.in_flight.phase, else: :idle),
        last_completed_at: state.last_completed_at,
        last_error: state.last_error,
        incomplete_at_end: state.incomplete_at_end,
        scid_check: state.scid_check
      }}, state}
  end

  @impl true
  def handle_info(:consume, %{lifecycle_status: :quiesced} = state),
    do: {:noreply, state}

  def handle_info(:consume, %{retry_ref: ref} = state) when not is_nil(ref),
    do: {:noreply, state}

  def handle_info(:consume, %{in_flight: %{phase: :retry, entries: entries}} = state),
    do: consume_entries(state, entries)

  def handle_info(:consume, %{in_flight: %{phase: :acknowledge}} = state),
    do: acknowledge_batch(state)

  def handle_info(:consume, %{in_flight: nil} = state) do
    case FileSystem.next_entries(
           state.journal_name,
           :processing,
           state.max_batch_entries,
           state.max_batch_bytes
         ) do
      {:ok, [%Entry{} | _rest] = entries} ->
        consume_entries(state, compatible_prefix(entries))

      :empty ->
        settle_or_schedule(state)

      {:error, reason} ->
        {:noreply, retry_after_failure(state, reason)}
    end
  end

  def handle_info(:consume, state), do: {:noreply, state}

  def handle_info({:retry, ref}, %{retry_ref: ref} = state) do
    send(self(), :consume)
    {:noreply, %{state | retry_ref: nil}}
  end

  def handle_info({:retry, _stale_ref}, state), do: {:noreply, state}

  # A partition committed a snapshot covering this stream up to `offset`: the durable resume point
  # may follow it. Mid-batch, that batch's ack applies it; idle, release it now.
  def handle_info({:semantic_snapshot_durable, partition, stream_id, offset}, state)
      when stream_id == state.stream_id do
    gate = SnapshotGate.snapshotted(state.snapshot_gate, partition, offset)
    {:noreply, release_snapshot(%{state | snapshot_gate: gate})}
  end

  def handle_info({:semantic_snapshot_durable, _partition, _stream_id, _offset}, state),
    do: {:noreply, state}

  # A partition recovered from a snapshot: if this consumer has processed its stream past what the
  # snapshot includes, the state lacks those batches. Restart, which reads the stream again from the
  # durable resume point; the partition skips the frames its snapshot already holds.
  def handle_info({:semantic_partition_recovered, partition, resume}, state) do
    if replay_from_snapshot?(state, partition, resume) do
      Logger.warning(
        "Ingress journal consumer replays from a recovered semantic snapshot of #{partition}",
        mission_id: state.mission_id,
        path_id: state.path_id
      )

      {:stop, {:shutdown, :semantic_replay}, state}
    else
      {:noreply, state}
    end
  end

  # A partition stopped after its final snapshot: it must not pin the durable cursor for good.
  def handle_info({:semantic_snapshot_stopped, partition, stream_id}, state)
      when stream_id == state.stream_id do
    gate = SnapshotGate.release(state.snapshot_gate, partition)
    {:noreply, release_snapshot(%{state | snapshot_gate: gate})}
  end

  def handle_info({:semantic_snapshot_stopped, _partition, _stream_id}, state),
    do: {:noreply, state}

  # Trapping exits (#270): a linked process's normal exit changes nothing; any other stops the
  # consumer with the same reason, as an untrapped link would.
  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}
  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}

  def handle_info(
        {:provider_ingress_persisted, _projector_pid, ref, %{} = progress},
        %{in_flight: %{ref: ref, phase: :processing} = batch} = state
      ) do
    batch =
      Map.merge(batch, %{
        phase: :acknowledge,
        resume: Map.get(progress, :resume_offset),
        incomplete: Map.get(progress, :incomplete),
        scid_check: Map.get(progress, :scid_check),
        counts: Map.get(progress, :counts),
        snapshot_partition: Map.get(progress, :snapshot_partition)
      })

    acknowledge_batch(%{state | in_flight: batch})
  end

  def handle_info({:provider_ingress_persisted, _projector_pid, _stale_ref, _resume}, state),
    do: {:noreply, state}

  def handle_info(
        {:provider_ingress_persisted, _projector_pid, ref},
        %{in_flight: %{ref: ref, phase: :processing} = batch} = state
      ) do
    acknowledge_batch(%{state | in_flight: %{batch | phase: :acknowledge}})
  end

  def handle_info({:provider_ingress_persisted, _projector_pid, _stale_ref}, state),
    do: {:noreply, state}

  def handle_info(
        {:provider_ingress_failed, _executor_pid, ref, reason},
        %{in_flight: %{ref: ref, phase: :processing} = batch} = state
      ) do
    {:noreply, retry_after_failure(%{state | in_flight: %{batch | phase: :retry}}, reason)}
  end

  def handle_info({:provider_ingress_failed, _executor_pid, _stale_ref, _reason}, state),
    do: {:noreply, state}

  defp consume_entries(state, [%Entry{} = first | _rest] = entries) do
    last = List.last(entries)
    entry_count = length(entries)
    byte_count = Enum.sum(Enum.map(entries, & &1.payload_length))

    batch = %{
      first: first,
      last: last,
      entries: entries,
      entry_count: entry_count,
      byte_count: byte_count,
      phase: :retry,
      ref: nil,
      # #686: when the batch went to the executor, and what its result carried.
      delivered_at: nil,
      counts: nil
    }

    state = %{state | in_flight: batch} |> load_resume_slice() |> subscribe_to_snapshots(first)

    with {:ok, raw_evidence} <- Evidence.from_contiguous_entries(entries),
         raw_evidence = slice(raw_evidence, state.resume_slice),
         ref <- make_ref(),
         :ok <-
           ProviderIngressExecutor.enqueue_telemetry(state.executor_name, raw_evidence,
             completion: {self(), ref}
           ) do
      :telemetry.execute(
        [:cadence, :ingress_journal, :processing_batch],
        %{entries: entry_count, bytes: byte_count},
        %{}
      )

      {:noreply,
       %{
         state
         | in_flight: %{
             batch
             | ref: ref,
               phase: :processing,
               delivered_at: System.monotonic_time()
           },
           delivered_batches: state.delivered_batches + 1,
           delivered_entries: state.delivered_entries + entry_count,
           delivered_bytes: state.delivered_bytes + byte_count,
           max_delivered_batch_entries: max(state.max_delivered_batch_entries, entry_count),
           max_delivered_batch_bytes: max(state.max_delivered_batch_bytes, byte_count)
       }}
    else
      {:error, reason} ->
        {:noreply, retry_after_failure(state, reason)}
    end
  end

  defp compatible_prefix([%Entry{} = first | rest]) do
    {entries, _last} =
      Enum.reduce_while(rest, {[first], first}, fn entry, {acc, previous} ->
        if Evidence.compatible_entries?(previous, entry) do
          {:cont, {[entry | acc], entry}}
        else
          {:halt, {acc, previous}}
        end
      end)

    Enum.reverse(entries)
  end

  defp positive_option(opts, config, key, default) do
    value = Keyword.get(opts, key, Keyword.get(config, key, default))

    if is_integer(value) and value > 0 do
      value
    else
      raise ArgumentError, "#{key} must be a positive integer, got: #{inspect(value)}"
    end
  end

  defp acknowledge_batch(%{in_flight: batch} = state) do
    # Processing finished through the batch's end, and the stream may resume (durably) at the start
    # of a frame or packet still incomplete (domain's partial-frame fix, 11-15). The journal's
    # durable resume point is that, held back to the partitions' last snapshots (SnapshotGate).
    finished = batch_resume(batch, state.resume_floor) || batch.last.end_offset
    partition = Map.get(batch, :snapshot_partition)
    if partition, do: SemanticSnapshotNotifier.subscribe_partition(partition)
    gate = SnapshotGate.note(state.snapshot_gate, partition)
    resume = SnapshotGate.limit(gate, finished, state.resume_floor)

    case FileSystem.acknowledge(
           state.journal_name,
           :processing,
           batch.last.end_offset,
           resume_offset: resume
         ) do
      :ok ->
        send(self(), :consume)
        IngestTelemetry.batch_acknowledged(batch, state)

        {:noreply,
         %{
           state
           | in_flight: nil,
             resume_slice: nil,
             resume_floor: resume,
             snapshot_gate: gate,
             last_finished: {batch.last.end_offset, finished},
             last_incomplete: Map.get(batch, :incomplete),
             scid_check: add_scid_check(state.scid_check, Map.get(batch, :scid_check)),
             acknowledged_batches: state.acknowledged_batches + 1,
             acknowledged_entries: state.acknowledged_entries + batch.entry_count,
             acknowledged_bytes: state.acknowledged_bytes + batch.byte_count,
             last_completed_at: DateTime.utc_now(),
             consecutive_failures: 0,
             retry_delay_ms: 0,
             last_error: nil
         }}

      {:error, reason} ->
        # Processing has completed. Retry custody acknowledgement, not decoding.
        {:noreply, retry_after_failure(state, reason)}
    end
  end

  defp replay_from_snapshot?(state, partition, resume) do
    with true <- MapSet.member?(state.snapshot_gate.partitions, partition),
         {_end_offset, finished} <- state.last_finished do
      finished > Map.get(resume, state.stream_id, state.resume_floor)
    else
      _no_gate_or_nothing_processed -> false
    end
  end

  defp subscribe_to_snapshots(%{stream_id: nil} = state, %Entry{stream_id: stream_id}) do
    SemanticSnapshotNotifier.subscribe(stream_id)
    %{state | stream_id: stream_id}
  end

  defp subscribe_to_snapshots(state, _first), do: state

  # Idle, with a snapshot newly covering more than the durable resume point: re-ack the read
  # position with the higher resume point. Mid-batch the batch's own ack applies it.
  defp release_snapshot(%{in_flight: nil, last_finished: {end_offset, finished}} = state) do
    resume = SnapshotGate.limit(state.snapshot_gate, finished, state.resume_floor)

    with true <- resume > state.resume_floor,
         :ok <-
           FileSystem.acknowledge(state.journal_name, :processing, end_offset,
             resume_offset: resume
           ) do
      %{state | resume_floor: resume}
    else
      _unchanged_or_retried_at_the_next_snapshot -> state
    end
  end

  defp release_snapshot(state), do: state

  defp retry_after_failure(state, reason) do
    delay =
      if state.consecutive_failures == 0,
        do: min(state.retry_initial_ms, state.retry_max_ms),
        else: min(state.retry_delay_ms * 2, state.retry_max_ms)

    ref = make_ref()
    state.retry_scheduler.(self(), {:retry, ref}, delay)
    phase = if state.in_flight, do: state.in_flight.phase, else: :read

    range =
      if state.in_flight,
        do: {state.in_flight.first.start_offset, state.in_flight.last.end_offset}

    Logger.warning(
      "Ingress journal retry (#{phase}) in #{delay}ms at #{inspect(range)}: " <>
        inspect(reason, limit: 10, printable_limit: 300),
      provider_binding_id: state.provider_binding_id
    )

    :telemetry.execute(
      [:cadence, :ingress_journal, :processing_retry],
      %{count: 1, delay_ms: delay},
      %{phase: phase}
    )

    %{
      state
      | failed_count: state.failed_count + 1,
        consecutive_failures: state.consecutive_failures + 1,
        retry_ref: ref,
        retry_delay_ms: delay,
        last_error: inspect(reason, limit: 10, printable_limit: 300)
    }
  end

  defp settle_or_schedule(%{lifecycle_status: :quiescing} = state) do
    if snapshot_pending?(state) do
      schedule_consume(state.poll_interval_ms)
      {:noreply, state}
    else
      {:noreply, settle_quiesced(state)}
    end
  end

  defp settle_or_schedule(state) do
    schedule_consume(state.poll_interval_ms)
    {:noreply, state}
  end

  # Quiescing (the contact's end) waits, a bounded time, for the partition's end-of-pass snapshot
  # to cover what was read; after that it releases the journal anyway so the stream can drain.
  defp snapshot_pending?(%{last_finished: {_end, finished}} = state) do
    SnapshotGate.holding?(state.snapshot_gate, finished, state.resume_floor) and
      System.monotonic_time(:millisecond) - state.quiesce_started_at <
        state.quiesce_snapshot_wait_ms
  end

  defp snapshot_pending?(_state), do: false

  defp release_ungated(%{last_finished: {end_offset, finished}} = state) do
    if SnapshotGate.holding?(state.snapshot_gate, finished, state.resume_floor) do
      Logger.warning(
        "Ingress journal released past the semantic snapshot at the end of the stream: " <>
          "durable resume #{state.resume_floor}, processed through #{finished}",
        mission_id: state.mission_id,
        path_id: state.path_id
      )

      case FileSystem.acknowledge(state.journal_name, :processing, end_offset,
             resume_offset: finished
           ) do
        :ok -> %{state | resume_floor: finished, snapshot_gate: SnapshotGate.new()}
        {:error, _reason} -> state
      end
    else
      state
    end
  end

  defp release_ungated(state), do: state

  defp settle_quiesced(state) do
    state = state |> release_ungated() |> give_up_incomplete()
    settlement = quiescence_settlement(state)
    Enum.each(state.quiesce_waiters, &GenServer.reply(&1, {:ok, settlement}))

    %{state | lifecycle_status: :quiesced, quiesce_waiters: []}
  end

  defp quiescence_settlement(state) do
    %{
      status: :quiesced,
      provider_binding_id: state.provider_binding_id,
      acknowledged_batches: state.acknowledged_batches,
      acknowledged_entries: state.acknowledged_entries,
      acknowledged_bytes: state.acknowledged_bytes,
      incomplete_at_end: state.incomplete_at_end,
      scid_check: state.scid_check
    }
  end

  # Adds one batch's frame-SCID tally to the stream's (DECISIONS #102).
  defp add_scid_check(total, nil), do: total
  defp add_scid_check(nil, batch), do: batch

  defp add_scid_check(total, batch),
    do: %{
      expected_scid: batch.expected_scid,
      spacecraft_id: Map.get(batch, :spacecraft_id),
      frames: total.frames + batch.frames,
      refused: Map.merge(total.refused, batch.refused, fn _scid, a, b -> a + b end)
    }

  # The batch's resume point, never below the floor; nil (resume = end) when it reported none.
  defp batch_resume(%{last: %{end_offset: end_offset}} = batch, floor) do
    case Map.get(batch, :resume) do
      resume when is_integer(resume) and resume <= end_offset -> max(resume, floor)
      _none -> nil
    end
  end

  defp load_resume_slice(%{resume_slice: :unread} = state) do
    case FileSystem.resume_offset(state.journal_name, :processing) do
      {:ok, offset} -> %{state | resume_slice: offset, resume_floor: offset}
      {:error, _reason} -> %{state | resume_slice: nil}
    end
  end

  defp load_resume_slice(state), do: state

  defp slice(raw_evidence, offset) when is_integer(offset),
    do: Evidence.drop_before(raw_evidence, offset)

  defp slice(raw_evidence, nil), do: raw_evidence

  # At the stream's end a frame or packet still incomplete never will be: give it up so the stream
  # drains (seal and reclaim wait for resume == read position), and count it: the partial frame's
  # bytes and the partial packets' octets, as the last decode reported them. It acks the READ
  # position, never the tail: bytes appended since the last read are read next (api-ops).
  defp give_up_incomplete(state) do
    with {:ok, %{cursors: %{processing: read}, resume_points: %{processing: %{resume: resume}}}}
         when resume < read <- journal_snapshot(state.journal_name),
         :ok <- FileSystem.acknowledge(state.journal_name, :processing, read, resume_offset: read) do
      incomplete = state.last_incomplete || %{frame_bytes: read - resume, packet_octets: 0}

      Logger.warning(
        "Ingress journal processing gave up an incomplete end: " <>
          "#{incomplete.frame_bytes} bytes of a frame, #{incomplete.packet_octets} of a packet",
        mission_id: state.mission_id,
        realized_contact_id: state.realized_contact_id,
        path_id: state.path_id
      )

      %{
        state
        | resume_floor: read,
          incomplete_at_end: %{
            frame_bytes: state.incomplete_at_end.frame_bytes + incomplete.frame_bytes,
            packet_octets: state.incomplete_at_end.packet_octets + incomplete.packet_octets,
            journal_bytes: state.incomplete_at_end.journal_bytes + read - resume
          }
      }
    else
      _complete -> state
    end
  end

  defp journal_snapshot(journal) do
    case FileSystem.snapshot(journal) do
      {:ok, snapshot} -> {:ok, snapshot}
      %{} = snapshot -> {:ok, snapshot}
      other -> other
    end
  end

  defp schedule_consume(interval_ms), do: Process.send_after(self(), :consume, interval_ms)
end
