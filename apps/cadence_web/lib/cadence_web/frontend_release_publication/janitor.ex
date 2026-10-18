defmodule CadenceWeb.FrontendReleasePublication.Janitor do
  @moduledoc """
  Periodically removes expired, unreferenced frontend release stages.

  The production child always uses `DatabaseArtifactStore`; only the interval
  and process name are overridable for deterministic supervision tests.
  """

  use GenServer

  require Logger

  alias CadenceWeb.FrontendReleasePublication.DatabaseArtifactStore

  @interval_ms 60_000

  @type state :: %{interval_ms: pos_integer(), timer_ref: reference()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    interval_ms = Keyword.get(opts, :interval_ms, @interval_ms)

    if is_integer(interval_ms) and interval_ms > 0 do
      {:ok, %{interval_ms: interval_ms, timer_ref: schedule(interval_ms)}}
    else
      {:stop, :invalid_interval}
    end
  end

  @impl true
  def handle_info(:cleanup, %{interval_ms: interval_ms} = state) do
    cleanup_once()
    {:noreply, %{state | timer_ref: schedule(interval_ms)}}
  end

  defp schedule(interval_ms), do: Process.send_after(self(), :cleanup, interval_ms)

  defp cleanup_once do
    case DatabaseArtifactStore.cleanup_expired_staged_artifacts() do
      {:ok, _count} -> :ok
      {:error, {:stage_cleanup, reason}} -> report_database_failure(reason)
    end
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      report_database_failure(error)
  end

  defp report_database_failure(reason) do
    Logger.warning("Frontend release stage cleanup did not complete: #{inspect(reason)}")
    :ok
  end
end
