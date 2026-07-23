defmodule Cadence.Control.MissionRecovery do
  @moduledoc false

  use GenServer

  alias Cadence.Control.Activations
  alias Cadence.Control.Missions

  @default_interval_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    {:ok, %{interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms)},
     {:continue, :recover}}
  end

  @impl true
  def handle_continue(:recover, state) do
    recover_active_missions()
    {:noreply, schedule(state)}
  end

  @impl true
  def handle_info(:recover, state) do
    recover_active_missions()
    {:noreply, schedule(state)}
  end

  defp recover_active_missions do
    if Process.whereis(Cadence.Repo) do
      Activations.list_active_bases()
      |> Enum.each(fn activation ->
        _ = Missions.ensure_started(activation.mission_id)
      end)
    end

    :ok
  rescue
    _error in [DBConnection.ConnectionError, DBConnection.OwnershipError] -> :ok
  catch
    :exit, _reason -> :ok
  end

  defp schedule(state) do
    Process.send_after(self(), :recover, state.interval_ms)
    state
  end
end
