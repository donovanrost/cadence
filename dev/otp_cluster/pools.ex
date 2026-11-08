defmodule Cadence.OTPClusterSpike.Pools do
  @moduledoc false
  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init([]) do
    children = [
      {DynamicSupervisor, name: Cadence.OTPClusterSpike.Partitions, strategy: :one_for_one},
      {DynamicSupervisor, name: Cadence.OTPClusterSpike.Controllers, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
