defmodule Cadence.ApplicationDispatch.BindingSet do
  @moduledoc """
  Versioned collection of application dispatch rules.
  """

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    CapabilityConfig,
    CapabilityInstance,
    Selector,
    SelectorMatch,
    SelectorScope
  }

  alias Cadence.Ids
  alias Cadence.Platform.ContentBasis
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  @basis_version 1
  @basis_fields %{
    __MODULE__ => [
      :binding_set_id,
      :organization_id,
      :mission_id,
      :version,
      :capability_instances,
      :rules
    ],
    BindingRule => [
      :binding_rule_id,
      :capability_instance_id,
      :handler_key,
      :selector,
      :capability_config,
      :priority,
      :fanout_mode,
      :handler_configuration
    ],
    CapabilityInstance => [
      :capability_instance_id,
      :family_key,
      :target_scope,
      :source_endpoint_ref,
      :capability_config,
      :lifecycle_state,
      :runtime_configuration
    ],
    CapabilityConfig => [:config_type, :document],
    Selector => [:match, :scope],
    SelectorScope => [:source_endpoint_ref, :target_scope],
    SelectorMatch => [:apid, :packet_kind],
    PacketDefinition => [
      :apid,
      :fields,
      :mission_id,
      :organization_id,
      :packet_definition_id,
      :packet_name,
      :version
    ],
    FieldDefinition => [
      :byte_order,
      :data_type,
      :engineering_unit,
      :field_id,
      :name,
      :offset_bits,
      :size_bits
    ]
  }

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

  @doc """
  The binding set's content hash: what an activation request approves, an activation records, and
  the runtime spec verifies against the stored binding set.

  A telemetry field's `parameter_id` and `qualified_name` are left out (DECISIONS #73). They are
  the mission-model plan's semantic identity, which the runtime basis hash already covers through
  the mission model's content hash. Before 11-14 they weren't persisted, so every stored hash was
  computed without them; leaving them out keeps an in-memory set hashing like its read-back.
  This named v1 basis replaces the earlier whole-struct hash (#166); dev stacks must be reseeded.
  """
  @spec content_sha256(t()) :: binary()
  def content_sha256(%__MODULE__{} = binding_set) do
    binding_set
    |> basis_value()
    |> Map.to_list()
    |> then(&ContentBasis.digest("binding_set", @basis_version, &1))
  end

  @doc false
  def basis_struct_fields, do: @basis_fields

  defp basis_value(%module{} = value) do
    fields = Map.fetch!(@basis_fields, module)
    value |> ContentBasis.project(fields) |> basis_value()
  end

  defp basis_value(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, basis_value(value)} end)

  defp basis_value(list) when is_list(list), do: Enum.map(list, &basis_value/1)

  defp basis_value(other), do: other

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
          maybe_add_implicit_capability_instance(updated_rule, capability_instance, seen_ids, acc)
      end
    end)
    |> then(fn {updated_rules, {_seen_ids, implicit_capability_instances}} ->
      {updated_rules, implicit_capability_instances}
    end)
  end

  defp maybe_add_implicit_capability_instance(
         %BindingRule{} = updated_rule,
         %CapabilityInstance{} = capability_instance,
         seen_ids,
         acc
       ) do
    capability_instance_id = capability_instance.capability_instance_id

    if MapSet.member?(seen_ids, capability_instance_id) do
      {updated_rule, {seen_ids, acc}}
    else
      {updated_rule, {MapSet.put(seen_ids, capability_instance_id), acc ++ [capability_instance]}}
    end
  end
end
