defmodule Cadence.Persistence.Retention.Sweeper do
  @moduledoc """
  Runs one retention rule on a timer (#694), a chunk at a time.

  Each sweep deletes chunks, pausing `pause_ms` between them, until the rule says nothing is left,
  the `budget_ms` is spent, or another node holds the rule's lock. A chunk is one short
  transaction: no lock outlives it, so ingest never waits on a sweep, and the sweep never skips for
  a pass. It emits `[:cadence, :retention, :chunk]` (`rows`, `duration_us`) per chunk and
  `[:cadence, :retention, :run]` (`chunks`, `rows`, `duration_ms`) per sweep, both with the
  rule's name, for #686's scorecard.

  A failing sweep is logged and retried at the next tick; the cursor of a walk that has not ended
  is kept, so the next sweep resumes where this one stopped.
  """

  use GenServer

  require Logger

  alias Cadence.Persistence.Retention
  alias Cadence.Repo

  @chunk_timeout_ms 60_000

  def child_spec(opts) do
    rule = Keyword.fetch!(opts, :rule)
    %{id: {__MODULE__, rule}, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  def start_link(opts) do
    rule = Keyword.fetch!(opts, :rule)
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, rule))
  end

  @doc "Runs one sweep now and returns its report."
  @spec run_now(GenServer.server()) :: map()
  def run_now(server), do: GenServer.call(server, :run, :infinity)

  @doc """
  One sweep of `rule` from `cursor`: `%{chunks, rows, stopped, cursor}`, `stopped` one of `:done`,
  `:budget`, `:locked` or `{:error, reason}`. Options override the settings (`:now`, `:pause_ms`).
  """
  @spec sweep(module(), term(), keyword()) :: map()
  def sweep(rule, cursor, opts \\ []) do
    settings = Keyword.merge(Retention.settings(), opts)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    started = System.monotonic_time(:millisecond)

    report =
      walk(rule, cursor, now, settings, started, %{
        chunks: 0,
        rows: 0,
        stopped: nil,
        cursor: cursor
      })

    :telemetry.execute(
      [:cadence, :retention, :run],
      %{
        chunks: report.chunks,
        rows: report.rows,
        duration_ms: System.monotonic_time(:millisecond) - started
      },
      %{rule: rule.name()}
    )

    report
  end

  @impl true
  def init(opts) do
    rule = Keyword.fetch!(opts, :rule)
    state = %{rule: rule, cursor: rule.initial_cursor(), opts: Keyword.delete(opts, :rule)}
    {:ok, schedule(state)}
  end

  @impl true
  def handle_call(:run, _from, state) do
    {report, state} = run(state)
    {:reply, report, state}
  end

  @impl true
  def handle_info(:tick, state) do
    {_report, state} = run(state)
    {:noreply, schedule(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp run(%{rule: rule, cursor: cursor, opts: opts} = state) do
    report = sweep(rule, cursor, opts)
    log(rule, report)

    next =
      case report.stopped do
        :done -> rule.initial_cursor()
        _resumable -> report.cursor
      end

    {report, %{state | cursor: next}}
  end

  defp schedule(%{opts: opts} = state) do
    interval = Keyword.get(opts, :interval_ms) || Retention.settings()[:interval_ms]
    Process.send_after(self(), :tick, interval)
    state
  end

  defp walk(rule, cursor, now, settings, started, report) do
    case chunk(rule, cursor, now, settings) do
      :locked ->
        %{report | stopped: :locked}

      {:error, reason} ->
        %{report | stopped: {:error, reason}}

      {:ok, status, rows, next} ->
        report = %{report | chunks: report.chunks + 1, rows: report.rows + rows, cursor: next}

        continue(rule, status, next, now, settings, started, report)
    end
  end

  defp continue(_rule, :done, _next, _now, _settings, _started, report),
    do: %{report | stopped: :done}

  defp continue(rule, :more, next, now, settings, started, report) do
    if System.monotonic_time(:millisecond) - started >= settings[:budget_ms] do
      %{report | stopped: :budget}
    else
      if settings[:pause_ms] > 0, do: Process.sleep(settings[:pause_ms])
      walk(rule, next, now, settings, started, report)
    end
  end

  # One chunk: its own transaction, under the rule's advisory lock, then whatever it left to do
  # (files) once the rows are gone.
  defp chunk(rule, cursor, now, settings) do
    started = System.monotonic_time(:microsecond)

    result =
      Repo.transaction(
        fn ->
          if lock?(rule), do: rule.sweep_chunk(cursor, now, settings), else: :locked
        end,
        timeout: @chunk_timeout_ms
      )

    case result do
      {:ok, :locked} ->
        :locked

      {:ok, {status, rows, next, after_commit}} ->
        after_commit.()

        :telemetry.execute(
          [:cadence, :retention, :chunk],
          %{rows: rows, duration_us: System.monotonic_time(:microsecond) - started},
          %{rule: rule.name()}
        )

        {:ok, status, rows, next}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp lock?(rule) do
    %{rows: [[locked]]} =
      Repo.query!("SELECT pg_try_advisory_xact_lock(hashtext($1))", ["retention:#{rule.name()}"])

    locked
  end

  defp log(rule, %{stopped: {:error, reason}}),
    do: Logger.error("retention #{rule.name()} failed, resumes next sweep: #{inspect(reason)}")

  defp log(_rule, %{rows: 0, stopped: stopped}) when stopped in [:done, :locked], do: :ok

  defp log(rule, report) do
    Logger.info(
      "retention #{rule.name()} deleted #{report.rows} row(s) in #{report.chunks} chunk(s), " <>
        "stopped: #{inspect(report.stopped)}"
    )
  end
end
