defmodule Cadence.Runtime.ClusterSupervisor do
  @moduledoc false
  use Supervisor
  alias Cadence.Runtime.{Cluster, ClusterMembership, ProcessNamespace}

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    namespace = Keyword.fetch!(opts, :process_namespace)
    config = Cluster.config(namespace)
    runtime_opts = Keyword.fetch!(opts, :runtime_opts)
    topologies = Keyword.get(config, :topologies, [])

    discovery =
      if topologies == [],
        do: [],
        else: [
          {Elixir.Cluster.Supervisor,
           [topologies, [name: ProcessNamespace.via(namespace, :discovery)]]}
        ]

    # Discovery and membership failure must not take healthy execution down.
    # Membership itself restarts its agent after pg so that it always rejoins.
    children =
      discovery ++
        [
          {DynamicSupervisor,
           strategy: :one_for_one,
           name: ProcessNamespace.via(namespace, :execution_pool),
           extra_arguments: [runtime_opts]},
          {ClusterMembership, process_namespace: namespace}
        ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
