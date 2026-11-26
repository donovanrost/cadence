defmodule Cadence.Runtime.PartitionOwner.SemanticSnapshots do
  @moduledoc """
  The partition's semantic snapshot cadence (DECISIONS #94/#96, #692).

  A partition owner that persists its semantic state snapshots it when the state changed and
  either `interval_ms` (60 s) passed since the last snapshot or the partition has been idle for
  `idle_ms` (the end of a pass), and when it stops. The snapshot holds the state and, per journal
  stream, the offset that state includes (`semantic_resume`); once it is committed the stream's
  consumer is told, and only then may its durable cursor pass those offsets
  (`Cadence.Runtime.IngressJournalConsumer`).

  This is also the partition's only semantic persistence: there is no per-batch log. A recovering
  owner loads its last snapshot (`Store.recover/2`) and the journal replays from the snapshot's
  offsets; `skip_replayed?/2` keeps the frames the snapshot already includes from being applied to
  the state a second time. A partition that persists no journal loses at most the memory since its
  last snapshot (about 60 s).

  The owner state keys this module reads and writes: `semantic_resume` (stream id => offset),
  `semantic_replay_floor` (the snapshot's offsets as recovered), `semantic_dirty?`,
  `semantic_snapshot_at` and `semantic_input_at` (monotonic ms), and `semantic_snapshot_config`.
  Without a semantic writer (no plan, or runtime records not persisted) nothing is tracked,
  snapshotted or gated.
  """

  require Logger

  alias Cadence.Runtime.PartitionKey
  alias Cadence.Runtime.SemanticSnapshotNotifier
  alias Cadence.SemanticRuntime.Store

  @defaults [interval_ms: 60_000, idle_ms: 2_000, tick_ms: 1_000]

  @doc "The initial state keys (recovery's own values, already in the state, win)."
  @spec init(keyword()) :: map()
  def init(opts) do
    %{
      semantic_resume: %{},
      semantic_replay_floor: %{},
      semantic_dirty?: false,
      semantic_snapshot_at: now(),
      semantic_input_at: now(),
      semantic_snapshot_config: Keyword.merge(@defaults, opts)
    }
  end

  @doc "Whether this owner's journal acks follow its snapshots."
  @spec gated?(map()) :: boolean()
  def gated?(%{persist_runtime_records?: true, semantic_writer: writer}), do: writer != nil
  def gated?(_state), do: false

  @doc "Schedules the next tick (`tick_ms: nil` turns the cadence off, for tests)."
  @spec schedule(map()) :: :ok
  def schedule(%{semantic_snapshot_config: config}) do
    case Keyword.get(config, :tick_ms) do
      ms when is_integer(ms) and ms > 0 -> Process.send_after(self(), :semantic_snapshot_tick, ms)
      _off -> :ok
    end

    :ok
  end

  def schedule(_state), do: :ok

  @doc """
  Records one processed batch: the state may have changed, and `result`'s journal stream is now
  covered up to its resume offset (the start of an incomplete frame, else the batch's end).
  """
  @spec track(map(), map()) :: map()
  def track(state, result) do
    if gated?(state) do
      state
      |> Map.put(:semantic_dirty?, true)
      |> Map.put(:semantic_input_at, now())
      |> track_stream(result)
    else
      state
    end
  end

  @doc "The state changed without a batch (a timer fired): a snapshot is due when the cadence says."
  @spec touch(map()) :: map()
  def touch(state) do
    if gated?(state),
      do: state |> Map.put(:semantic_dirty?, true) |> Map.put(:semantic_input_at, now()),
      else: state
  end

  @doc """
  The tick: snapshots when due. `{:fenced, state}` when another owner has taken the partition
  (this one must stop); any other failure keeps the state dirty for the next tick.
  """
  @spec tick(map()) :: {:ok, map()} | {:fenced, map()}
  def tick(state) do
    schedule(state)

    if due?(state) do
      case snapshot(state) do
        {:ok, state} -> {:ok, state}
        {:error, :semantic_runtime_fenced, state} -> {:fenced, state}
        {:error, _reason, state} -> {:ok, state}
      end
    else
      {:ok, state}
    end
  end

  @doc """
  Whether a sample's frame is already in the recovered state: the snapshot includes every frame of
  its stream that starts before the snapshot's offset, so a replay must not apply it again. Samples
  with no journal frame are never skipped.
  """
  @spec skip_replayed?(map(), map()) :: boolean()
  def skip_replayed?(%{semantic_replay_floor: floor}, %{journal_frame: {stream, offset, _at}}),
    do: offset < Map.get(floor, stream, 0)

  def skip_replayed?(_state, _sample), do: false

  @doc "Tells the streams' consumers this owner recovered from a snapshot, so they replay from it."
  @spec announce_recovery(map()) :: :ok
  def announce_recovery(%{semantic_writer: nil}), do: :ok

  def announce_recovery(state) do
    SemanticSnapshotNotifier.recovered(
      PartitionKey.identifier(state.partition_key),
      state.semantic_replay_floor
    )
  end

  @doc "Snapshots now if there is anything unsnapshotted."
  @spec flush(map()) :: map()
  def flush(%{semantic_dirty?: true} = state), do: state |> snapshot() |> unwrap()
  def flush(state), do: state

  @doc """
  The owner is stopping: a final snapshot, then the streams' consumers are told it no longer
  gates them. If the final snapshot did not commit it keeps gating, so the journal still holds
  what its last good snapshot needs (a restarted owner gates again with its first batch).
  """
  @spec stop(map()) :: map()
  def stop(state) do
    if gated?(state) do
      state = flush(state)

      if state.semantic_dirty? == false do
        SemanticSnapshotNotifier.stopped(
          PartitionKey.identifier(state.partition_key),
          state.semantic_resume
        )
      end

      state
    else
      state
    end
  end

  @doc "The progress a batch result reports to the journal consumer: who gates it, or nil."
  @spec partition(map(), map()) :: binary() | nil
  def partition(state, _result),
    do: if(gated?(state), do: PartitionKey.identifier(state.partition_key))

  defp track_stream(state, result) do
    metadata = result.raw_evidence.metadata || %{}
    stream = Map.get(metadata, "journal_stream_id") || Map.get(metadata, :journal_stream_id)

    offset =
      Map.get(result, :resume_offset) || Map.get(metadata, "journal_end_offset") ||
        Map.get(metadata, :journal_end_offset)

    if is_binary(stream) and is_integer(offset) do
      %{
        state
        | semantic_resume: Map.update(state.semantic_resume, stream, offset, &max(&1, offset))
      }
    else
      state
    end
  end

  defp due?(%{semantic_dirty?: true, semantic_snapshot_config: config} = state) do
    now = now()

    gated?(state) and
      (now - state.semantic_snapshot_at >= Keyword.fetch!(config, :interval_ms) or
         now - state.semantic_input_at >= Keyword.fetch!(config, :idle_ms))
  end

  defp due?(_state), do: false

  # `{:ok, state}`, or `{:error, reason, state}` with the state still dirty.
  defp snapshot(state) do
    case Store.snapshot(
           state.active_activation,
           state.partition_key,
           state.semantic_writer,
           state.semantic_state,
           state.semantic_resume
         ) do
      :ok ->
        SemanticSnapshotNotifier.published(
          PartitionKey.identifier(state.partition_key),
          state.semantic_resume
        )

        {:ok, %{state | semantic_dirty?: false, semantic_snapshot_at: now()}}

      {:error, reason} ->
        # Fenced: another owner has the partition, and the caller stops. Anything else retries at
        # the next tick; the journal is not released past the last snapshot.
        Logger.warning("Semantic snapshot failed: #{inspect(reason)}",
          mission_id: state.mission_id,
          partition_id: PartitionKey.identifier(state.partition_key)
        )

        {:error, reason, state}
    end
  end

  defp unwrap({:ok, state}), do: state
  defp unwrap({:error, _reason, state}), do: state

  defp now, do: System.monotonic_time(:millisecond)
end
