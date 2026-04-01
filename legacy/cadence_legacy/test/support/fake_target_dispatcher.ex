defmodule Cadence.TestSupport.FakeTargetDispatcher do
  @moduledoc false

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    target_id = Keyword.fetch!(opts, :target_id)

    name =
      {:via, Registry, {Cadence.MissionRegistry, {:target_dispatcher, mission_id, target_id}}}

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec count(pid()) :: non_neg_integer()
  def count(pid), do: GenServer.call(pid, :count)

  @impl true
  def init(_opts) do
    {:ok, %{count: 0}}
  end

  @impl true
  def handle_call(:count, _from, state) do
    {:reply, state.count, state}
  end

  @impl true
  def handle_info(:check_queue, state) do
    {:noreply, %{state | count: state.count + 1}}
  end
end
