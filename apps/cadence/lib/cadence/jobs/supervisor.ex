defmodule Cadence.Jobs.Supervisor do
  @moduledoc false

  use Supervisor

  alias Cadence.Jobs.Dispatcher

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec quiesce() :: {:ok, map()} | {:error, :noproc}
  def quiesce do
    Dispatcher.quiesce()
  end

  @impl true
  def init(opts) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Cadence.Jobs.WorkerSupervisor},
      {Dispatcher, opts}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
