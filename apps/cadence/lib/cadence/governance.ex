defmodule Cadence.Governance do
  @moduledoc """
  Persistence boundary for mission-scoped governed configuration artifacts.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance,
    Selector
  }

  alias Cadence.Capabilities.{Registry, ValidationContext}
  alias Cadence.DerivedTelemetry.Definition, as: DerivedTelemetryDefinition

  alias Cadence.Governance.{
    BindingRuleRow,
    BindingSetRow,
    CapabilityInstanceRow,
    GovernedDerivedTelemetryDefinitionRow,
    GovernedPacketDefinitionRow,
    PacketDefinitionFieldRow
  }

  alias Cadence.Missions
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo
  alias Cadence.SourceEndpoints
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  @spec persist_binding_set(binary(), BindingSet.t()) :: {:ok, BindingSet.t()} | {:error, term()}
  def persist_binding_set(organization_id, %BindingSet{} = binding_set)
      when is_binary(organization_id) do
    with {:ok, scoped_binding_set} <- put_binding_set_scope(binding_set, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(
             scoped_binding_set.organization_id,
             scoped_binding_set.mission_id
           ),
         {:ok, _persisted_binding_set} <- persist_binding_set(scoped_binding_set) do
      {:ok, scoped_binding_set}
    end
  end

  @spec persist_binding_set(BindingSet.t()) :: {:ok, BindingSet.t()} | {:error, term()}
  def persist_binding_set(%BindingSet{} = binding_set) do
    with :ok <- validate_binding_set(binding_set),
         {:ok, packet_definitions} <-
           referenced_packet_definitions(binding_set.capability_instances) do
      Multi.new()
      |> Multi.run(:packet_definitions, fn repo, _changes ->
        persist_packet_definitions(repo, packet_definitions)
      end)
      |> Multi.run(:binding_set_row, fn repo, _changes ->
        persist_binding_set_row(repo, binding_set)
      end)
      |> Multi.run(:capability_instance_rows, fn repo, %{binding_set_row: binding_set_row} ->
        persist_capability_instance_rows(repo, binding_set_row, binding_set.capability_instances)
      end)
      |> Multi.run(:binding_rule_rows, fn repo, %{binding_set_row: binding_set_row} ->
        persist_binding_rule_rows(
          repo,
          binding_set_row,
          binding_set.rules,
          binding_set.capability_instances
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, _changes} ->
          {:ok, binding_set}

        {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
          {:error, changeset}

        {:error, _operation, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  @spec persist_packet_definition(PacketDefinition.t()) ::
          {:ok, PacketDefinition.t()} | {:error, term()}
  def persist_packet_definition(%PacketDefinition{} = packet_definition) do
    case persist_packet_definition_row(Repo, packet_definition) do
      {:ok, %GovernedPacketDefinitionRow{}} -> {:ok, packet_definition}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec persist_packet_definition(binary(), PacketDefinition.t()) ::
          {:ok, PacketDefinition.t()} | {:error, term()}
  def persist_packet_definition(organization_id, %PacketDefinition{} = packet_definition)
      when is_binary(organization_id) do
    with {:ok, scoped_packet_definition} <-
           put_packet_definition_scope(packet_definition, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(
             scoped_packet_definition.organization_id,
             scoped_packet_definition.mission_id
           ),
         {:ok, _persisted_packet_definition} <-
           persist_packet_definition(scoped_packet_definition) do
      {:ok, scoped_packet_definition}
    end
  end

  @spec list_packet_definitions(binary()) :: [PacketDefinition.t()]
  def list_packet_definitions(mission_id) when is_binary(mission_id) do
    field_preload_query =
      from(field_row in PacketDefinitionFieldRow,
        order_by: [asc: field_row.offset_bits, asc: field_row.field_id]
      )

    mission_id
    |> latest_definition_rows(GovernedPacketDefinitionRow, :packet_definition_id)
    |> Repo.preload(field_rows: field_preload_query)
    |> Enum.map(&to_packet_definition/1)
    |> Enum.sort_by(&{&1.apid, &1.packet_name})
  end

  @spec list_packet_definitions(binary(), binary()) :: [PacketDefinition.t()]
  def list_packet_definitions(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    field_preload_query =
      from(field_row in PacketDefinitionFieldRow,
        order_by: [asc: field_row.offset_bits, asc: field_row.field_id]
      )

    organization_id
    |> latest_definition_rows(mission_id, GovernedPacketDefinitionRow, :packet_definition_id)
    |> Repo.preload(field_rows: field_preload_query)
    |> Enum.map(&to_packet_definition/1)
    |> Enum.sort_by(&{&1.apid, &1.packet_name})
  end

  @spec fetch_binding_set(binary(), binary(), pos_integer()) ::
          {:ok, BindingSet.t()} | {:error, term()}
  def fetch_binding_set(mission_id, binding_set_id, version)
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 do
    binding_set_row =
      BindingSetRow
      |> where(
        [binding_set_row],
        binding_set_row.mission_id == ^mission_id and
          binding_set_row.binding_set_id == ^binding_set_id and
          binding_set_row.version == ^version
      )
      |> Repo.one()

    case binding_set_row do
      nil -> {:error, :binding_set_not_found}
      %BindingSetRow{} = row -> hydrate_binding_set(row)
    end
  end

  @spec fetch_binding_set(binary(), binary(), binary(), pos_integer()) ::
          {:ok, BindingSet.t()} | {:error, term()}
  def fetch_binding_set(organization_id, mission_id, binding_set_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(binding_set_id) and
             is_integer(version) and version > 0 do
    organization_id
    |> binding_set_row_for_org(mission_id, binding_set_id, version)
    |> hydrate_binding_set_row()
  end

  @spec fetch_latest_binding_set(binary(), binary()) :: {:ok, BindingSet.t()} | {:error, term()}
  def fetch_latest_binding_set(mission_id, binding_set_id)
      when is_binary(mission_id) and is_binary(binding_set_id) do
    binding_set_row =
      BindingSetRow
      |> where(
        [binding_set_row],
        binding_set_row.mission_id == ^mission_id and
          binding_set_row.binding_set_id == ^binding_set_id
      )
      |> order_by([binding_set_row], desc: binding_set_row.version)
      |> limit(1)
      |> Repo.one()

    case binding_set_row do
      nil -> {:error, :binding_set_not_found}
      %BindingSetRow{} = row -> hydrate_binding_set(row)
    end
  end

  @spec fetch_latest_binding_set(binary(), binary(), binary()) ::
          {:ok, BindingSet.t()} | {:error, term()}
  def fetch_latest_binding_set(organization_id, mission_id, binding_set_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(binding_set_id) do
    binding_set_row =
      BindingSetRow
      |> where(
        [binding_set_row],
        binding_set_row.organization_id == ^organization_id and
          binding_set_row.mission_id == ^mission_id and
          binding_set_row.binding_set_id == ^binding_set_id
      )
      |> order_by([binding_set_row], desc: binding_set_row.version)
      |> limit(1)
      |> Repo.one()

    case binding_set_row do
      nil -> {:error, :binding_set_not_found}
      %BindingSetRow{} = row -> hydrate_binding_set(row)
    end
  end

  @spec persist_derived_definition(DerivedTelemetryDefinition.t()) ::
          {:ok, DerivedTelemetryDefinition.t()} | {:error, term()}
  def persist_derived_definition(%DerivedTelemetryDefinition{} = definition) do
    with :ok <- DerivedTelemetryDefinition.validate(definition) do
      changeset = GovernedDerivedTelemetryDefinitionRow.changeset(definition)

      case Repo.insert(changeset,
             on_conflict: :nothing,
             conflict_target: [:mission_id, :derived_definition_id, :version]
           ) do
        {:ok, _row} -> {:ok, definition}
        {:error, %Changeset{} = changeset} -> {:error, changeset}
      end
    end
  end

  @spec list_derived_definitions(binary()) :: [DerivedTelemetryDefinition.t()]
  def list_derived_definitions(mission_id) when is_binary(mission_id) do
    mission_id
    |> latest_definition_rows(GovernedDerivedTelemetryDefinitionRow, :derived_definition_id)
    |> Enum.map(&GovernedDerivedTelemetryDefinitionRow.to_domain/1)
    |> Enum.sort_by(& &1.point_id)
  end

  defp validate_binding_set(
         %BindingSet{
           mission_id: mission_id,
           rules: rules,
           capability_instances: capability_instances
         } = binding_set
       )
       when is_binary(mission_id) and mission_id != "" and is_list(rules) and
              is_list(capability_instances) do
    capability_registry = Registry.default()

    with {:ok, capability_instances_by_id} <-
           validate_capability_instances(capability_instances, mission_id, capability_registry),
         :ok <-
           validate_binding_rules(
             rules,
             mission_id,
             capability_instances_by_id,
             capability_registry
           ) do
      validate_binding_set_instances(binding_set, capability_instances_by_id)
    end
  end

  defp validate_binding_set(%BindingSet{}), do: {:error, :missing_mission_id}

  defp binding_set_row_for_org(organization_id, mission_id, binding_set_id, version) do
    BindingSetRow
    |> where(
      [binding_set_row],
      binding_set_row.organization_id == ^organization_id and
        binding_set_row.mission_id == ^mission_id and
        binding_set_row.binding_set_id == ^binding_set_id and
        binding_set_row.version == ^version
    )
    |> Repo.one()
  end

  defp hydrate_binding_set_row(nil), do: {:error, :binding_set_not_found}
  defp hydrate_binding_set_row(%BindingSetRow{} = row), do: hydrate_binding_set(row)

  defp validate_capability_instances(capability_instances, mission_id, capability_registry)
       when is_list(capability_instances) do
    Enum.reduce_while(capability_instances, {:ok, %{}}, fn
      %CapabilityInstance{} = capability_instance, {:ok, acc} ->
        reduce_capability_instance_validation(
          capability_instance,
          mission_id,
          capability_registry,
          acc
        )
    end)
  end

  defp reduce_capability_instance_validation(
         %CapabilityInstance{} = capability_instance,
         mission_id,
         capability_registry,
         acc
       ) do
    if Map.has_key?(acc, capability_instance.capability_instance_id) do
      {:halt,
       {:error, {:duplicate_capability_instance_id, capability_instance.capability_instance_id}}}
    else
      case validate_capability_instance(capability_instance, mission_id, capability_registry) do
        {:ok, %CapabilityInstance{} = resolved_capability_instance} ->
          {:cont,
           {:ok,
            Map.put(
              acc,
              resolved_capability_instance.capability_instance_id,
              resolved_capability_instance
            )}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end
  end

  defp validate_capability_instance(
         %CapabilityInstance{} = capability_instance,
         mission_id,
         capability_registry
       ) do
    with :ok <- validate_capability_instance_scope(capability_instance, mission_id),
         {:ok, resolved_capability_instance} <-
           resolve_capability_instance_configuration(capability_instance, mission_id),
         true <- is_atom(resolved_capability_instance.family_key),
         validation_context <-
           ValidationContext.new(%{
             mission_id: mission_id,
             target_scope: resolved_capability_instance.target_scope,
             metadata: %{source_endpoint_ref: resolved_capability_instance.source_endpoint_ref}
           }),
         :ok <-
           Registry.validate_capability_instance(
             capability_registry,
             resolved_capability_instance,
             validation_context
           ) do
      {:ok, resolved_capability_instance}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :missing_capability_family}
    end
  end

  defp validate_binding_rules(rules, mission_id, capability_instances_by_id, capability_registry)
       when is_list(rules) and is_map(capability_instances_by_id) do
    Enum.reduce_while(rules, :ok, fn %BindingRule{} = rule, :ok ->
      case validate_binding_rule(
             rule,
             mission_id,
             capability_instances_by_id,
             capability_registry
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_binding_rule(
         %BindingRule{} = binding_rule,
         mission_id,
         capability_instances_by_id,
         capability_registry
       ) do
    with :ok <- validate_binding_rule_scope(binding_rule, mission_id),
         {:ok, resolved_binding_rule, resolved_capability_instance} <-
           resolve_binding_rule(
             binding_rule,
             capability_instances_by_id,
             mission_id
           ) do
      validation_context =
        ValidationContext.new(%{
          mission_id: mission_id,
          target_scope: resolved_capability_instance.target_scope,
          input_stage: binding_rule_input_stage(resolved_binding_rule),
          metadata: %{
            apid: BindingRule.apid(resolved_binding_rule),
            source_endpoint_ref:
              BindingRule.source_endpoint_ref(resolved_binding_rule) ||
                resolved_capability_instance.source_endpoint_ref
          }
        })

      Registry.validate_binding_rule(
        capability_registry,
        resolved_binding_rule,
        validation_context
      )
    end
  end

  defp validate_binding_set_instances(%BindingSet{rules: rules}, capability_instances_by_id)
       when is_map(capability_instances_by_id) do
    Enum.reduce_while(rules, :ok, fn %BindingRule{} = rule, :ok ->
      case Map.fetch(capability_instances_by_id, BindingRule.capability_instance_id(rule)) do
        {:ok, _capability_instance} ->
          {:cont, :ok}

        :error ->
          {:halt,
           {:error, {:unknown_capability_instance, BindingRule.capability_instance_id(rule)}}}
      end
    end)
  end

  defp referenced_packet_definitions(capability_instances) when is_list(capability_instances) do
    capability_instances
    |> Enum.reduce_while({:ok, %{}}, fn
      %CapabilityInstance{} = capability_instance, {:ok, acc} ->
        reduce_referenced_packet_definition(capability_instance, acc)
    end)
    |> case do
      {:ok, packet_definitions_by_key} ->
        {:ok, Map.values(packet_definitions_by_key)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reduce_referenced_packet_definition(%CapabilityInstance{} = capability_instance, acc) do
    case {CapabilityInstance.capability_config(capability_instance),
          CapabilityInstance.configuration(capability_instance)} do
      {%CapabilityConfig{config_type: :none}, _configuration} ->
        {:cont, {:ok, acc}}

      {nil, nil} ->
        {:cont, {:ok, acc}}

      {%CapabilityConfig{config_type: :governed_packet_definition},
       %PacketDefinition{} = packet_definition} ->
        key = packet_definition_key(packet_definition)
        {:cont, {:ok, Map.put_new(acc, key, packet_definition)}}

      {%CapabilityConfig{config_type: :governed_packet_definition}, nil} ->
        {:cont, {:ok, acc}}

      {%CapabilityConfig{config_type: :inline}, _configuration} ->
        {:cont, {:ok, acc}}

      {_capability_config, configuration} ->
        {:halt, {:error, {:unsupported_handler_configuration, configuration}}}
    end
  end

  defp persist_packet_definitions(repo, packet_definitions) do
    Enum.reduce_while(packet_definitions, {:ok, %{}}, fn %PacketDefinition{} = packet_definition,
                                                         {:ok, acc} ->
      case persist_packet_definition_row(repo, packet_definition) do
        {:ok, %GovernedPacketDefinitionRow{} = row} ->
          {:cont, {:ok, Map.put(acc, packet_definition_key(packet_definition), row)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp persist_packet_definition_row(repo, %PacketDefinition{} = packet_definition) do
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
             on_conflict: :nothing,
             conflict_target: [:packet_definition_row_id, :field_id]
           ) do
        {:ok, %PacketDefinitionFieldRow{} = field_row} ->
          {:cont, {:ok, [field_row | acc]}}

        {:error, %Changeset{} = changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
  end

  defp persist_binding_set_row(repo, %BindingSet{} = binding_set) do
    changeset = BindingSetRow.changeset(binding_set)

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

  defp persist_capability_instance_rows(
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

  defp persist_binding_rule_rows(
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

  defp hydrate_binding_set(%BindingSetRow{} = binding_set_row) do
    capability_instance_rows =
      CapabilityInstanceRow
      |> where(
        [capability_instance_row],
        capability_instance_row.binding_set_row_id == ^binding_set_row.id
      )
      |> order_by([capability_instance_row],
        asc: capability_instance_row.capability_instance_id
      )
      |> Repo.all()

    binding_rule_rows =
      BindingRuleRow
      |> where([binding_rule_row], binding_rule_row.binding_set_row_id == ^binding_set_row.id)
      |> order_by([binding_rule_row],
        asc: binding_rule_row.priority,
        asc: binding_rule_row.binding_rule_id
      )
      |> Repo.all()

    with {:ok, packet_definitions_by_key} <-
           fetch_capability_instance_packet_definitions(capability_instance_rows),
         {:ok, capability_instances} <-
           hydrate_capability_instances(capability_instance_rows, packet_definitions_by_key),
         capability_instances_by_id <-
           Map.new(capability_instances, fn %CapabilityInstance{} = capability_instance ->
             {capability_instance.capability_instance_id, capability_instance}
           end),
         {:ok, rules} <- hydrate_binding_rules(binding_rule_rows, capability_instances_by_id) do
      {:ok,
       %BindingSet{
         binding_set_id: binding_set_row.binding_set_id,
         organization_id: binding_set_row.organization_id,
         mission_id: binding_set_row.mission_id,
         version: binding_set_row.version,
         capability_instances: capability_instances,
         rules: rules
       }}
    end
  end

  defp fetch_capability_instance_packet_definitions(capability_instance_rows) do
    packet_definition_refs =
      capability_instance_rows
      |> Enum.reduce([], fn %CapabilityInstanceRow{} = capability_instance_row, acc ->
        case capability_instance_row |> capability_config() |> packet_definition_ref() do
          nil -> acc
          ref -> [ref | acc]
        end
      end)
      |> Enum.uniq()

    if packet_definition_refs == [] do
      {:ok, %{}}
    else
      filter =
        Enum.reduce(packet_definition_refs, dynamic(false), fn {mission_id, packet_definition_id,
                                                                version},
                                                               dynamic_filter ->
          dynamic(
            [packet_definition_row],
            ^dynamic_filter or
              (packet_definition_row.mission_id == ^mission_id and
                 packet_definition_row.packet_definition_id == ^packet_definition_id and
                 packet_definition_row.version == ^version)
          )
        end)

      field_preload_query =
        from(field_row in PacketDefinitionFieldRow,
          order_by: [asc: field_row.offset_bits, asc: field_row.field_id]
        )

      packet_definition_rows =
        GovernedPacketDefinitionRow
        |> where(^filter)
        |> preload(field_rows: ^field_preload_query)
        |> Repo.all()

      packet_definitions_by_key =
        Map.new(packet_definition_rows, fn %GovernedPacketDefinitionRow{} = packet_definition_row ->
          packet_definition = to_packet_definition(packet_definition_row)
          {packet_definition_key(packet_definition), packet_definition}
        end)

      {:ok, packet_definitions_by_key}
    end
  end

  defp hydrate_capability_instances(capability_instance_rows, packet_definitions_by_key) do
    Enum.reduce_while(capability_instance_rows, {:ok, []}, fn %CapabilityInstanceRow{} =
                                                                capability_instance_row,
                                                              {:ok, acc} ->
      case to_capability_instance(capability_instance_row, packet_definitions_by_key) do
        {:ok, %CapabilityInstance{} = capability_instance} ->
          {:cont, {:ok, [capability_instance | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, capability_instances} -> {:ok, Enum.reverse(capability_instances)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp hydrate_binding_rules(binding_rule_rows, capability_instances_by_id) do
    Enum.reduce_while(binding_rule_rows, {:ok, []}, fn %BindingRuleRow{} = binding_rule_row,
                                                       {:ok, acc} ->
      case to_binding_rule(binding_rule_row, capability_instances_by_id) do
        {:ok, %BindingRule{} = binding_rule} ->
          {:cont, {:ok, [binding_rule | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, rules} -> {:ok, Enum.reverse(rules)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_capability_instance(
         %CapabilityInstanceRow{} = capability_instance_row,
         packet_definitions_by_key
       ) do
    capability_config = capability_config(capability_instance_row)

    with {:ok, runtime_configuration} <-
           resolve_capability_configuration(capability_config, packet_definitions_by_key) do
      {:ok,
       CapabilityInstance.new(%{
         capability_instance_id: capability_instance_row.capability_instance_id,
         family_key: capability_instance_row.family_key,
         target_scope: capability_instance_row.target_scope,
         source_endpoint_ref: capability_instance_row.source_endpoint_ref,
         lifecycle_state: capability_instance_row.lifecycle_state,
         capability_config: capability_config,
         runtime_configuration: runtime_configuration
       })}
    end
  end

  defp to_binding_rule(%BindingRuleRow{} = binding_rule_row, capability_instances_by_id) do
    with {:ok, %CapabilityInstance{} = capability_instance} <-
           fetch_capability_instance(
             binding_rule_row.capability_instance_id,
             capability_instances_by_id
           ) do
      {:ok,
       %BindingRule{
         binding_rule_id: binding_rule_row.binding_rule_id,
         capability_instance_id: binding_rule_row.capability_instance_id,
         handler_key: capability_instance.family_key,
         selector: to_selector(binding_rule_row),
         capability_config: capability_instance.capability_config,
         priority: binding_rule_row.priority,
         fanout_mode: String.to_existing_atom(binding_rule_row.fanout_mode),
         handler_configuration: capability_instance.runtime_configuration
       }}
    end
  end

  defp resolve_binding_rule(
         %BindingRule{} = binding_rule,
         capability_instances_by_id,
         mission_id
       ) do
    with {:ok, %CapabilityInstance{} = capability_instance} <-
           fetch_capability_instance(
             BindingRule.capability_instance_id(binding_rule),
             capability_instances_by_id
           ),
         :ok <- validate_binding_rule_instance_scope(binding_rule, capability_instance),
         {:ok, resolved_capability_instance} <-
           resolve_capability_instance_configuration(capability_instance, mission_id) do
      {:ok,
       %BindingRule{
         binding_rule
         | handler_key: resolved_capability_instance.family_key,
           capability_config: resolved_capability_instance.capability_config,
           handler_configuration: resolved_capability_instance.runtime_configuration
       }, resolved_capability_instance}
    end
  end

  defp resolve_capability_instance_configuration(
         %CapabilityInstance{} = capability_instance,
         mission_id
       ) do
    case CapabilityInstance.configuration(capability_instance) do
      nil ->
        with {:ok, runtime_configuration} <-
               load_capability_configuration(
                 CapabilityInstance.capability_config(capability_instance),
                 mission_id
               ) do
          {:ok,
           %CapabilityInstance{capability_instance | runtime_configuration: runtime_configuration}}
        end

      runtime_configuration ->
        {:ok,
         %CapabilityInstance{capability_instance | runtime_configuration: runtime_configuration}}
    end
  end

  defp fetch_capability_instance(capability_instance_id, capability_instances_by_id)
       when is_binary(capability_instance_id) and is_map(capability_instances_by_id) do
    case Map.fetch(capability_instances_by_id, capability_instance_id) do
      {:ok, %CapabilityInstance{} = capability_instance} -> {:ok, capability_instance}
      :error -> {:error, {:unknown_capability_instance, capability_instance_id}}
    end
  end

  defp resolve_capability_configuration(
         %CapabilityConfig{config_type: :none},
         _packet_definitions_by_key
       ) do
    {:ok, nil}
  end

  defp resolve_capability_configuration(
         %CapabilityConfig{config_type: :governed_packet_definition} = capability_config,
         packet_definitions_by_key
       ) do
    ref = packet_definition_ref(capability_config)

    case Map.fetch(packet_definitions_by_key, ref) do
      {:ok, packet_definition} -> {:ok, packet_definition}
      :error -> {:error, {:packet_definition_not_found, ref}}
    end
  end

  defp resolve_capability_configuration(
         %CapabilityConfig{config_type: :inline} = capability_config,
         _packet_definitions_by_key
       ) do
    {:ok, CapabilityConfig.inline_document(capability_config) || %{}}
  end

  defp to_packet_definition(%GovernedPacketDefinitionRow{} = packet_definition_row) do
    fields =
      Enum.map(packet_definition_row.field_rows, fn %PacketDefinitionFieldRow{} = field_row ->
        %FieldDefinition{
          field_id: field_row.field_id,
          name: field_row.name,
          offset_bits: field_row.offset_bits,
          size_bits: field_row.size_bits,
          data_type: String.to_existing_atom(field_row.data_type),
          byte_order: String.to_existing_atom(field_row.byte_order),
          engineering_unit: field_row.engineering_unit
        }
      end)

    %PacketDefinition{
      packet_definition_id: packet_definition_row.packet_definition_id,
      organization_id: packet_definition_row.organization_id,
      mission_id: packet_definition_row.mission_id,
      packet_name: packet_definition_row.packet_name,
      apid: packet_definition_row.apid,
      version: packet_definition_row.version,
      fields: fields
    }
  end

  defp load_capability_configuration(nil, _mission_id), do: {:ok, nil}

  defp load_capability_configuration(%CapabilityConfig{config_type: :none}, _mission_id),
    do: {:ok, nil}

  defp load_capability_configuration(
         %CapabilityConfig{config_type: :governed_packet_definition} = capability_config,
         mission_id
       ) do
    case packet_definition_ref(capability_config) do
      {^mission_id, _packet_definition_id, _version} = ref ->
        fetch_packet_definition(ref)

      {definition_mission_id, _packet_definition_id, _version} ->
        {:error, {:packet_definition_mission_mismatch, definition_mission_id, mission_id}}

      nil ->
        {:error, {:packet_definition_not_found, nil}}
    end
  end

  defp load_capability_configuration(
         %CapabilityConfig{config_type: :inline} = capability_config,
         _mission_id
       ) do
    {:ok, CapabilityConfig.inline_document(capability_config) || %{}}
  end

  defp load_capability_configuration(%CapabilityConfig{} = capability_config, _mission_id) do
    {:error, {:unsupported_capability_config_type, capability_config.config_type}}
  end

  defp capability_config(%CapabilityInstanceRow{} = capability_instance_row) do
    CapabilityConfig.new(%{
      config_type: capability_instance_row.capability_config_type || :none,
      document: capability_instance_row.capability_config_document || %{}
    })
  end

  defp fetch_packet_definition({mission_id, packet_definition_id, version} = ref) do
    field_preload_query =
      from(field_row in PacketDefinitionFieldRow,
        order_by: [asc: field_row.offset_bits, asc: field_row.field_id]
      )

    packet_definition_row =
      GovernedPacketDefinitionRow
      |> where(
        [packet_definition_row],
        packet_definition_row.mission_id == ^mission_id and
          packet_definition_row.packet_definition_id == ^packet_definition_id and
          packet_definition_row.version == ^version
      )
      |> preload(field_rows: ^field_preload_query)
      |> Repo.one()

    case packet_definition_row do
      %GovernedPacketDefinitionRow{} = row -> {:ok, to_packet_definition(row)}
      nil -> {:error, {:packet_definition_not_found, ref}}
    end
  end

  defp packet_definition_ref(%CapabilityConfig{} = capability_config),
    do: CapabilityConfig.packet_definition_ref(capability_config)

  defp packet_definition_key(%PacketDefinition{} = packet_definition) do
    {packet_definition.mission_id, packet_definition.packet_definition_id,
     packet_definition.version}
  end

  defp latest_definition_rows(mission_id, schema, definition_id_field)
       when is_binary(mission_id) and is_atom(definition_id_field) do
    schema
    |> where([definition_row], field(definition_row, :mission_id) == ^mission_id)
    |> order_by([definition_row],
      asc: field(definition_row, ^definition_id_field),
      desc: field(definition_row, :version)
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn definition_row, acc ->
      definition_id = Map.fetch!(definition_row, definition_id_field)
      Map.put_new(acc, definition_id, definition_row)
    end)
    |> Map.values()
  end

  defp latest_definition_rows(organization_id, mission_id, schema, definition_id_field)
       when is_binary(organization_id) and is_binary(mission_id) and
              is_atom(definition_id_field) do
    schema
    |> where(
      [definition_row],
      field(definition_row, :organization_id) == ^organization_id and
        field(definition_row, :mission_id) == ^mission_id
    )
    |> order_by([definition_row],
      asc: field(definition_row, ^definition_id_field),
      desc: field(definition_row, :version)
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn definition_row, acc ->
      definition_id = Map.fetch!(definition_row, definition_id_field)
      Map.put_new(acc, definition_id, definition_row)
    end)
    |> Map.values()
  end

  defp put_binding_set_scope(%BindingSet{} = binding_set, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case binding_set.organization_id do
      nil ->
        {:ok, %BindingSet{binding_set | organization_id: organization_id}}

      ^organization_id ->
        {:ok, binding_set}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          binding_set.mission_id}}
    end
  end

  defp put_packet_definition_scope(%PacketDefinition{} = packet_definition, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case packet_definition.organization_id do
      nil ->
        {:ok, %PacketDefinition{packet_definition | organization_id: organization_id}}

      ^organization_id ->
        {:ok, packet_definition}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          packet_definition.mission_id}}
    end
  end

  defp maybe_to_existing_atom(nil), do: nil
  defp maybe_to_existing_atom(value), do: String.to_existing_atom(value)

  defp binding_rule_input_stage(%BindingRule{} = binding_rule),
    do: BindingRule.packet_kind(binding_rule)

  defp validate_binding_rule_scope(%BindingRule{} = binding_rule, mission_id) do
    case BindingRule.target_scope(binding_rule) do
      :mission ->
        validate_mission_scope(binding_rule)

      :source_endpoint ->
        validate_source_endpoint_scope(binding_rule, mission_id)

      _other ->
        {:error, {:invalid_binding_rule_scope, binding_rule.selector.scope}}
    end
  end

  defp validate_capability_instance_scope(%CapabilityInstance{} = capability_instance, mission_id) do
    case capability_instance.target_scope do
      :mission ->
        if is_nil(capability_instance.source_endpoint_ref) do
          :ok
        else
          {:error,
           {:invalid_capability_instance_scope, capability_instance.capability_instance_id}}
        end

      :source_endpoint ->
        validate_source_endpoint_ref(
          capability_instance.source_endpoint_ref,
          mission_id,
          capability_instance.capability_instance_id
        )

      _other ->
        {:error, {:invalid_capability_instance_scope, capability_instance.capability_instance_id}}
    end
  end

  defp validate_mission_scope(%BindingRule{} = binding_rule) do
    if is_nil(BindingRule.source_endpoint_ref(binding_rule)) do
      :ok
    else
      {:error, {:invalid_binding_rule_scope, binding_rule.selector.scope}}
    end
  end

  defp validate_source_endpoint_scope(%BindingRule{} = binding_rule, mission_id) do
    source_endpoint_ref = BindingRule.source_endpoint_ref(binding_rule)

    if is_binary(source_endpoint_ref) and source_endpoint_ref != "" do
      case SourceEndpoints.fetch_source_endpoint(mission_id, source_endpoint_ref) do
        {:ok, _source_endpoint} ->
          :ok

        {:error, :source_endpoint_not_found} ->
          {:error, {:source_endpoint_not_found, mission_id, source_endpoint_ref}}
      end
    else
      {:error, {:invalid_binding_rule_scope, binding_rule.selector.scope}}
    end
  end

  defp validate_source_endpoint_ref(source_endpoint_ref, mission_id, scope_id) do
    if is_binary(source_endpoint_ref) and source_endpoint_ref != "" do
      case SourceEndpoints.fetch_source_endpoint(mission_id, source_endpoint_ref) do
        {:ok, _source_endpoint} ->
          :ok

        {:error, :source_endpoint_not_found} ->
          {:error, {:source_endpoint_not_found, mission_id, source_endpoint_ref, scope_id}}
      end
    else
      {:error, {:invalid_source_endpoint_scope, scope_id}}
    end
  end

  defp validate_binding_rule_instance_scope(
         %BindingRule{},
         %CapabilityInstance{target_scope: :mission}
       ),
       do: :ok

  defp validate_binding_rule_instance_scope(
         %BindingRule{} = binding_rule,
         %CapabilityInstance{
           target_scope: :source_endpoint,
           source_endpoint_ref: source_endpoint_ref
         }
       ) do
    if BindingRule.source_endpoint_ref(binding_rule) == source_endpoint_ref do
      :ok
    else
      {:error,
       {:binding_rule_scope_mismatch, binding_rule.binding_rule_id, binding_rule.selector.scope,
        source_endpoint_ref}}
    end
  end

  defp to_selector(%BindingRuleRow{} = binding_rule_row) do
    Selector.new(%{
      scope: selector_scope_attrs(binding_rule_row.selector_scope),
      match: selector_match_attrs(binding_rule_row.selector_match)
    })
  end

  defp selector_scope_attrs(selector_scope) when is_map(selector_scope) do
    %{
      target_scope:
        selector_scope
        |> Map.get("target_scope", Map.get(selector_scope, :target_scope))
        |> maybe_to_existing_atom(),
      source_endpoint_ref:
        Map.get(
          selector_scope,
          "source_endpoint_ref",
          Map.get(selector_scope, :source_endpoint_ref)
        )
    }
  end

  defp selector_scope_attrs(_selector_scope), do: %{}

  defp selector_match_attrs(selector_match) when is_map(selector_match) do
    %{
      packet_kind:
        selector_match
        |> Map.get("packet_kind", Map.get(selector_match, :packet_kind))
        |> maybe_to_existing_atom(),
      apid: Map.get(selector_match, "apid", Map.get(selector_match, :apid))
    }
  end

  defp selector_match_attrs(_selector_match), do: %{}
end
