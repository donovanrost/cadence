defmodule Cadence.TestSupport.FakeLaneRouter do
  @moduledoc false

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec updates(pid()) :: list()
  def updates(pid), do: GenServer.call(pid, :updates)

  @spec set_queue_depths(pid(), map()) :: :ok
  def set_queue_depths(pid, depths), do: GenServer.cast(pid, {:set_depths, depths})

  @impl true
  def init(opts) do
    {:ok,
     %{
       queue_depths: Keyword.get(opts, :queue_depths, %{}),
       updates: [],
       shard_ready: []
     }}
  end

  @impl true
  def handle_call(:queue_depths, _from, state) do
    {:reply, state.queue_depths, state}
  end

  def handle_call(:updates, _from, state) do
    {:reply, state.updates, state}
  end

  @impl true
  def handle_cast({:set_max_inflight, lane, inflight}, state) do
    updates = state.updates ++ [{lane, inflight}]
    {:noreply, %{state | updates: updates}}
  end

  def handle_cast({:shard_ready, lane, shard_id, count}, state) do
    shard_ready = state.shard_ready ++ [{lane, shard_id, count}]
    {:noreply, %{state | shard_ready: shard_ready}}
  end

  def handle_cast({:set_depths, depths}, state) do
    {:noreply, %{state | queue_depths: depths}}
  end
end
