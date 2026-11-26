defmodule Cadence.Telemetry.Storage.QuestDB.RetentionJob do
  @moduledoc """
  Runs `QuestDB.Retention` on a timer (#693), on every node. It replaces the scripts outside the
  repo that dropped dev's day partitions.

  Dropping a day partition that is wholly past retention does not contend with ingest, which
  writes today's partition, so it does not wait for a quiet period. Two nodes dropping the same
  partition is harmless: the second finds it gone and drops nothing.

  Options: `:interval_ms` (1 h), `:run_fun` (tests), and the `Retention` settings. A run that
  fails is logged and retried on the next tick.
  """

  use GenServer

  require Logger

  alias Cadence.Telemetry.Storage.QuestDB.Retention

  @default_interval_ms 3_600_000

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Runs one retention pass now."
  @spec run_now() :: {:ok, map()} | {:error, term()}
  def run_now, do: GenServer.call(__MODULE__, :run, :infinity)

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      run_fun: Keyword.get(opts, :run_fun, &Retention.run/1),
      run_opts: Keyword.get(opts, :run_opts, [])
    }

    # The first run comes one interval after the node starts, not during boot.
    {:ok, schedule(state)}
  end

  @impl true
  def handle_call(:run, _from, state), do: {:reply, run(state), state}

  @impl true
  def handle_info(:tick, state) do
    _ = run(state)
    {:noreply, schedule(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp run(state) do
    case state.run_fun.(state.run_opts) do
      {:ok, %{dropped: []} = report} ->
        {:ok, report}

      {:ok, report} ->
        Logger.info(
          "questdb retention dropped #{length(report.dropped)} day partition(s) " <>
            "(#{report.dropped_bytes} bytes) older than #{report.cutoff}: #{Enum.join(report.dropped, ", ")}"
        )

        {:ok, report}

      {:error, reason} ->
        Logger.error("questdb retention failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp schedule(%{interval_ms: interval} = state) do
    Process.send_after(self(), :tick, interval)
    state
  end
end
