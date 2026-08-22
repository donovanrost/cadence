defmodule Cadence.TestSupport.FakeUplinkDispatcher do
  @moduledoc false

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    name = {:via, Registry, {Cadence.MissionRegistry, {:uplink_dispatcher, mission_id}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    {:ok, %{connected?: Keyword.get(opts, :connected?, true)}}
  end

  @impl true
  def handle_call({:connected?, _target_id}, _from, state) do
    {:reply, state.connected?, state}
  end
end
