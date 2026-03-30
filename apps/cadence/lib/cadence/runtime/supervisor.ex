defmodule Cadence.Runtime.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Cadence.Runtime.CapabilityRegistry, []},
      {Registry, keys: :unique, name: Cadence.Runtime.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Cadence.Runtime.MissionSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
