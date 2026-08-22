defmodule Cadence.Runtime.PartitionOwner.PartitionBuilder do
  @moduledoc false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Capabilities.{Descriptor, ExecutionContext, ExecutionResult}

  alias Cadence.Runtime.{
    ActionExecutor,
    ActivationContext,
    CapabilityRegistry,
    MissionRuntimeSpec,
    PartitionKey,
    ProcessNamespace,
    TimerService
  }

  alias Cadence.Runtime.PartitionOwner.RuntimeRecords

  def build(
        %BindingSet{} = binding_set,
        %MissionRuntimeSpec{} = activation,
        %PartitionKey{} = partition_key,
        clock_mode,
        %DateTime{} = current_time
      ) do
    build(binding_set, activation, partition_key, clock_mode, current_time, [])
  end

  def build(
        %BindingSet{} = binding_set,
        %MissionRuntimeSpec{} = activation,
        %PartitionKey{} = partition_key,
        clock_mode,
        %DateTime{} = current_time,
        opts
      )
      when is_list(opts) do
    process_namespace =
      Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)

    capability_registry = process_namespace.capability_registry

    activation_context =
      ActivationContext.new(%{
        mission_id: activation.mission_id,
        activation_id: activation.activation_id,
        binding_set_id: activation.binding_set_id,
        binding_set_version: activation.binding_set_version,
        partition_key: partition_key,
        metadata: activation.metadata
      })

    with {:ok, {built_capability_instances, built_rules}} <-
           build_runtime_rules(
             binding_set.rules,
             binding_set.capability_instances,
             partition_key,
             activation_context,
             capability_registry
           ) do
      runtime_binding_set =
        %BindingSet{
          binding_set
          | capability_instances: built_capability_instances,
            rules: built_rules
        }

      with {:ok, managed_application_states, timer_service, runtime_records} <-
             initialize_managed_applications(
               runtime_binding_set,
               activation,
               partition_key,
               clock_mode,
               current_time,
               capability_registry
             ) do
        {:ok, runtime_binding_set, managed_application_states, timer_service, runtime_records}
      end
    end
  end

  defp initialize_managed_applications(
         %BindingSet{} = runtime_binding_set,
         %MissionRuntimeSpec{} = activation,
         %PartitionKey{} = partition_key,
         clock_mode,
         %DateTime{} = current_time,
         capability_registry
       ) do
    initialization_context = %{
      activation: activation,
      runtime_binding_set: runtime_binding_set,
      partition_key: partition_key,
      capability_registry: capability_registry
    }

    runtime_binding_set.capability_instances
    |> Enum.reduce_while(
      {:ok, %{}, TimerService.new(mode: clock_mode, current_time: current_time),
       RuntimeRecords.empty()},
      fn %CapabilityInstance{} = capability_instance, reduce_state ->
        reduce_managed_application_initialization(
          capability_instance,
          reduce_state,
          initialization_context
        )
      end
    )
  end

  defp reduce_managed_application_initialization(
         %CapabilityInstance{} = capability_instance,
         {:ok, _acc, timer_service, _runtime_records} = reduce_state,
         %{capability_registry: capability_registry} = initialization_context
       ) do
    case CapabilityRegistry.fetch_descriptor(
           capability_registry,
           capability_instance.family_key
         ) do
      {:ok, %Descriptor{} = descriptor} ->
        maybe_initialize_managed_application_instance(
          descriptor,
          capability_instance,
          reduce_state,
          initialization_context
        )

      {:error, reason} ->
        _ = TimerService.cancel_all(timer_service)
        {:halt, {:error, reason}}
    end
  end

  defp maybe_initialize_managed_application_instance(
         %Descriptor{kind: :managed_application},
         %CapabilityInstance{} = capability_instance,
         {:ok, acc, %TimerService{} = timer_service, runtime_records},
         %{
           activation: %MissionRuntimeSpec{} = activation,
           runtime_binding_set: %BindingSet{} = runtime_binding_set,
           partition_key: %PartitionKey{} = partition_key,
           capability_registry: capability_registry
         }
       ) do
    initialize_managed_application_instance(
      activation,
      runtime_binding_set,
      partition_key,
      capability_instance,
      timer_service,
      acc,
      runtime_records,
      capability_registry
    )
  end

  defp maybe_initialize_managed_application_instance(
         %Descriptor{},
         %CapabilityInstance{},
         {:ok, acc, %TimerService{} = timer_service, runtime_records},
         _initialization_context
       ) do
    {:cont, {:ok, acc, timer_service, runtime_records}}
  end

  defp initialize_managed_application_instance(
         %MissionRuntimeSpec{} = activation,
         %BindingSet{} = runtime_binding_set,
         %PartitionKey{} = partition_key,
         %CapabilityInstance{} = capability_instance,
         %TimerService{} = timer_service,
         acc,
         runtime_records,
         capability_registry
       ) do
    execution_context =
      execution_context(
        activation,
        runtime_binding_set,
        partition_key,
        capability_instance,
        TimerService.current_time(timer_service)
      )

    with {:ok, %ExecutionResult{} = execution_result} <-
           CapabilityRegistry.init_managed_application(
             capability_registry,
             capability_instance.family_key,
             capability_instance.runtime_configuration,
             execution_context
           ),
         {:ok, state_snapshot} <-
           CapabilityRegistry.snapshot_managed_state(
             capability_registry,
             capability_instance.family_key,
             execution_result.state,
             execution_context
           ),
         {:ok, %{timer_service: next_timer_service, timer_events: timer_events}} <-
           execute_managed_application_init_actions(
             execution_result,
             capability_instance,
             timer_service
           ) do
      {:cont,
       {:ok, Map.put(acc, capability_instance.capability_instance_id, execution_result.state),
        next_timer_service,
        RuntimeRecords.merge(
          runtime_records,
          RuntimeRecords.for_execution(
            :initialized,
            capability_instance,
            execution_context,
            execution_result,
            execution_result.action_requests,
            timer_events,
            state_snapshot: state_snapshot
          )
        )}}
    else
      {:error, reason} ->
        _ = TimerService.cancel_all(timer_service)
        {:halt, {:error, {capability_instance.capability_instance_id, reason}}}
    end
  end

  defp execute_managed_application_init_actions(
         %ExecutionResult{} = execution_result,
         %CapabilityInstance{} = capability_instance,
         %TimerService{} = timer_service
       ) do
    ActionExecutor.execute_many(
      execution_result.action_requests,
      capability_instance.capability_instance_id,
      timer_service
    )
  end

  defp build_runtime_rules(
         rules,
         capability_instances,
         %PartitionKey{} = partition_key,
         %ActivationContext{} = activation_context,
         capability_registry
       )
       when is_list(rules) and is_list(capability_instances) do
    with {:ok, runtime_capability_instances} <-
           build_runtime_capability_instances(
             capability_instances,
             partition_key,
             activation_context,
             capability_registry
           ) do
      runtime_capability_instance_ids =
        runtime_capability_instances
        |> Enum.map(& &1.capability_instance_id)
        |> MapSet.new()

      runtime_rules =
        rules
        |> Enum.filter(fn %BindingRule{} = rule ->
          rule_applies_to_partition?(rule, partition_key) and
            MapSet.member?(
              runtime_capability_instance_ids,
              BindingRule.capability_instance_id(rule)
            )
        end)

      {:ok, {runtime_capability_instances, runtime_rules}}
    end
  end

  defp build_runtime_capability_instances(
         capability_instances,
         %PartitionKey{} = partition_key,
         %ActivationContext{} = activation_context,
         capability_registry
       )
       when is_list(capability_instances) do
    Enum.reduce_while(capability_instances, {:ok, []}, fn %CapabilityInstance{} =
                                                            capability_instance,
                                                          {:ok, acc} ->
      reduce_runtime_capability_instance(
        capability_instance,
        acc,
        partition_key,
        activation_context,
        capability_registry
      )
    end)
  end

  defp reduce_runtime_capability_instance(
         %CapabilityInstance{} = capability_instance,
         acc,
         %PartitionKey{} = partition_key,
         %ActivationContext{} = activation_context,
         capability_registry
       ) do
    case build_runtime_capability_instance(
           capability_instance,
           partition_key,
           activation_context,
           capability_registry
         ) do
      {:ok, runtime_capability_instance} ->
        {:cont, {:ok, acc ++ [runtime_capability_instance]}}

      :skip ->
        {:cont, {:ok, acc}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp build_runtime_capability_instance(
         %CapabilityInstance{} = capability_instance,
         %PartitionKey{} = partition_key,
         %ActivationContext{} = activation_context,
         capability_registry
       ) do
    with {:ok, %Descriptor{} = descriptor} <-
           CapabilityRegistry.fetch_descriptor(
             capability_registry,
             capability_instance.family_key
           ),
         :ok <-
           validate_runtime_capability_partition(
             descriptor,
             capability_instance,
             partition_key
           ),
         {:ok, instance_configuration} <-
           build_runtime_capability_instance_configuration(
             capability_instance,
             activation_context,
             capability_registry
           ) do
      {:ok,
       %CapabilityInstance{capability_instance | runtime_configuration: instance_configuration}}
    else
      :skip ->
        :skip

      {:error, {:build_runtime_instance, reason}} ->
        {:error, {capability_instance.family_key, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execution_context(
        %MissionRuntimeSpec{} = activation,
        %BindingSet{} = runtime_binding_set,
        %PartitionKey{} = partition_key,
        %CapabilityInstance{} = capability_instance,
        %DateTime{} = current_time,
        metadata \\ %{}
      ) do
    ExecutionContext.new(%{
      mission_id: activation.mission_id,
      activation_id: activation.activation_id,
      binding_set_id: runtime_binding_set.binding_set_id,
      binding_set_version: runtime_binding_set.version,
      current_time: current_time,
      partition_key: partition_key,
      capability_instance_id: capability_instance.capability_instance_id,
      scope_ref: capability_scope_ref(capability_instance, activation.mission_id, partition_key),
      metadata: metadata
    })
  end

  defp capability_scope_ref(
         %CapabilityInstance{
           target_scope: :source_endpoint,
           source_endpoint_ref: source_endpoint_ref
         },
         _mission_id,
         %PartitionKey{value: partition_value}
       ) do
    source_endpoint_ref || partition_value
  end

  defp capability_scope_ref(
         %CapabilityInstance{target_scope: :mission},
         mission_id,
         %PartitionKey{}
       ),
       do: mission_id

  defp validate_runtime_capability_partition(
         %Descriptor{} = descriptor,
         %CapabilityInstance{} = capability_instance,
         %PartitionKey{} = partition_key
       ) do
    if descriptor.partition_affinity == partition_key.affinity and
         capability_instance_applies_to_partition?(capability_instance, partition_key) do
      :ok
    else
      :skip
    end
  end

  defp build_runtime_capability_instance_configuration(
         %CapabilityInstance{} = capability_instance,
         %ActivationContext{} = activation_context,
         capability_registry
       ) do
    case CapabilityRegistry.build_instance(
           capability_registry,
           capability_instance.family_key,
           capability_instance.runtime_configuration,
           activation_context
         ) do
      {:ok, instance_configuration} ->
        {:ok, instance_configuration}

      {:error, reason} ->
        {:error, {:build_runtime_instance, reason}}
    end
  end

  defp rule_applies_to_partition?(%BindingRule{} = rule, %PartitionKey{
         affinity: :source_endpoint,
         value: partition_value
       }) do
    case BindingRule.source_endpoint_ref(rule) do
      nil -> true
      source_endpoint_ref -> source_endpoint_ref == partition_value
    end
  end

  defp rule_applies_to_partition?(%BindingRule{}, %PartitionKey{}), do: false

  defp capability_instance_applies_to_partition?(
         %CapabilityInstance{target_scope: :mission},
         %PartitionKey{}
       ),
       do: true

  defp capability_instance_applies_to_partition?(
         %CapabilityInstance{
           target_scope: :source_endpoint,
           source_endpoint_ref: source_endpoint_ref
         },
         %PartitionKey{affinity: :source_endpoint, value: partition_value}
       ) do
    source_endpoint_ref == partition_value
  end

  defp capability_instance_applies_to_partition?(%CapabilityInstance{}, %PartitionKey{}),
    do: false

  def snapshot_managed_applications(state) do
    state.runtime_binding_set.capability_instances
    |> Enum.reduce_while({:ok, []}, fn %CapabilityInstance{} = capability_instance, {:ok, acc} ->
      reduce_managed_application_snapshot(capability_instance, acc, state)
    end)
  end

  defp reduce_managed_application_snapshot(
         %CapabilityInstance{} = capability_instance,
         acc,
         state
       ) do
    case snapshot_managed_application(state, capability_instance) do
      {:ok, snapshot} -> {:cont, {:ok, acc ++ [snapshot]}}
      :skip -> {:cont, {:ok, acc}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp snapshot_managed_application(state, %CapabilityInstance{} = capability_instance) do
    with {:ok, %Descriptor{} = descriptor} <-
           CapabilityRegistry.fetch_descriptor(
             state.process_namespace.capability_registry,
             capability_instance.family_key
           ),
         :ok <- ensure_managed_application_descriptor(descriptor),
         {:ok, application_state} <-
           fetch_managed_application_state(state, capability_instance.capability_instance_id),
         {:ok, snapshot_state} <-
           CapabilityRegistry.snapshot_managed_state(
             state.process_namespace.capability_registry,
             capability_instance.family_key,
             application_state,
             snapshot_execution_context(state, capability_instance)
           ) do
      {:ok,
       %{
         capability_instance_id: capability_instance.capability_instance_id,
         family_key: capability_instance.family_key,
         target_scope: capability_instance.target_scope,
         source_endpoint_ref: capability_instance.source_endpoint_ref,
         state: snapshot_state
       }}
    else
      :skip -> :skip
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_managed_application_descriptor(%Descriptor{kind: :managed_application}), do: :ok
  defp ensure_managed_application_descriptor(%Descriptor{}), do: :skip

  defp snapshot_execution_context(state, %CapabilityInstance{} = capability_instance) do
    execution_context(
      state.active_activation,
      state.runtime_binding_set,
      state.partition_key,
      capability_instance,
      TimerService.current_time(state.timer_service)
    )
  end

  defp fetch_managed_application_state(state, capability_instance_id)
       when is_binary(capability_instance_id) do
    case Map.fetch(state.managed_application_states, capability_instance_id) do
      {:ok, application_state} -> {:ok, application_state}
      :error -> {:error, {:managed_application_not_initialized, capability_instance_id}}
    end
  end
end
