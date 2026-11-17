defmodule Cadence.Control.SemanticCommitRetirement do
  @moduledoc """
  Retires semantic runtime commits behind their partition's checkpoint after each pass (DECISIONS
  #94; #101's rules, `Cadence.SemanticRuntime.CommitRetirement`). Every `tick_ms` (5 min) it takes
  the partitions with no commit for `quiet_ms` (2 min: the pass has ended, or the partition is
  idle) and retires up to `max_batches` × `batch_size` (40 × 5,000) commits in each. A partition
  in a pass is never touched, and each batch re-checks that inside its own statement.

  Modes (`mode:` option, else `CADENCE_SEMANTIC_COMMIT_RETIREMENT`, else `:dry`):

    * `:dry` (the default): counts what it would retire and logs it; deletes nothing;
    * `:live`: retires;
    * `:off`: does nothing.

  One `:info` line per partition per tick when there is something to retire, nothing per batch.
  It never vacuums (Postgres reuses the space) and refuses to run while any table other than the
  checkpoints references the commits.
  """

  use GenServer

  require Logger

  alias Cadence.SemanticRuntime.CommitRetirement

  @env "CADENCE_SEMANTIC_COMMIT_RETIREMENT"
  @defaults [
    tick_ms: 300_000,
    quiet_ms: 120_000,
    batch_size: 5_000,
    max_batches: 40,
    pause_ms: 200
  ]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))

  @doc "Runs one sweep now (tests, operators); returns one entry per partition looked at."
  @spec run_now(GenServer.server()) :: [map()]
  def run_now(server \\ __MODULE__), do: GenServer.call(server, :run, :infinity)

  @doc """
  One sweep. Returns `[%{partition, mode, rows, batches, ms, stopped}]` for the quiet partitions
  that had something to retire (`:dry`: the count it would retire, 0 batches).
  """
  @spec run(keyword()) :: [map()] | {:refused, [binary()]}
  def run(opts \\ []) do
    opts = Keyword.merge(@defaults, opts)
    mode = mode(opts)

    case {mode, CommitRetirement.unexpected_foreign_keys()} do
      {:off, _keys} ->
        []

      {_mode, []} ->
        now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
        cutoff = DateTime.add(now, -Keyword.fetch!(opts, :quiet_ms), :millisecond)

        cutoff
        |> CommitRetirement.quiet_partitions()
        |> Enum.map(&sweep(&1, mode, cutoff, opts))
        |> Enum.reject(&(&1.rows == 0))
        |> tap(&Enum.each(&1, fn outcome -> log(outcome) end))

      {_mode, keys} ->
        Logger.warning(
          "semantic commit retirement refused: other tables reference the commits: " <>
            Enum.join(keys, ", ")
        )

        {:refused, keys}
    end
  end

  @doc "The mode a sweep runs in: the `mode:` option, else the environment, else `:dry`."
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
    state = Keyword.merge(@defaults, opts)
    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:run, _from, state), do: {:reply, run(state), state}

  @impl true
  def handle_info(:tick, state) do
    safely_run(state)
    schedule(state)
    {:noreply, state}
  end

  defp sweep(partition, :dry, cutoff, _opts) do
    started = System.monotonic_time(:millisecond)
    rows = CommitRetirement.retirable_count(partition, cutoff)
    ms = System.monotonic_time(:millisecond) - started
    %{partition: partition, mode: :dry, rows: rows, batches: 0, ms: ms, stopped: :dry}
  end

  defp sweep(partition, :live, cutoff, opts) do
    partition
    |> CommitRetirement.retire(cutoff, Keyword.take(opts, [:batch_size, :max_batches, :pause_ms]))
    |> Map.merge(%{partition: partition, mode: :live})
  end

  defp log(%{partition: partition} = outcome) do
    Logger.info(
      "semantic commit retirement #{outcome.mode} mission=#{partition.mission_id} " <>
        "partition=#{partition.partition_id} " <>
        "basis=#{String.slice(partition.runtime_basis_sha256, 0, 12)} " <>
        "rows=#{outcome.rows} batches=#{outcome.batches} ms=#{outcome.ms} " <>
        "stopped=#{outcome.stopped}"
    )
  end

  # A failing sweep (database unavailable, table not migrated yet) must not crash-loop the
  # control supervisor; the next tick tries again.
  defp safely_run(state) do
    run(state)
  rescue
    error -> Logger.warning("semantic commit retirement failed: #{Exception.message(error)}")
  end

  defp schedule(state) do
    case Keyword.get(state, :tick_ms) do
      ms when is_integer(ms) and ms > 0 -> Process.send_after(self(), :tick, ms)
      _off -> :ok
    end
  end
end
