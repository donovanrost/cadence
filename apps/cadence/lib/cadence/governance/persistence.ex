defmodule Cadence.Governance.Persistence do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.Governance.{
    BindingRuleRow,
    BindingSetRow,
    CapabilityInstanceRow,
    GovernedPacketDefinitionRow,
    PacketDefinitionFieldRow
  }

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  def persist_packet_definitions(repo, packet_definitions) do
    Enum.reduce_while(packet_definitions, {:ok, %{}}, fn %PacketDefinition{} = packet_definition,
                                                         {:ok, acc} ->
      case persist_packet_definition(repo, packet_definition) do
        {:ok, %GovernedPacketDefinitionRow{} = row} ->
          {:cont, {:ok, Map.put(acc, packet_definition_key(packet_definition), row)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  def persist_packet_definition(repo, %PacketDefinition{} = packet_definition) do
    changeset = GovernedPacketDefinitionRow.changeset(packet_definition)

    with {:ok, _row} <-
           repo.insert(changeset,
             on_conflict: :nothing,
             conflict_target: [:mission_id, :packet_definition_id, :version]
           ),
         %GovernedPacketDefinitionRow{} = packet_definition_row <-
           repo.get_by!(GovernedPacketDefinitionRow,
             mission_id: packet_definition.mission_id,
             packet_definition_id: packet_definition.packet_definition_id,
             version: packet_definition.version
           ),
         {:ok, _field_rows} <-
           persist_packet_definition_fields(repo, packet_definition_row, packet_definition) do
      {:ok, packet_definition_row}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  def persist_binding_set(repo, %BindingSet{} = binding_set, storage \\ %{}) do
    changeset = BindingSetRow.changeset(binding_set, storage)

    case repo.insert(changeset,
           on_conflict: :nothing,
           conflict_target: [:mission_id, :binding_set_id, :version]
         ) do
      {:ok, _row} ->
        {:ok,
         repo.get_by!(BindingSetRow,
           mission_id: binding_set.mission_id,
           binding_set_id: binding_set.binding_set_id,
           version: binding_set.version
         )}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  The instance and rule rows `persist_capability_instances/3` and `persist_binding_rules/4` would
  insert, built by the same changesets but not inserted (#447 compresses them).
  """
  def binding_rows(%BindingSet{} = binding_set) do
    by_id = Map.new(binding_set.capability_instances, &{&1.capability_instance_id, &1})

    with {:ok, instances} <- map_ok(binding_set.capability_instances, &instance_row/1),
         {:ok, rules} <- map_ok(binding_set.rules, &rule_row(&1, by_id)) do
      {:ok, instances, rules}
    end
  end

  defp instance_row(%CapabilityInstance{} = capability_instance) do
    with {:ok, attrs} <- capability_instance_config_attrs(capability_instance) do
      0 |> CapabilityInstanceRow.changeset(capability_instance, attrs) |> applied()
    end
  end

  defp rule_row(%BindingRule{} = rule, by_id) do
    with {:ok, attrs} <- binding_rule_persistence_attrs(rule, by_id) do
      0 |> BindingRuleRow.changeset(rule, attrs) |> applied()
    end
  end

  defp applied(%Changeset{valid?: true} = changeset),
    do: {:ok, Changeset.apply_changes(changeset)}

  defp applied(%Changeset{} = changeset), do: {:error, changeset}

  defp map_ok(items, fun) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  def persist_capability_instances(
        repo,
        %BindingSetRow{} = binding_set_row,
        capability_instances
      ) do
    Enum.reduce_while(capability_instances, {:ok, []}, fn %CapabilityInstance{} =
                                                            capability_instance,
                                                          {:ok, acc} ->
      with {:ok, capability_config_attrs} <-
             capability_instance_config_attrs(capability_instance),
           changeset <-
             CapabilityInstanceRow.changeset(
               binding_set_row.id,
               capability_instance,
               capability_config_attrs
             ),
           {:ok, %CapabilityInstanceRow{} = capability_instance_row} <-
             repo.insert(changeset,
               on_conflict: :nothing,
               conflict_target: [:binding_set_row_id, :capability_instance_id]
             ) do
        {:cont, {:ok, [capability_instance_row | acc]}}
      else
        {:error, %Changeset{} = changeset} -> {:halt, {:error, changeset}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def persist_binding_rules(
        repo,
        %BindingSetRow{} = binding_set_row,
        rules,
        capability_instances
      ) do
    capability_instances_by_id =
      Map.new(capability_instances, fn %CapabilityInstance{} = capability_instance ->
        {capability_instance.capability_instance_id, capability_instance}
      end)

    Enum.reduce_while(rules, {:ok, []}, fn %BindingRule{} = rule, {:ok, acc} ->
      with {:ok, binding_rule_attrs} <-
             binding_rule_persistence_attrs(rule, capability_instances_by_id),
           changeset <-
             BindingRuleRow.changeset(binding_set_row.id, rule, binding_rule_attrs),
           {:ok, %BindingRuleRow{} = binding_rule_row} <-
             repo.insert(changeset,
               on_conflict: :nothing,
               conflict_target: [:binding_set_row_id, :binding_rule_id]
             ) do
        {:cont, {:ok, [binding_rule_row | acc]}}
      else
        {:error, %Changeset{} = changeset} -> {:halt, {:error, changeset}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp persist_packet_definition_fields(
         repo,
         %GovernedPacketDefinitionRow{} = packet_definition_row,
         %PacketDefinition{} = packet_definition
       ) do
    Enum.reduce_while(packet_definition.fields, {:ok, []}, fn %FieldDefinition{} =
                                                                field_definition,
                                                              {:ok, acc} ->
      changeset = PacketDefinitionFieldRow.changeset(packet_definition_row.id, field_definition)

      case repo.insert(changeset,
             on_conflict: fill_field_identity(),
             conflict_target: [:packet_definition_row_id, :field_id]
           ) do
        {:ok, %PacketDefinitionFieldRow{} = field_row} ->
          {:cont, {:ok, [field_row | acc]}}

        {:error, %Changeset{} = changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
  end

  # DECISIONS #73: a field row written before its identity was persisted gains it when the same
  # packet definition is persisted again; a stored identity is never replaced.
  defp fill_field_identity do
    from(field_row in PacketDefinitionFieldRow,
      update: [
        set: [
          parameter_id: fragment("COALESCE(?, EXCLUDED.parameter_id)", field_row.parameter_id),
          qualified_name:
            fragment("COALESCE(?, EXCLUDED.qualified_name)", field_row.qualified_name)
        ]
      ]
    )
  end

  defp capability_instance_config_attrs(%CapabilityInstance{} = capability_instance) do
    case {CapabilityInstance.capability_config(capability_instance),
          CapabilityInstance.configuration(capability_instance)} do
      {%CapabilityConfig{} = capability_config, _configuration} ->
        {:ok,
         %{
           capability_config_type: Atom.to_string(capability_config.config_type),
           capability_config_document: JsonDocument.encode(capability_config.document)
         }}

      {nil, nil} ->
        {:ok,
         %{
           capability_config_type: "none",
           capability_config_document: %{}
         }}

      {nil, configuration} ->
        {:error, {:unsupported_handler_configuration, configuration}}
    end
  end

  defp binding_rule_persistence_attrs(%BindingRule{} = rule, capability_instances_by_id) do
    case Map.fetch(capability_instances_by_id, BindingRule.capability_instance_id(rule)) do
      {:ok, %CapabilityInstance{} = capability_instance} ->
        {:ok, %{handler_key: Atom.to_string(capability_instance.family_key)}}

      :error ->
        {:error, {:unknown_capability_instance, BindingRule.capability_instance_id(rule)}}
    end
  end

  defp packet_definition_key(%PacketDefinition{} = packet_definition) do
    {packet_definition.mission_id, packet_definition.packet_definition_id,
     packet_definition.version}
  end
end
