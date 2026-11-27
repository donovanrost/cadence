defmodule Cadence.GroundNetworks.PredictedPasses.Maintenance do
  @moduledoc """
  Enqueues each mission's daily predicted-pass runs (#891): the horizon extension and the prune
  (`Cadence.GroundNetworks.PredictedPasses.daily/1`). It checks hourly; the run ids are per
  mission and UTC day, so each runs once a day however often it checks, and a node that was down
  catches up on its first check.
  """

  use GenServer

  alias Cadence.GroundNetworks.PredictedPasses

  @default_interval_ms :timer.hours(1)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @default_interval_ms)
    send(self(), :check)
    {:ok, %{interval_ms: interval}}
  end

  @impl true
  def handle_info(:check, state) do
    :ok = PredictedPasses.daily()
    Process.send_after(self(), :check, state.interval_ms)
    {:noreply, state}
  end
end
