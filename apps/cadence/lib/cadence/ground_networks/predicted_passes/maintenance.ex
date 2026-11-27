defmodule Cadence.GroundNetworks.PredictedPasses.Maintenance do
  @moduledoc """
  Enqueues each mission's daily predicted-pass runs (#891): the horizon extension and the prune
  (`Cadence.GroundNetworks.PredictedPasses.daily/1`). It checks hourly; the run ids are per
  mission and UTC day, so each runs once a day however often it checks, and a node that was down
  catches up on its first check.

  The first check is scheduled, never run from `init/1`, and a check that fails (a database
  outage, say) is logged and retried at the next interval. The process stays up either way, so
  a short outage can't exhaust the application supervisor's restart intensity.
  """

  use GenServer

  require Logger

  alias Cadence.GroundNetworks.PredictedPasses

  @default_interval_ms :timer.hours(1)
  @default_first_check_ms :timer.seconds(30)

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      check: Keyword.get(opts, :check, &PredictedPasses.daily/0)
    }

    Process.send_after(
      self(),
      :check,
      Keyword.get(opts, :first_check_ms, @default_first_check_ms)
    )

    {:ok, state}
  end

  @impl true
  def handle_info(:check, state) do
    check(state.check)
    Process.send_after(self(), :check, state.interval_ms)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @event "predicted_passes.daily_check_failed"

  defp check(fun) do
    case fun.() do
      :ok -> :ok
      other -> warn("returned #{inspect(other)}", "result")
    end
  rescue
    error -> warn(Exception.message(error), inspect(error.__struct__))
  catch
    :exit, reason -> warn("exited: #{inspect(reason)}", "exit")
  end

  defp warn(detail, error_class) do
    Logger.warning("Predicted-pass daily check failed, retrying at the next interval: " <> detail,
      cadence_event: @event,
      error_class: error_class
    )
  end
end
