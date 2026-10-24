defmodule Cadence.Runtime.BindingSetIndex do
  @moduledoc """
  Copy-safe representation of an admitted binding set.

  References are local to this immutable value. Governed identities and hashes
  still describe the original binding set. Both configuration fields are kept
  exactly, including explicit capability descriptors and legacy runtime values.
  Selection expands only the instances and ordered rules needed by a partition.
  """
  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Runtime.PartitionKey

  @enforce_keys [:template, :rules, :instances, :configurations]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          template: BindingSet.t(),
          rules: [tuple()],
          instances: [tuple()],
          configurations: map()
        }

  def new(%__MODULE__{} = index), do: index

  def new(%BindingSet{} = bindings) do
    {rules, pool} = Enum.map_reduce(bindings.rules, {%{}, %{}}, &index_rule/2)

    {instances, {_keys, values}} =
      Enum.map_reduce(bindings.capability_instances, pool, &index_instance/2)

    %__MODULE__{
      template: %{bindings | rules: [], capability_instances: []},
      rules: rules,
      instances: instances,
      configurations: values
    }
  end

  def materialize(%BindingSet{} = bindings), do: bindings

  def materialize(%__MODULE__{} = index) do
    expand(index, index.rules, index.instances)
  end

  def select(bindings, %PartitionKey{} = partition) do
    index = new(bindings)

    instances =
      Enum.filter(index.instances, fn {instance, _, _} ->
        instance.target_scope == :mission or
          (partition.affinity == :source_endpoint and
             instance.source_endpoint_ref == partition.value)
      end)

    ids = MapSet.new(instances, fn {instance, _, _} -> instance.capability_instance_id end)

    rules =
      Enum.filter(index.rules, fn {rule, _, _} ->
        partition.affinity == :source_endpoint and
          BindingRule.source_endpoint_ref(rule) in [nil, partition.value] and
          MapSet.member?(ids, BindingRule.capability_instance_id(rule))
      end)

    expand(index, rules, instances)
  end

  defp expand(index, rules, instances) do
    %{
      index.template
      | rules: Enum.map(rules, &expand_rule(&1, index.configurations)),
        capability_instances: Enum.map(instances, &expand_instance(&1, index.configurations))
    }
  end

  defp index_rule(rule, pool) do
    {runtime, pool} = intern(rule.handler_configuration, pool)
    {capability, pool} = intern(rule.capability_config, pool)
    {{%{rule | handler_configuration: nil, capability_config: nil}, runtime, capability}, pool}
  end

  defp index_instance(instance, pool) do
    {runtime, pool} = intern(instance.runtime_configuration, pool)
    {capability, pool} = intern(instance.capability_config, pool)

    {{%{instance | runtime_configuration: nil, capability_config: nil}, runtime, capability},
     pool}
  end

  defp intern(value, {keys, values}) do
    case Map.fetch(keys, value) do
      {:ok, key} ->
        {key, {keys, values}}

      :error ->
        key = map_size(values)
        {key, {Map.put(keys, value, key), Map.put(values, key, value)}}
    end
  end

  defp expand_rule({rule, runtime, capability}, values) do
    %{
      rule
      | handler_configuration: Map.fetch!(values, runtime),
        capability_config: Map.fetch!(values, capability)
    }
  end

  defp expand_instance({instance, runtime, capability}, values) do
    %{
      instance
      | runtime_configuration: Map.fetch!(values, runtime),
        capability_config: Map.fetch!(values, capability)
    }
  end
end
