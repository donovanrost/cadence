defmodule Cadence.Runtime.MissionRuntime do
  @moduledoc false

  use Supervisor

  alias Cadence.Runtime.{PartitionKey, ProcessNamespace}

  def start_link(mission_id) when is_binary(mission_id) do
    start_link([], mission_id)
  end

  def start_link(runtime_opts, mission_id) when is_list(runtime_opts) and is_binary(mission_id) do
    process_namespace = process_namespace(runtime_opts)

    Supervisor.start_link(__MODULE__, {mission_id, runtime_opts},
      name: runtime_name(process_namespace, mission_id)
    )
  end

  @impl true
  def init({mission_id, runtime_opts}) when is_binary(mission_id) and is_list(runtime_opts) do
    process_namespace = process_namespace(runtime_opts)

    children =
      [
        {DynamicSupervisor,
         strategy: :one_for_one,
         name: realized_contact_supervisor_name(process_namespace, mission_id),
         extra_arguments: [runtime_opts]},
        {DynamicSupervisor,
         strategy: :one_for_one,
         name: partition_supervisor_name(process_namespace, mission_id),
         extra_arguments: [runtime_opts]},
        {Cadence.Runtime.MissionCoordinator,
         mission_id: mission_id,
         process_namespace: process_namespace,
         profiler: Keyword.get(runtime_opts, :profiler, Cadence.Telemetry.Profiler)}
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.init(children, strategy: :one_for_all)
  end

  def init(mission_id) when is_binary(mission_id), do: init({mission_id, []})

  @spec runtime_name(binary()) :: {:via, Registry, {module(), term()}}
  def runtime_name(mission_id), do: runtime_name(ProcessNamespace.default(), mission_id)

  @spec runtime_name(ProcessNamespace.t(), binary()) :: {:via, Registry, {atom(), term()}}
  def runtime_name(%ProcessNamespace{} = process_namespace, mission_id),
    do: via(process_namespace, {:mission_runtime, mission_id})

  @spec coordinator_name(binary()) :: {:via, Registry, {module(), term()}}
  def coordinator_name(mission_id), do: coordinator_name(ProcessNamespace.default(), mission_id)

  @spec coordinator_name(ProcessNamespace.t(), binary()) :: {:via, Registry, {atom(), term()}}
  def coordinator_name(%ProcessNamespace{} = process_namespace, mission_id),
    do: via(process_namespace, {:mission_coordinator, mission_id})

  @spec partition_supervisor_name(binary()) :: {:via, Registry, {module(), term()}}
  def partition_supervisor_name(mission_id),
    do: partition_supervisor_name(ProcessNamespace.default(), mission_id)

  @spec partition_supervisor_name(ProcessNamespace.t(), binary()) ::
          {:via, Registry, {atom(), term()}}
  def partition_supervisor_name(%ProcessNamespace{} = process_namespace, mission_id),
    do: via(process_namespace, {:partition_supervisor, mission_id})

  @spec realized_contact_supervisor_name(binary()) :: {:via, Registry, {module(), term()}}
  def realized_contact_supervisor_name(mission_id),
    do: realized_contact_supervisor_name(ProcessNamespace.default(), mission_id)

  @spec realized_contact_supervisor_name(ProcessNamespace.t(), binary()) ::
          {:via, Registry, {atom(), term()}}
  def realized_contact_supervisor_name(%ProcessNamespace{} = process_namespace, mission_id),
    do: via(process_namespace, {:realized_contact_supervisor, mission_id})

  @spec realized_contact_runtime_name(binary(), binary()) :: {:via, Registry, {module(), term()}}
  def realized_contact_runtime_name(mission_id, realized_contact_id) do
    realized_contact_runtime_name(ProcessNamespace.default(), mission_id, realized_contact_id)
  end

  @spec realized_contact_runtime_name(ProcessNamespace.t(), binary(), binary()) ::
          {:via, Registry, {atom(), term()}}
  def realized_contact_runtime_name(process_namespace, mission_id, realized_contact_id) do
    via(process_namespace, {:realized_contact_runtime, mission_id, realized_contact_id})
  end

  @spec realized_contact_coordinator_name(binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def realized_contact_coordinator_name(mission_id, realized_contact_id) do
    realized_contact_coordinator_name(ProcessNamespace.default(), mission_id, realized_contact_id)
  end

  @spec realized_contact_coordinator_name(ProcessNamespace.t(), binary(), binary()) ::
          {:via, Registry, {atom(), term()}}
  def realized_contact_coordinator_name(process_namespace, mission_id, realized_contact_id) do
    via(process_namespace, {:realized_contact_coordinator, mission_id, realized_contact_id})
  end

  @spec realized_contact_quiescence_supervisor_name(binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def realized_contact_quiescence_supervisor_name(mission_id, realized_contact_id) do
    realized_contact_quiescence_supervisor_name(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id
    )
  end

  @spec realized_contact_quiescence_supervisor_name(
          ProcessNamespace.t(),
          binary(),
          binary()
        ) :: {:via, Registry, {atom(), term()}}
  def realized_contact_quiescence_supervisor_name(
        process_namespace,
        mission_id,
        realized_contact_id
      ) do
    via(
      process_namespace,
      {:realized_contact_quiescence_supervisor, mission_id, realized_contact_id}
    )
  end

  @spec downlink_combiner_name(binary(), binary()) :: {:via, Registry, {module(), term()}}
  def downlink_combiner_name(mission_id, realized_contact_id) do
    downlink_combiner_name(ProcessNamespace.default(), mission_id, realized_contact_id)
  end

  @spec downlink_combiner_name(ProcessNamespace.t(), binary(), binary()) ::
          {:via, Registry, {atom(), term()}}
  def downlink_combiner_name(process_namespace, mission_id, realized_contact_id) do
    via(process_namespace, {:downlink_combiner, mission_id, realized_contact_id})
  end

  @spec partition_owner_name(binary(), PartitionKey.t()) ::
          {:via, Registry, {module(), term()}}
  def partition_owner_name(mission_id, %PartitionKey{} = partition_key) do
    partition_owner_name(ProcessNamespace.default(), mission_id, partition_key)
  end

  @spec partition_owner_name(ProcessNamespace.t(), binary(), PartitionKey.t()) ::
          {:via, Registry, {atom(), term()}}
  def partition_owner_name(process_namespace, mission_id, %PartitionKey{} = partition_key) do
    via(
      process_namespace,
      {:partition_owner, mission_id, PartitionKey.registry_key(partition_key)}
    )
  end

  @spec path_supervisor_name(binary(), binary()) :: {:via, Registry, {module(), term()}}
  def path_supervisor_name(mission_id, realized_contact_id) do
    path_supervisor_name(ProcessNamespace.default(), mission_id, realized_contact_id)
  end

  @spec path_supervisor_name(ProcessNamespace.t(), binary(), binary()) ::
          {:via, Registry, {atom(), term()}}
  def path_supervisor_name(process_namespace, mission_id, realized_contact_id) do
    via(process_namespace, {:path_supervisor, mission_id, realized_contact_id})
  end

  @spec path_runtime_name(binary(), binary(), binary()) :: {:via, Registry, {module(), term()}}
  def path_runtime_name(mission_id, realized_contact_id, path_id) do
    path_runtime_name(ProcessNamespace.default(), mission_id, realized_contact_id, path_id)
  end

  @spec path_runtime_name(ProcessNamespace.t(), binary(), binary(), binary()) ::
          {:via, Registry, {atom(), term()}}
  def path_runtime_name(process_namespace, mission_id, realized_contact_id, path_id) do
    via(process_namespace, {:path_runtime, mission_id, realized_contact_id, path_id})
  end

  @spec path_coordinator_name(binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def path_coordinator_name(mission_id, realized_contact_id, path_id) do
    path_coordinator_name(ProcessNamespace.default(), mission_id, realized_contact_id, path_id)
  end

  @spec path_coordinator_name(ProcessNamespace.t(), binary(), binary(), binary()) ::
          {:via, Registry, {atom(), term()}}
  def path_coordinator_name(process_namespace, mission_id, realized_contact_id, path_id) do
    via(process_namespace, {:path_coordinator, mission_id, realized_contact_id, path_id})
  end

  @spec transport_supervisor_name(binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def transport_supervisor_name(mission_id, realized_contact_id, path_id) do
    transport_supervisor_name(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id,
      path_id
    )
  end

  @spec transport_supervisor_name(ProcessNamespace.t(), binary(), binary(), binary()) ::
          {:via, Registry, {atom(), term()}}
  def transport_supervisor_name(process_namespace, mission_id, realized_contact_id, path_id) do
    via(process_namespace, {:transport_supervisor, mission_id, realized_contact_id, path_id})
  end

  @spec provider_supervisor_name(binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def provider_supervisor_name(mission_id, realized_contact_id, path_id) do
    provider_supervisor_name(ProcessNamespace.default(), mission_id, realized_contact_id, path_id)
  end

  @spec provider_supervisor_name(ProcessNamespace.t(), binary(), binary(), binary()) ::
          {:via, Registry, {atom(), term()}}
  def provider_supervisor_name(process_namespace, mission_id, realized_contact_id, path_id) do
    via(process_namespace, {:provider_supervisor, mission_id, realized_contact_id, path_id})
  end

  @spec transport_runtime_name(binary(), binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def transport_runtime_name(mission_id, realized_contact_id, path_id, transport_binding_id) do
    transport_runtime_name(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id,
      path_id,
      transport_binding_id
    )
  end

  @spec transport_runtime_name(ProcessNamespace.t(), binary(), binary(), binary(), binary()) ::
          {:via, Registry, {atom(), term()}}
  def transport_runtime_name(
        process_namespace,
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id
      ) do
    via(
      process_namespace,
      {:transport_runtime, mission_id, realized_contact_id, path_id, transport_binding_id}
    )
  end

  @spec provider_runtime_name(binary(), binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def provider_runtime_name(mission_id, realized_contact_id, path_id, provider_binding_id) do
    provider_runtime_name(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id,
      path_id,
      provider_binding_id
    )
  end

  @spec provider_runtime_name(ProcessNamespace.t(), binary(), binary(), binary(), binary()) ::
          {:via, Registry, {atom(), term()}}
  def provider_runtime_name(
        process_namespace,
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      ) do
    via(
      process_namespace,
      {:provider_runtime, mission_id, realized_contact_id, path_id, provider_binding_id}
    )
  end

  @spec provider_ingress_executor_name(binary(), binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def provider_ingress_executor_name(
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      ) do
    provider_ingress_executor_name(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id,
      path_id,
      provider_binding_id
    )
  end

  @spec provider_ingress_executor_name(
          ProcessNamespace.t(),
          binary(),
          binary(),
          binary(),
          binary()
        ) :: {:via, Registry, {atom(), term()}}
  def provider_ingress_executor_name(
        process_namespace,
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      ) do
    via(
      process_namespace,
      {:provider_ingress_executor, mission_id, realized_contact_id, path_id, provider_binding_id}
    )
  end

  @spec provider_ingress_journal_name(binary(), binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def provider_ingress_journal_name(
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      ) do
    provider_ingress_journal_name(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id,
      path_id,
      provider_binding_id
    )
  end

  @spec provider_ingress_journal_name(
          ProcessNamespace.t(),
          binary(),
          binary(),
          binary(),
          binary()
        ) :: {:via, Registry, {atom(), term()}}
  def provider_ingress_journal_name(
        process_namespace,
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      ) do
    via(
      process_namespace,
      {:provider_ingress_journal, mission_id, realized_contact_id, path_id, provider_binding_id}
    )
  end

  @spec provider_ingress_journal_consumer_name(binary(), binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def provider_ingress_journal_consumer_name(
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      ) do
    provider_ingress_journal_consumer_name(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id,
      path_id,
      provider_binding_id
    )
  end

  @spec provider_ingress_journal_consumer_name(
          ProcessNamespace.t(),
          binary(),
          binary(),
          binary(),
          binary()
        ) :: {:via, Registry, {atom(), term()}}
  def provider_ingress_journal_consumer_name(
        process_namespace,
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      ) do
    via(
      process_namespace,
      {:provider_ingress_journal_consumer, mission_id, realized_contact_id, path_id,
       provider_binding_id}
    )
  end

  @spec provider_ingress_archive_consumer_name(binary(), binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def provider_ingress_archive_consumer_name(
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      ) do
    provider_ingress_archive_consumer_name(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id,
      path_id,
      provider_binding_id
    )
  end

  @spec provider_ingress_archive_consumer_name(
          ProcessNamespace.t(),
          binary(),
          binary(),
          binary(),
          binary()
        ) :: {:via, Registry, {atom(), term()}}
  def provider_ingress_archive_consumer_name(
        process_namespace,
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      ) do
    via(
      process_namespace,
      {:provider_ingress_archive_consumer, mission_id, realized_contact_id, path_id,
       provider_binding_id}
    )
  end

  @spec provider_persistence_projector_name(binary(), binary(), binary(), binary()) ::
          {:via, Registry, {module(), term()}}
  def provider_persistence_projector_name(
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      ) do
    provider_persistence_projector_name(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id,
      path_id,
      provider_binding_id
    )
  end

  @spec provider_persistence_projector_name(
          ProcessNamespace.t(),
          binary(),
          binary(),
          binary(),
          binary()
        ) :: {:via, Registry, {atom(), term()}}
  def provider_persistence_projector_name(
        process_namespace,
        mission_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      ) do
    via(
      process_namespace,
      {:provider_persistence_projector, mission_id, realized_contact_id, path_id,
       provider_binding_id}
    )
  end

  defp process_namespace(runtime_opts) do
    Keyword.get_lazy(runtime_opts, :process_namespace, &ProcessNamespace.default/0)
  end

  defp via(%ProcessNamespace{} = process_namespace, key),
    do: ProcessNamespace.via(process_namespace, key)
end
