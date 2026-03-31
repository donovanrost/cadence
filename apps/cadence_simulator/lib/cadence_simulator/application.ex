defmodule CadenceSimulator.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: CadenceSimulator.RuntimeSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: CadenceSimulator.Supervisor)
  end
end
