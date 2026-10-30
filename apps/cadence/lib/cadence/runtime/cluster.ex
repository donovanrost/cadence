defmodule Cadence.Runtime.Cluster do
  @moduledoc """
  Opt-in BEAM placement. Global names identify runtime processes; `:pg` advertises
  execution agents. Membership is eligibility, never a durable ownership lease.
  """
  alias Cadence.Runtime.{ClusterRegistry, ProcessNamespace}

  def config(%ProcessNamespace{registry: registry}) do
    case Registry.meta(registry, :cluster) do
      {:ok, config} -> config || nil
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def via(namespace, key) do
    case config(namespace) do
      nil -> ProcessNamespace.via(namespace, key)
      config -> {:via, ClusterRegistry, {Keyword.fetch!(config, :id), namespace.registry, key}}
    end
  end

  def lookup(namespace, key) do
    case config(namespace) do
      nil ->
        Registry.lookup(namespace.registry, key)

      config ->
        case :global.whereis_name(
               {__MODULE__, Keyword.fetch!(config, :id), namespace.registry, key}
             ) do
          :undefined -> []
          pid -> [{pid, nil}]
        end
    end
  end

  def select(namespace, specification) do
    case config(namespace) do
      nil ->
        Registry.select(namespace.registry, specification)

      config ->
        id = Keyword.fetch!(config, :id)
        registry = namespace.registry

        entries =
          for {__MODULE__, ^id, ^registry, key} = name <- :global.registered_names(),
              pid = :global.whereis_name(name),
              is_pid(pid),
              do: {key, pid, nil}

        :ets.match_spec_run(entries, :ets.match_spec_compile(specification))
    end
  end

  def start_partition(namespace, key, child) do
    config = config(namespace)

    agents =
      :pg.get_members(
        Keyword.fetch!(config, :scope),
        {__MODULE__, Keyword.fetch!(config, :id), namespace.registry}
      )

    # Rendezvous hashing keeps placement stable as membership changes. Existing
    # owners are always resolved before this path; joins do not move live work.
    case Enum.max_by(agents, &{:erlang.phash2({key, node(&1)}), node(&1)}, fn -> nil end) do
      nil ->
        {:error, :no_execution_nodes}

      agent ->
        GenServer.call(agent, {:start_partition, child}, :infinity)
    end
  catch
    :exit, reason -> {:error, {:placement_unavailable, reason}}
  end
end
