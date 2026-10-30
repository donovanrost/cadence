defmodule Cadence.Runtime.ExecutionAgent do
  @moduledoc false
  use GenServer
  alias Cadence.Platform.Drain
  alias Cadence.Runtime.{Cluster, ProcessNamespace}

  def start_link(opts) do
    namespace = Keyword.fetch!(opts, :process_namespace)

    GenServer.start_link(__MODULE__, opts,
      name: ProcessNamespace.via(namespace, :execution_agent)
    )
  end

  def withdraw(namespace) do
    case GenServer.whereis(ProcessNamespace.via(namespace, :execution_agent)) do
      nil -> :ok
      agent -> GenServer.call(agent, :withdraw)
    end
  end

  defp group(namespace, config),
    do: {Cluster, Keyword.fetch!(config, :id), namespace.registry}

  @impl true
  def init(opts) do
    namespace = Keyword.fetch!(opts, :process_namespace)
    config = Cluster.config(namespace)

    if Keyword.get(config, :execution?, true) and not Drain.draining?() do
      :ok = :pg.join(Keyword.fetch!(config, :scope), group(namespace, config), self())
    end

    {:ok, namespace}
  end

  @impl true
  def handle_call(:withdraw, _from, namespace) do
    config = Cluster.config(namespace)
    :pg.leave(Keyword.fetch!(config, :scope), group(namespace, config), self())
    {:reply, :ok, namespace}
  end

  @impl true
  def handle_call({:start_partition, child}, _from, namespace) do
    reply =
      if Drain.draining?() or
           not Keyword.get(Cluster.config(namespace), :execution?, true),
         do: {:error, :cadence_draining},
         else:
           DynamicSupervisor.start_child(ProcessNamespace.via(namespace, :execution_pool), child)

    {:reply, reply, namespace}
  end
end
