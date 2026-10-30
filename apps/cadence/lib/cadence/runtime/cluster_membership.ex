defmodule Cadence.Runtime.ClusterMembership do
  @moduledoc false
  use Supervisor
  alias Cadence.Runtime.{Cluster, ExecutionAgent}

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    namespace = Keyword.fetch!(opts, :process_namespace)
    config = Cluster.config(namespace)

    children = [
      %{id: :membership, start: {:pg, :start_link, [Keyword.fetch!(config, :scope)]}},
      {ExecutionAgent, process_namespace: namespace}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
