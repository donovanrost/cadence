defmodule Cadence.Runtime.ClusterRegistry do
  @moduledoc false

  # Keep local Registry entries for node-local lifecycle inspection. The global
  # name is acquired before init/recovery can claim a semantic writer epoch.
  def register_name({id, registry, key}, pid) do
    name = {Cadence.Runtime.Cluster, id, registry, key}

    resolver =
      if match?({:partition_owner, _, _}, key),
        do: &:global.random_notify_name/3,
        else: &:global.random_exit_name/3

    case :global.register_name(name, pid, resolver) do
      :yes ->
        case Registry.register(registry, key, nil) do
          {:ok, _} ->
            :yes

          _ ->
            :global.unregister_name(name)
            :no
        end

      :no ->
        :no
    end
  end

  def unregister_name({id, registry, key}) do
    name = {Cadence.Runtime.Cluster, id, registry, key}
    # A losing process must never remove its successor's registration.
    if :global.whereis_name(name) == self(), do: :global.unregister_name(name)
    Registry.unregister(registry, key)
    :ok
  end

  def whereis_name({id, registry, key}),
    do: :global.whereis_name({Cadence.Runtime.Cluster, id, registry, key})

  def send(name, message) do
    case whereis_name(name) do
      :undefined -> exit({:badarg, {name, message}})
      pid -> Kernel.send(pid, message)
    end
  end
end
