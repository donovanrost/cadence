defmodule Cadence.Control.IdentityStateRetention do
  @moduledoc """
  #359 (a): deletes trivial observation identity states once they can't matter any more
  (`Cadence.Telemetry.Storage.ObservationIdentityStates.Retention` has the rule). It replaces
  qa's nightly `identity-states-prune.sh`, which retires once this runs live on dev.

  **The cutoff** is the LATER of two windows before `now`, so a state goes only when both have
  passed:

    * `observation_retention_hours`: how long the observation store keeps the observation (QuestDB's
      day partitions; 48 h on the dev stack). Unset means unknown, and nothing is deleted;
    * the re-delivery window: the contacts journal's retention after settlement
      (`Cadence.Contacts.JournalReclaim.retention_ms/0`, 72 h) plus `settlement_allowance_hours`
      (24 h: a pass's observations settle within a day). 96 h today.

  Every `tick_ms` (1 h) it walks the table along its primary key, `scan_size` (10,000) states per
  batch, at most `max_batches` (100) batches per tick, pausing `pause_ms` between them. The walk
  resumes where the last tick stopped and starts over after the end, so one pass over the table
  is spread over several ticks.

  Modes (`mode:` option, else `CADENCE_IDENTITY_STATE_RETENTION`, else `:dry`):

    * `:dry` (the default): counts what it would delete and logs it; deletes nothing;
    * `:live`: deletes;
    * `:off`: does nothing.

  It never vacuums: Postgres's autovacuum makes the space reusable, and nothing returns it to the
  disk (VACUUM FULL or a repack is a separate, planned step).
  """

  use GenServer

  require Logger

  alias Cadence.Contacts.JournalReclaim
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.Retention

  @env "CADENCE_IDENTITY_STATE_RETENTION"
  @hour_ms 3_600_000
  @defaults [
    tick_ms: @hour_ms,
    scan_size: 10_000,
    max_batches: 100,
    pause_ms: 200,
    settlement_allowance_hours: 24
  ]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))

  @doc "Runs one tick now (tests, operators)."
  @spec run_now(GenServer.server()) :: map()
  def run_now(server \\ __MODULE__), do: GenServer.call(server, :run, :infinity)

  @doc """
  The cutoff at `now`: the later of the observation retention and the re-delivery window, so the
  EARLIER instant. `nil` when the observation retention isn't configured (nothing is deleted).
  """
  @spec cutoff(DateTime.t(), keyword()) :: DateTime.t() | nil
  def cutoff(%DateTime{} = now, opts \\ []) do
    opts = settings(opts)

    case Keyword.get(opts, :observation_retention_hours) do
      hours when is_integer(hours) and hours > 0 ->
        redelivery_ms =
          Keyword.get_lazy(opts, :journal_retention_ms, &JournalReclaim.retention_ms/0) +
            Keyword.fetch!(opts, :settlement_allowance_hours) * @hour_ms

        # Whole seconds; rounding down only makes the cutoff earlier (keeps more).
        now
        |> DateTime.add(-max(hours * @hour_ms, redelivery_ms), :millisecond)
        |> DateTime.truncate(:second)

      _unset ->
        nil
    end
  end

  @doc """
  One tick from `cursor` (`""` = the start). Returns `%{mode, cutoff, scanned, matched, batches,
  cursor, stopped}`; `matched` is what was deleted (`:live`) or would be (`:dry`).
  """
  @spec run(keyword()) :: map()
  def run(opts \\ []) do
    opts = settings(opts)
    mode = mode(opts)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    cursor = Keyword.get(opts, :cursor, "")

    case {mode, cutoff(now, opts)} do
      {:off, _cutoff} -> outcome(mode, nil, cursor, :off)
      {_mode, nil} -> outcome(mode, nil, cursor, :no_observation_retention)
      {_mode, cutoff} -> walk(%{outcome(mode, cutoff, cursor, nil) | batches: 0}, opts)
    end
  end

  @doc "The mode a tick runs in: the `mode:` option, else the environment, else `:dry`."
  @spec mode(keyword()) :: :dry | :live | :off
  def mode(opts \\ []) do
    case Keyword.get(opts, :mode) || System.get_env(@env) do
      mode when mode in [:dry, :live, :off] -> mode
      "live" -> :live
      "off" -> :off
      _dry_or_unset -> :dry
    end
  end

  @impl true
  def init(opts) do
    state = %{opts: settings(opts), cursor: ""}
    schedule(state.opts)
    {:ok, state}
  end

  @impl true
  def handle_call(:run, _from, state) do
    outcome = tick(state)
    {:reply, outcome, %{state | cursor: next_cursor(outcome)}}
  end

  @impl true
  def handle_info(:tick, state) do
    cursor = state |> safely_tick() |> next_cursor()
    schedule(state.opts)
    {:noreply, %{state | cursor: cursor}}
  end

  defp tick(state), do: state.opts |> Keyword.put(:cursor, state.cursor) |> run() |> tap(&log/1)

  # The walk starts over after it reached the end; otherwise it resumes from the last id read.
  defp next_cursor(%{stopped: :end}), do: ""
  defp next_cursor(%{cursor: cursor}), do: cursor

  defp walk(outcome, opts) do
    batch = Retention.batch(outcome.mode, outcome.cursor, outcome.cutoff, opts[:scan_size])

    outcome = %{
      outcome
      | scanned: outcome.scanned + batch.scanned,
        matched: outcome.matched + batch.matched,
        batches: outcome.batches + 1,
        cursor: batch.cursor
    }

    cond do
      batch.scanned < opts[:scan_size] -> %{outcome | stopped: :end}
      outcome.batches >= opts[:max_batches] -> %{outcome | stopped: :batch_limit}
      true -> pause_then_walk(outcome, opts)
    end
  end

  defp pause_then_walk(outcome, opts) do
    if opts[:pause_ms] > 0, do: Process.sleep(opts[:pause_ms])
    walk(outcome, opts)
  end

  defp outcome(mode, cutoff, cursor, stopped),
    do: %{
      mode: mode,
      cutoff: cutoff,
      scanned: 0,
      matched: 0,
      batches: 0,
      cursor: cursor,
      stopped: stopped
    }

  defp settings(opts) do
    @defaults
    |> Keyword.merge(Application.get_env(:cadence, __MODULE__, []))
    |> Keyword.merge(opts)
  end

  defp log(%{matched: 0}), do: :ok

  defp log(outcome) do
    Logger.info(
      "identity state retention #{outcome.mode} cutoff=#{inspect(outcome.cutoff)} " <>
        "scanned=#{outcome.scanned} matched=#{outcome.matched} batches=#{outcome.batches} " <>
        "stopped=#{outcome.stopped}"
    )
  end

  # A failing tick (database unavailable, table not migrated yet) must not crash-loop the control
  # supervisor; the next tick resumes from the same cursor.
  defp safely_tick(state) do
    tick(state)
  rescue
    error ->
      Logger.warning("identity state retention failed: #{Exception.message(error)}")
      %{cursor: state.cursor, stopped: :failed}
  end

  defp schedule(opts) do
    case Keyword.get(opts, :tick_ms) do
      ms when is_integer(ms) and ms > 0 -> Process.send_after(self(), :tick, ms)
      _off -> :ok
    end
  end
end
