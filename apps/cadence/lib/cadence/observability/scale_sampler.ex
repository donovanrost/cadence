defmodule Cadence.Observability.ScaleSampler do
  @moduledoc """
  A per-second scorecard of a running node under fleet-scale load (#717, epic #217).

  Started for one measurement by `mix cadence.scale.run` (over RPC), never by the application:
  it attaches its own `:telemetry` handlers, uniquely named and detached when it stops. Every
  second it writes one JSON line to `:out`:

  - `ecto`: query count and queue/query time p50/p99/max (ms), from `[:cadence, :repo, :query]`
  - `ingest`: telemetry's `[:cadence, :ingest, :batch, :stop]` sums (entries, bytes, frames,
    packets, samples), `duration_us` and `journal_lag_ms` p50/p99/max, distinct paths; and the
    `[:cadence, :ingest, :journal, :backlog]` maxima. Missing measurements are skipped, not 0
    (a batch acknowledged after a restart omits them, #686).
  - `beam`: run queue, scheduler utilization, process count, memory (MB)
  - `mailboxes`: message-queue length of each name in `:processes`, plus the top `:top` overall
  - `postgres`: WAL bytes written that second

  The sampler's own WAL query is excluded from `ecto`.
  """

  use GenServer

  alias Cadence.Observability.ScaleSampler.Stats

  @repo_event [:cadence, :repo, :query]
  @batch_event [:cadence, :ingest, :batch, :stop]
  @backlog_event [:cadence, :ingest, :journal, :backlog]
  @batch_sums [:entries, :bytes, :frames, :packets, :samples]
  @batch_distributions [:duration_us, :journal_lag_ms]

  @doc """
  Starts the sampler. Options: `:out` (JSON lines path, required), `:interval_ms` (1000),
  `:processes` (registered names to watch, default []), `:top` (5), `:postgres` (true: sample
  WAL bytes; false where there's no database to ask).
  """
  @spec start(keyword()) :: GenServer.on_start()
  def start(opts), do: GenServer.start(__MODULE__, opts, name: __MODULE__)

  @doc "Stops the sampler and returns the run summary (`Stats.summarize/1` of every row)."
  @spec stop() :: {:ok, map()}
  def stop, do: GenServer.call(__MODULE__, :stop, 30_000)

  @impl true
  def init(opts) do
    # Started over RPC, this process inherits the caller's group leader; log on the node instead.
    if user = Process.whereis(:user), do: Process.group_leader(self(), user)
    out = Keyword.fetch!(opts, :out)
    File.mkdir_p!(Path.dirname(out))
    table = :ets.new(__MODULE__, [:duplicate_bag, :public, write_concurrency: true])
    handler = "cadence-scale-sampler-#{System.unique_integer([:positive])}"
    config = %{table: table, sampler: self()}

    :ok =
      :telemetry.attach_many(
        handler,
        [@repo_event, @batch_event, @backlog_event],
        &__MODULE__.handle_event/4,
        config
      )

    state0 = %{
      table: table,
      handler: handler,
      out: File.open!(out, [:write, :utf8]),
      interval_ms: Keyword.get(opts, :interval_ms, 1_000),
      processes: Keyword.get(opts, :processes, []),
      top: Keyword.get(opts, :top, 5),
      wall_time_was_on?: :erlang.system_flag(:scheduler_wall_time, true),
      scheduler: scheduler_sample(),
      postgres?: Keyword.get(opts, :postgres, true),
      wal: nil,
      rows: []
    }

    state = %{state0 | wal: wal_position(state0)}
    Process.send_after(self(), :tick, state.interval_ms)
    {:ok, state}
  end

  @doc false
  # Runs in the emitting process: cheap ETS writes only.
  def handle_event(@repo_event, measurements, _metadata, %{table: table, sampler: sampler}) do
    unless self() == sampler do
      put(table, :ecto_queue, measurements[:queue_time])
      put(table, :ecto_query, measurements[:query_time])
      :ets.insert(table, {:ecto_count, 1})
    end
  end

  def handle_event(@batch_event, measurements, metadata, %{table: table}) do
    :ets.insert(table, {:batches, 1})
    for key <- @batch_sums, do: put(table, {:sum, key}, measurements[key])
    for key <- @batch_distributions, do: put(table, key, measurements[key])
    if path = metadata[:path_id], do: :ets.insert(table, {:path, path})
  end

  def handle_event(@backlog_event, measurements, _metadata, %{table: table}) do
    put(table, :backlog_bytes, measurements[:bytes])
    put(table, :backlog_age_ms, measurements[:oldest_unacked_age_ms])
  end

  defp put(_table, _key, nil), do: true
  defp put(table, key, value) when is_number(value), do: :ets.insert(table, {key, value})
  defp put(_table, _key, _other), do: true

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, state.interval_ms)
    {:noreply, record(state)}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    state = record(state)
    {:stop, :normal, {:ok, Stats.summarize(Enum.reverse(state.rows))}, state}
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach(state.handler)

    unless state.wall_time_was_on?,
      do: :erlang.system_flag(:scheduler_wall_time, false)

    File.close(state.out)
  end

  defp record(state) do
    scheduler = scheduler_sample()
    wal = wal_position(state)

    row = %{
      t: DateTime.utc_now() |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601(),
      ecto: ecto(state.table),
      ingest: ingest(state.table),
      beam: beam(state.scheduler, scheduler),
      mailboxes: mailboxes(state.processes, state.top),
      postgres: %{wal_bytes: wal_delta(state.wal, wal)}
    }

    IO.write(state.out, [Jason.encode!(row), "\n"])
    %{state | scheduler: scheduler, wal: wal, rows: [row | state.rows]}
  end

  defp ecto(table) do
    %{
      count: table |> take(:ecto_count) |> length(),
      queue_ms: table |> take(:ecto_queue) |> Enum.map(&native_ms/1) |> Stats.distribution(),
      query_ms: table |> take(:ecto_query) |> Enum.map(&native_ms/1) |> Stats.distribution()
    }
  end

  defp ingest(table) do
    sums = Map.new(@batch_sums, &{&1, table |> take({:sum, &1}) |> Enum.sum()})

    %{
      batches: table |> take(:batches) |> length(),
      paths: table |> take(:path) |> Enum.uniq() |> length(),
      duration_us: table |> take(:duration_us) |> Stats.distribution(),
      journal_lag_ms: table |> take(:journal_lag_ms) |> Stats.distribution(),
      backlog_bytes_max: table |> take(:backlog_bytes) |> Enum.max(fn -> nil end),
      backlog_age_ms_max: table |> take(:backlog_age_ms) |> Enum.max(fn -> nil end)
    }
    |> Map.merge(sums)
  end

  defp take(table, key), do: table |> :ets.take(key) |> Enum.map(&elem(&1, 1))

  defp native_ms(native), do: System.convert_time_unit(native, :native, :microsecond) / 1_000

  defp beam(previous, current) do
    %{
      run_queue: :erlang.statistics(:total_run_queue_lengths),
      scheduler_utilization: utilization(previous, current),
      processes: :erlang.system_info(:process_count),
      memory_mb: div(:erlang.memory(:total), 1_048_576)
    }
  end

  defp scheduler_sample, do: :erlang.statistics(:scheduler_wall_time) || []

  # Busy wall time over total wall time, across schedulers, since the previous sample.
  defp utilization(previous, current) do
    before = Map.new(previous, fn {id, active, total} -> {id, {active, total}} end)

    {active, total} =
      Enum.reduce(current, {0, 0}, fn {id, active, total}, {a, t} ->
        {active0, total0} = Map.get(before, id, {active, total})
        {a + active - active0, t + total - total0}
      end)

    if total > 0, do: Float.round(active / total, 3), else: nil
  end

  defp mailboxes(names, top) do
    watched =
      Map.new(names, fn name ->
        len =
          case Process.whereis(name) do
            nil -> nil
            pid -> queue_len(pid)
          end

        {inspect(name), len}
      end)

    busiest =
      Process.list()
      |> Enum.flat_map(fn pid ->
        case queue_len(pid) do
          len when is_integer(len) and len > 0 -> [{pid, len}]
          _none -> []
        end
      end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.take(top)
      |> Enum.map(fn {pid, len} -> %{process: label(pid), len: len} end)

    %{watched: watched, top: busiest}
  end

  defp queue_len(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} -> len
      nil -> nil
    end
  end

  defp label(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, name} when is_atom(name) and name != [] -> inspect(name)
      _unnamed -> inspect(pid)
    end
  end

  defp wal_position(%{postgres?: false}), do: nil

  defp wal_position(_state) do
    sql = "select pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')::bigint"

    case Cadence.Repo.query(sql, [], log: false) do
      {:ok, %{rows: [[position]]}} -> position
      {:error, _reason} -> nil
    end
  end

  defp wal_delta(previous, current) when is_integer(previous) and is_integer(current),
    do: current - previous

  defp wal_delta(_previous, _current), do: nil
end
