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
  - `mailboxes`: per watched module, the processes with a backlog and their sum and max, plus
    the busiest processes (`ScaleSampler.Mailboxes`)
  - `storage`: Postgres WAL bytes that second, QuestDB WAL lag (`ScaleSampler.Storage`)
  - `host`: load average, swap used and agent processes on the machine (`ScaleSampler.Host`)

  It never outlives its run: it monitors `:owner` (the runner, usually on another node; a
  Ctrl-C or a lost connection stops it) and stops itself at `:max_ms` whatever happens.

  The summary adds the run's settings (`meta`) and, per watched table, rows and bytes written
  over the run in Postgres and QuestDB. The sampler's own queries are excluded from `ecto`.
  """

  use GenServer

  alias Cadence.Observability.ScaleSampler.{Host, Mailboxes, Stats, Storage}

  @repo_event [:cadence, :repo, :query]
  @batch_event [:cadence, :ingest, :batch, :stop]
  @backlog_event [:cadence, :ingest, :journal, :backlog]
  @batch_sums [:entries, :bytes, :frames, :packets, :samples]
  @batch_distributions [:duration_us, :journal_lag_ms]

  @doc """
  Starts the sampler. Options: `:out` (JSON lines path, required), `:interval_ms` (1000),
  `:modules` (mailboxes to watch, default []), `:top` (5), `:postgres_tables` /
  `:questdb_tables` (`Storage` defaults), `:postgres` (true; false where there's no database to
  ask), `:questdb_exec` (a `sql -> result` function for QuestDB; no QuestDB probes without it),
  `:owner` (a pid; the sampler stops when it goes down) and `:max_ms` (required: a hard stop).
  """
  @spec start(keyword()) :: GenServer.on_start()
  def start(opts), do: GenServer.start(__MODULE__, opts, name: __MODULE__)

  @doc "Stops the sampler and returns the run summary: `meta`, `storage` deltas and `metrics`."
  @spec stop() :: {:ok, map()}
  def stop, do: GenServer.call(__MODULE__, :stop, 60_000)

  @impl true
  def init(opts) do
    # Started over RPC, this process inherits the caller's group leader; log on the node instead.
    if user = Process.whereis(:user), do: Process.group_leader(self(), user)
    out = Keyword.fetch!(opts, :out)
    max_ms = Keyword.fetch!(opts, :max_ms)
    if owner = Keyword.get(opts, :owner), do: Process.monitor(owner)
    Process.send_after(self(), :deadline, max_ms)
    File.mkdir_p!(Path.dirname(out))
    table = :ets.new(__MODULE__, [:duplicate_bag, :public, write_concurrency: true])
    handler = "cadence-scale-sampler-#{System.unique_integer([:positive])}"
    events = [@repo_event, @batch_event, @backlog_event]

    :ok =
      :telemetry.attach_many(handler, events, &__MODULE__.handle_event/4, %{
        table: table,
        sampler: self()
      })

    state =
      %{
        table: table,
        handler: handler,
        out: File.open!(out, [:write, :utf8]),
        interval_ms: Keyword.get(opts, :interval_ms, 1_000),
        modules: Keyword.get(opts, :modules, []),
        top: Keyword.get(opts, :top, 5),
        postgres?: Keyword.get(opts, :postgres, true),
        questdb_exec: Keyword.get(opts, :questdb_exec),
        pg_tables: Keyword.get(opts, :postgres_tables, Storage.default_postgres_tables()),
        qdb_tables: Keyword.get(opts, :questdb_tables, Storage.default_questdb_tables()),
        wall_time_was_on?: :erlang.system_flag(:scheduler_wall_time, true),
        scheduler: scheduler_sample(),
        started_at: DateTime.utc_now(),
        owner: Keyword.get(opts, :owner),
        rows: []
      }
      |> disable_unreachable_questdb()
      |> then(&Map.merge(&1, %{wal: wal(&1), storage_start: storage_snapshot(&1)}))

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

  defp put(table, key, value) when is_number(value), do: :ets.insert(table, {key, value})
  defp put(_table, _key, _missing), do: true

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, state.interval_ms)
    {:noreply, record(state)}
  end

  # The runner is gone (Ctrl-C, crash, lost connection) or the run overran: nobody will ask for
  # the summary, so stop; the JSON lines written so far stay on disk.
  def handle_info({:DOWN, _ref, :process, owner, _reason}, %{owner: owner} = state),
    do: {:stop, :normal, state}

  def handle_info(:deadline, state), do: {:stop, :normal, state}

  @impl true
  def handle_call(:stop, _from, state) do
    state = record(state)

    summary =
      state.rows
      |> Enum.reverse()
      |> Stats.summarize()
      |> Map.put(:meta, meta(state))
      |> Map.put(:storage, storage_deltas(state))

    {:stop, :normal, {:ok, summary}, state}
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach(state.handler)
    unless state.wall_time_was_on?, do: :erlang.system_flag(:scheduler_wall_time, false)
    File.close(state.out)
  end

  defp record(state) do
    scheduler = scheduler_sample()
    wal = wal(state)

    row = %{
      t: DateTime.utc_now() |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601(),
      ecto: ecto(state.table),
      ingest: ingest(state.table),
      beam: beam(state.scheduler, scheduler),
      mailboxes: Mailboxes.sample(state.modules, state.top),
      host: Host.sample(),
      storage: %{
        postgres_wal_bytes: delta(state.wal, wal),
        questdb_wal_lag: if(state.questdb_exec, do: Storage.questdb_wal_lag(state.questdb_exec))
      }
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

  # `:undefined` until the scheduler_wall_time flag is on (init turns it on).
  defp scheduler_sample do
    case :erlang.statistics(:scheduler_wall_time) do
      samples when is_list(samples) -> samples
      :undefined -> []
    end
  end

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

  # Probed once: if QuestDB doesn't answer at the start, the run records that and doesn't ask again.
  defp disable_unreachable_questdb(%{questdb_exec: nil} = state),
    do: Map.put(state, :questdb_status, :not_configured)

  defp disable_unreachable_questdb(state) do
    case Storage.questdb_wal_lag(state.questdb_exec) do
      nil -> %{state | questdb_exec: nil} |> Map.put(:questdb_status, :unreachable)
      _lag -> Map.put(state, :questdb_status, :ok)
    end
  end

  defp wal(%{postgres?: true}), do: Storage.wal_position()
  defp wal(_state), do: nil

  defp delta(previous, current) when is_integer(previous) and is_integer(current),
    do: current - previous

  defp delta(_previous, _current), do: nil

  defp storage_snapshot(state) do
    %{
      postgres: if(state.postgres?, do: Storage.postgres_tables(state.pg_tables), else: %{}),
      questdb:
        if(state.questdb_exec,
          do: Storage.questdb_tables(state.questdb_exec, state.qdb_tables),
          else: %{}
        )
    }
  end

  defp storage_deltas(state) do
    finish = storage_snapshot(state)

    %{
      postgres: Storage.deltas(state.storage_start.postgres, finish.postgres),
      questdb: Storage.deltas(state.storage_start.questdb, finish.questdb)
    }
  end

  # What makes two runs comparable; the git sha is added by the runner.
  defp meta(state) do
    journal = Application.get_env(:cadence, :ingress_journal, [])

    %{
      node: node(),
      started_at: DateTime.to_iso8601(state.started_at),
      otp: System.otp_release(),
      elixir: System.version(),
      schedulers: System.schedulers_online(),
      pool_size: Application.get_env(:cadence, Cadence.Repo, [])[:pool_size],
      journal_enabled: Keyword.get(journal, :enabled?),
      journal_durability: Keyword.get(journal, :durability),
      questdb: state.questdb_status,
      host: Host.info()
    }
  end
end
