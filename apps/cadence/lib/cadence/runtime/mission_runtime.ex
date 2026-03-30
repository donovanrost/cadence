defmodule Cadence.Runtime.MissionRuntime do
  @moduledoc false

  use Supervisor

  alias Cadence.Runtime.PartitionKey

  def start_link(mission_id) when is_binary(mission_id) do
    Supervisor.start_link(__MODULE__, mission_id, name: runtime_name(mission_id))
  end

  @impl true
  def init(mission_id) when is_binary(mission_id) do
    children = [
      {DynamicSupervisor,
       strategy: :one_for_one, name: realized_contact_supervisor_name(mission_id)},
      {DynamicSupervisor, strategy: :one_for_one, name: partition_supervisor_name(mission_id)},
      {Cadence.Runtime.MissionCoordinator, mission_id: mission_id}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @spec runtime_name(binary()) :: {:via, Registry, {module(), term()}}
  def runtime_name(mission_id),
    do: {:via, Registry, {Cadence.Runtime.Registry, {:mission_runtime, mission_id}}}

  @spec coordinator_name(binary()) :: {:via, Registry, {module(), term()}}
  def coordinator_name(mission_id),
    do: {:via, Registry, {Cadence.Runtime.Registry, {:mission_coordinator, mission_id}}}

  @spec partition_supervisor_name(binary()) :: {:via, Registry, {module(), term()}}
  def partition_supervisor_name(mission_id),
    do: {:via, Registry, {Cadence.Runtime.Registry, {:partition_supervisor, mission_id}}}

  @spec realized_contact_supervisor_name(binary()) :: {:via, Registry, {module(), term()}}
  def realized_contact_supervisor_name(mission_id),
    do: {:via, Registry, {Cadence.Runtime.Registry, {:realized_contact_supervisor, mission_id}}}

  @spec realized_contact_runtime_name(binary(), binary()) :: {:via, Registry, {module(), term()}}
  def realized_contact_runtime_name(mission_id, realized_contact_id) do
    {:via, Registry,
     {Cadence.Runtime.Registry, {:realized_contact_runtime, mission_id, realized_contact_id}}}
  end

  @spec realized_contact_coordinator_name(binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def realized_contact_coordinator_name(mission_id, realized_contact_id) do
    {:via, Registry,
     {Cadence.Runtime.Registry, {:realized_contact_coordinator, mission_id, realized_contact_id}}}
  end

  @spec downlink_combiner_name(binary(), binary()) :: {:via, Registry, {module(), term()}}
  def downlink_combiner_name(mission_id, realized_contact_id) do
    {:via, Registry,
     {Cadence.Runtime.Registry, {:downlink_combiner, mission_id, realized_contact_id}}}
  end

  @spec partition_owner_name(binary(), PartitionKey.t()) ::
          {:via, Registry, {module(), term()}}
  def partition_owner_name(mission_id, %PartitionKey{} = partition_key) do
    {:via, Registry,
     {Cadence.Runtime.Registry,
      {:partition_owner, mission_id, PartitionKey.registry_key(partition_key)}}}
  end

  @spec path_supervisor_name(binary(), binary()) :: {:via, Registry, {module(), term()}}
  def path_supervisor_name(mission_id, realized_contact_id) do
    {:via, Registry,
     {Cadence.Runtime.Registry, {:path_supervisor, mission_id, realized_contact_id}}}
  end

  @spec path_runtime_name(binary(), binary(), binary()) :: {:via, Registry, {module(), term()}}
  def path_runtime_name(mission_id, realized_contact_id, path_id) do
    {:via, Registry,
     {Cadence.Runtime.Registry, {:path_runtime, mission_id, realized_contact_id, path_id}}}
  end

  @spec path_coordinator_name(binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def path_coordinator_name(mission_id, realized_contact_id, path_id) do
    {:via, Registry,
     {Cadence.Runtime.Registry, {:path_coordinator, mission_id, realized_contact_id, path_id}}}
  end

  @spec transport_supervisor_name(binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def transport_supervisor_name(mission_id, realized_contact_id, path_id) do
    {:via, Registry,
     {Cadence.Runtime.Registry, {:transport_supervisor, mission_id, realized_contact_id, path_id}}}
  end

  @spec provider_supervisor_name(binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def provider_supervisor_name(mission_id, realized_contact_id, path_id) do
    {:via, Registry,
     {Cadence.Runtime.Registry, {:provider_supervisor, mission_id, realized_contact_id, path_id}}}
  end

  @spec transport_runtime_name(binary(), binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def transport_runtime_name(mission_id, realized_contact_id, path_id, transport_binding_id) do
    {:via, Registry,
     {Cadence.Runtime.Registry,
      {:transport_runtime, mission_id, realized_contact_id, path_id, transport_binding_id}}}
  end

  @spec provider_runtime_name(binary(), binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def provider_runtime_name(mission_id, realized_contact_id, path_id, provider_binding_id) do
    {:via, Registry,
     {Cadence.Runtime.Registry,
      {:provider_runtime, mission_id, realized_contact_id, path_id, provider_binding_id}}}
  end

  @spec provider_ingress_executor_name(binary(), binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def provider_ingress_executor_name(
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      ) do
    {:via, Registry,
     {Cadence.Runtime.Registry,
      {:provider_ingress_executor, mission_id, realized_contact_id, path_id, provider_binding_id}}}
  end

  @spec provider_persistence_projector_name(binary(), binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def provider_persistence_projector_name(
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      ) do
    {:via, Registry,
     {Cadence.Runtime.Registry,
      {:provider_persistence_projector, mission_id, realized_contact_id, path_id,
       provider_binding_id}}}
  end
end
