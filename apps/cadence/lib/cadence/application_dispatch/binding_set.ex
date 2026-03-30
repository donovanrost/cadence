defmodule Cadence.ApplicationDispatch.BindingSet do
  @moduledoc """
  Versioned collection of application dispatch rules.
  """

  alias Cadence.ApplicationDispatch.{BindingRule, CapabilityInstance}
  alias Cadence.Ids

  @type t :: %__MODULE__{
          binding_set_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          version: pos_integer(),
          capability_instances: [CapabilityInstance.t()],
          rules: [BindingRule.t()]
        }

  defstruct [
    :binding_set_id,
    :organization_id,
    :mission_id,
    :version,
    capability_instances: [],
    rules: []
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    rules =
      attrs
      |> Map.get(:rules, [])
      |> Enum.map(fn
        %BindingRule{} = rule -> rule
        rule_attrs -> BindingRule.new(rule_attrs)
      end)

    explicit_capability_instances =
      attrs
      |> Map.get(:capability_instances, [])
      |> Enum.map(fn
        %CapabilityInstance{} = capability_instance -> capability_instance
        capability_instance_attrs -> CapabilityInstance.new(capability_instance_attrs)
      end)

    {rules, implicit_capability_instances} =
      infer_legacy_capability_instances(rules, explicit_capability_instances)

    %__MODULE__{
      binding_set_id: Map.get(attrs, :binding_set_id, Ids.new("binding_set")),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      version: Map.get(attrs, :version, 1),
      capability_instances: explicit_capability_instances ++ implicit_capability_instances,
      rules: rules
    }
  end

  @spec fetch_capability_instance(t(), binary()) :: {:ok, CapabilityInstance.t()} | :error
  def fetch_capability_instance(
        %__MODULE__{capability_instances: capability_instances},
        capability_instance_id
      )
      when is_binary(capability_instance_id) do
    capability_instances
    |> Enum.find(&(&1.capability_instance_id == capability_instance_id))
    |> case do
      %CapabilityInstance{} = capability_instance -> {:ok, capability_instance}
      nil -> :error
    end
  end

  defp infer_legacy_capability_instances(rules, explicit_capability_instances) do
    existing_ids =
      explicit_capability_instances
      |> Enum.map(& &1.capability_instance_id)
      |> MapSet.new()

    Enum.map_reduce(rules, {existing_ids, []}, fn %BindingRule{} = rule, {seen_ids, acc} ->
      case BindingRule.capability_instance_id(rule) do
        capability_instance_id
        when is_binary(capability_instance_id) and capability_instance_id != "" ->
          {rule, {MapSet.put(seen_ids, capability_instance_id), acc}}

        _missing_capability_instance_id ->
          capability_instance_id = rule.binding_rule_id <> "_instance"

          capability_instance =
            CapabilityInstance.new(%{
              capability_instance_id: capability_instance_id,
              family_key: rule.handler_key,
              target_scope: BindingRule.target_scope(rule),
              source_endpoint_ref: BindingRule.source_endpoint_ref(rule),
              capability_config: BindingRule.capability_config(rule),
              runtime_configuration: BindingRule.configuration(rule)
            })

          updated_rule = %BindingRule{rule | capability_instance_id: capability_instance_id}

          if MapSet.member?(seen_ids, capability_instance_id) do
            {updated_rule, {seen_ids, acc}}
          else
            {updated_rule,
             {MapSet.put(seen_ids, capability_instance_id), acc ++ [capability_instance]}}
          end
      end
    end)
    |> then(fn {updated_rules, {_seen_ids, implicit_capability_instances}} ->
      {updated_rules, implicit_capability_instances}
    end)
  end
end
