# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule Cadence.Protocol.RecordArchive.FileSystem.Writer.Mission do
  @moduledoc false
  # One mission's archive writer (#688). Its buffer, segment id, retry state and timer are one
  # partition's, so a slow or failing flush stalls only that partition.
  #
  # Group commit: a `flush` call is not run on arrival. It waits, and one `:run_flush` message,
  # queued behind everything already in the mailbox, flushes every enqueue that arrived meanwhile
  # in one segment, one fsync and one index insert. Each waiter is answered only after that flush
  # returns, so no caller is told its entries are durable before they are. `batches_flushed` counts
  # the enqueues each flush carried.

  use GenServer, restart: :temporary

  require Logger

  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Protocol.RecordArchive.{FileSystem, Quarantine}
  alias Cadence.Protocol.RecordArchive.FileSystem.PoisonIsolation

  @idle_check_ms 60_000

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @doc "The zero stats a mission without a writer reports."
  def idle_stats, do: build_stats(new_state(%{mission_id: nil}))

  @impl true
  def init(opts) do
    Process.send_after(self(), :idle_check, @idle_check_ms)

    {:ok,
     new_state(%{
       mission_id: Keyword.fetch!(opts, :mission_id),
       base_path: Keyword.fetch!(opts, :base_path),
       repo: Keyword.fetch!(opts, :repo),
       archive_backend: Keyword.fetch!(opts, :archive_backend),
       flush_interval_ms: Keyword.fetch!(opts, :flush_interval_ms),
       flush_count: Keyword.fetch!(opts, :flush_count)
     })}
  end

  defp new_state(config) do
    Map.merge(config, %{
      buffer: :queue.new(),
      size: 0,
      batches: 0,
      segment_id: nil,
      retries: 0,
      timer: nil,
      started_at_ms: nil,
      active?: true,
      waiters: [],
      flush_requested?: false,
      metrics: zero_metrics()
    })
  end

  @impl true
  def handle_call({:enqueue, entries}, _from, state) do
    state = %{state | active?: true}

    if state.retries > 0 do
      # The journal still owns unacknowledged work. A failed flush must not let its caller's
      # retries append another copy of that same batch.
      {:reply, {:error, {:protocol_archive_backpressured, state.mission_id}}, state}
    else
      {:reply, :ok, enqueue(state, entries)}
    end
  end

  def handle_call(:backpressured?, _from, state), do: {:reply, state.retries > 0, state}

  def handle_call(:flush, from, state) do
    state = %{state | active?: true}

    cond do
      state.size == 0 and state.waiters == [] ->
        {:reply, :ok, state}

      state.flush_requested? ->
        {:noreply, %{state | waiters: [from | state.waiters]}}

      true ->
        send(self(), :run_flush)
        {:noreply, %{state | waiters: [from | state.waiters], flush_requested?: true}}
    end
  end

  def handle_call(:stats, _from, state), do: {:reply, build_stats(state), state}

  def handle_call(:reset_stats, _from, state),
    do: {:reply, :ok, %{state | metrics: zero_metrics()}}

  # A reset drops the buffer, so a flush waiting on it is answered: there is nothing left to flush.
  def handle_call(:reset, _from, state) do
    Enum.each(state.waiters, &GenServer.reply(&1, :ok))

    {:reply, :ok,
     state
     |> cancel_timer()
     |> Map.merge(Map.take(new_state(%{}), reset_keys()))
     |> Map.put(:waiters, [])}
  end

  @impl true
  def handle_info(:run_flush, state) do
    state = %{state | flush_requested?: false}
    {result, next} = run_flush(state)
    Enum.each(next.waiters, &GenServer.reply(&1, result))
    {:noreply, %{next | waiters: []}}
  end

  def handle_info({:flush, flush_ref}, %{timer: {_ref, flush_ref}} = state) do
    case run_flush(%{state | timer: nil}) do
      {:ok, next} ->
        {:noreply, next}

      {{:error, reason}, next} ->
        Logger.error(
          "protocol record archive flush failed for #{state.mission_id}: #{inspect(reason)}"
        )

        {:noreply, next}
    end
  end

  def handle_info({:flush, _stale_ref}, state), do: {:noreply, state}

  # A writer with nothing buffered, nothing retrying and no call since the last check goes away;
  # the next enqueue starts a fresh one.
  def handle_info(:idle_check, state) do
    if state.size == 0 and state.retries == 0 and not state.active? do
      {:stop, :normal, state}
    else
      Process.send_after(self(), :idle_check, @idle_check_ms)
      {:noreply, %{state | active?: false}}
    end
  end

  # A failed flush keeps its buffer and retries on a timer.
  defp run_flush(state) do
    case flush(state) do
      {:ok, next} -> {:ok, next}
      {:error, reason, next} -> {{:error, reason}, reschedule(next, retry_delay_ms(next))}
    end
  end

  defp reset_keys,
    do: [:buffer, :size, :batches, :segment_id, :retries, :timer, :started_at_ms, :metrics]

  defp enqueue(state, entries) do
    next_size = state.size + length(entries)

    state = %{
      state
      | buffer: :queue.join(state.buffer, :queue.from_list(entries)),
        size: next_size,
        batches: state.batches + 1,
        started_at_ms: state.started_at_ms || System.monotonic_time(:millisecond)
    }

    state = if state.timer, do: state, else: schedule(state, state.flush_interval_ms)

    if next_size >= state.flush_count, do: reschedule(state, 0), else: state
  end

  defp retry_delay_ms(state) do
    multiplier = Integer.pow(2, min(max(state.retries - 1, 0), 5))
    min(max(state.flush_interval_ms, 250) * multiplier, 5_000)
  end

  defp reschedule(state, delay_ms), do: state |> cancel_timer() |> schedule(delay_ms)

  defp schedule(state, delay_ms) do
    flush_ref = make_ref()
    timer_ref = Process.send_after(self(), {:flush, flush_ref}, delay_ms)
    %{state | timer: {timer_ref, flush_ref}}
  end

  defp cancel_timer(%{timer: nil} = state), do: state

  defp cancel_timer(%{timer: {timer_ref, _flush_ref}} = state) do
    _ = Process.cancel_timer(timer_ref)
    %{state | timer: nil}
  end

  defp flush(%{size: 0} = state), do: {:ok, cancel_timer(state)}

  defp flush(state) do
    state =
      state |> cancel_timer() |> Map.update!(:segment_id, &(&1 || FileSystem.new_segment_id()))

    entries = :queue.to_list(state.buffer)
    started_us = System.monotonic_time(:microsecond)

    case persist_entries(state, entries) do
      {:ok, segment_size_bytes} ->
        {:ok, flushed(state, length(entries), segment_size_bytes, started_us)}

      {:error, reason, quarantined} ->
        state |> drop_quarantined(quarantined) |> failed_flush(reason)

      {:error, reason} ->
        failed_flush(state, reason)
    end
  end

  defp flushed(state, count, size_bytes, started_us) do
    duration_us = System.monotonic_time(:microsecond) - started_us

    metrics =
      state.metrics
      |> Map.update!(:flush_count, &(&1 + 1))
      |> Map.update!(:flushed_count, &(&1 + count))
      |> Map.update!(:batches_flushed, &(&1 + state.batches))
      |> Map.update!(:segment_count, &(&1 + 1))
      |> Map.update!(:flushed_bytes_total, &(&1 + size_bytes))
      |> Map.update!(:flush_total_us, &(&1 + duration_us))
      |> Map.put(:last_completed_at, DateTime.utc_now())
      |> Map.put(:last_flush_error, nil)

    %{
      state
      | buffer: :queue.new(),
        size: 0,
        batches: 0,
        segment_id: nil,
        retries: 0,
        started_at_ms: nil,
        metrics: metrics
    }
  end

  defp failed_flush(state, reason) do
    metrics =
      state.metrics
      |> Map.update!(:flush_failure_count, &(&1 + 1))
      |> Map.put(:last_flush_error, inspect(reason))

    {:error, reason, %{state | retries: state.retries + 1, metrics: metrics}}
  end

  defp persist_entries(state, entries) do
    # Backpressure keeps this batch unchanged until indexing succeeds. Reuse its
    # immutable object on retry instead of leaking a new segment on every error.
    mission_id = state.mission_id
    organization_id = OrganizationScope.organization_id_for_mission(mission_id)

    opts = [
      base_path: state.base_path,
      organization_id: organization_id,
      archive_backend: state.archive_backend,
      repo: state.repo
    ]

    # DECISIONS #88: entries that can never be indexed are quarantined and the rest flushes, so
    # the mission's storage goes on (their own samples included); anything else stays transient.
    quarantine = &Quarantine.put(mission_id, organization_id, &1, DateTime.utc_now())

    case PoisonIsolation.persist(state.segment_id, entries, opts, quarantine) do
      {:ok, %{size_bytes: size_bytes, quarantined: quarantined}} ->
        announce_quarantine(organization_id, mission_id, quarantined)
        {:ok, size_bytes}

      {:error, reason, quarantined} ->
        announce_quarantine(organization_id, mission_id, quarantined)
        {:error, reason, quarantined}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    exception in [DBConnection.ConnectionError, Postgrex.Error] ->
      # Ecto raises on checkout/connection/query failures. Keep the buffer and
      # use the same retry path as an explicit persistence error; never report
      # archival success or restart the writer after an unavailable database.
      {:error, {:archive_database_error, Exception.message(exception)}}
  end

  defp announce_quarantine(_organization_id, _mission_id, []), do: :ok

  defp announce_quarantine(organization_id, mission_id, quarantined) do
    Logger.warning(
      "protocol record archive quarantined #{length(quarantined)} entries for #{mission_id}"
    )

    ScopedReadUpdates.publish(:attention_changed, organization_id, mission_id)
  end

  # A flush that ended transient after quarantining some entries: they leave the buffer, and the
  # retry takes a fresh segment id (the retained one held them), so every retry makes progress.
  defp drop_quarantined(state, quarantined) do
    gone = MapSet.new(quarantined, &{&1.entry["record_kind"], &1.entry["record_id"]})

    queue =
      :queue.filter(
        &(not MapSet.member?(gone, {&1["record_kind"], &1["record_id"]})),
        state.buffer
      )

    %{state | buffer: queue, size: :queue.len(queue), segment_id: nil}
  end

  defp build_stats(state) do
    metrics = state.metrics

    oldest_buffered_age_ms =
      case state.started_at_ms do
        nil -> 0
        started_at_ms -> max(System.monotonic_time(:millisecond) - started_at_ms, 0)
      end

    %{
      queue_depth: state.size,
      processing?: state.timer != nil,
      backpressured?: state.retries > 0,
      oldest_buffered_age_ms: oldest_buffered_age_ms,
      flush_count: metrics.flush_count,
      flush_failure_count: metrics.flush_failure_count,
      last_error: metrics.last_flush_error,
      last_flush_error: metrics.last_flush_error,
      last_completed_at: metrics.last_completed_at,
      flushed_count: metrics.flushed_count,
      batches_flushed: metrics.batches_flushed,
      avg_batches_per_flush: average(metrics.batches_flushed, metrics.flush_count),
      segment_count: metrics.segment_count,
      flush_total_us: metrics.flush_total_us,
      avg_flush_us: average(metrics.flush_total_us, metrics.flush_count),
      flushed_bytes_total: metrics.flushed_bytes_total,
      avg_segment_bytes: average(metrics.flushed_bytes_total, metrics.segment_count)
    }
  end

  defp zero_metrics do
    %{
      flush_count: 0,
      flush_failure_count: 0,
      last_flush_error: nil,
      last_completed_at: nil,
      flushed_count: 0,
      batches_flushed: 0,
      segment_count: 0,
      flush_total_us: 0,
      flushed_bytes_total: 0
    }
  end

  defp average(_total, 0), do: 0.0
  defp average(total, count), do: total / count
end
