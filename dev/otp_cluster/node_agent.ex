defmodule Cadence.OTPClusterSpike.NodeAgent do
  @moduledoc false
  use GenServer

  alias Cadence.OTPClusterSpike.Owner

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def start_owner(role, key, ready? \\ false),
    do: GenServer.call(__MODULE__, {:start_owner, role, key, ready?})

  @impl true
  def init([]) do
    :ok = :pg.join(Cadence.OTPClusterSpike.Groups, :execution, self())
    {:ok, %{}}
  end

  @impl true
  def handle_call({:start_owner, role, key, ready?}, _from, state) do
    pool =
      case role do
        :partition -> Cadence.OTPClusterSpike.Partitions
        :control -> Cadence.OTPClusterSpike.Controllers
      end

    result = DynamicSupervisor.start_child(pool, {Owner, key: key, ready?: ready?})
    {:reply, result, state}
  end
end
