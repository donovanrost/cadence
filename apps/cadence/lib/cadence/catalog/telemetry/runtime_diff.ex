defmodule Cadence.Catalog.Telemetry.RuntimeDiff do
  @moduledoc """
  Compares runtime artifacts freshly recompiled from a canonical telemetry
  snapshot against the governed runtime artifacts currently stored for that
  import basis.
  """

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.Catalog.Telemetry.RuntimeArtifacts
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  @type diff_section :: %{
          compared_count: non_neg_integer(),
          matching_count: non_neg_integer(),
          mismatches: [map()],
          missing_existing: [map()],
          extra_existing: [map()]
        }

  @type report :: %{
          snapshot_id: binary(),
          import_run_id: binary(),
          compiler_diagnostics: [Cadence.Catalog.Diagnostic.t()],
          compiler_summary: map(),
          expected_binding_set: map(),
          existing_binding_set: map() | nil,
          packet_definitions: diff_section(),
          capability_instances: diff_section(),
          binding_rules: diff_section()
        }

  @spec diff(RuntimeArtifacts.t(), BindingSet.t() | nil) :: report()
  def diff(
        %{
          snapshot: snapshot,
          compiler_result: compiler_result,
          binding_set: compiled_binding_set
        },
        existing_binding_set
      )
      when is_nil(existing_binding_set) or is_struct(existing_binding_set, BindingSet) do
    compiled_packet_definitions =
      compiled_binding_set.capability_instances
      |> Enum.map(&CapabilityInstance.configuration/1)
      |> Enum.filter(&match?(%PacketDefinition{}, &1))

    existing_packet_definitions =
      case existing_binding_set do
        %BindingSet{} = binding_set ->
          binding_set.capability_instances
          |> Enum.map(&CapabilityInstance.configuration/1)
          |> Enum.filter(&match?(%PacketDefinition{}, &1))

        nil ->
          []
      end

    %{
      snapshot_id: snapshot.snapshot_id,
      import_run_id: snapshot.import_run_id,
      compiler_diagnostics: compiler_result.diagnostics,
      compiler_summary: %{
        packet_definition_count: length(compiler_result.packet_definitions),
        selector_input_count: length(compiler_result.selector_inputs),
        diagnostic_count: length(compiler_result.diagnostics)
      },
      expected_binding_set: binding_set_summary(compiled_binding_set),
      existing_binding_set: existing_binding_set && binding_set_summary(existing_binding_set),
      packet_definitions:
        diff_by_id(
          compiled_packet_definitions,
          existing_packet_definitions,
          & &1.packet_definition_id,
          &normalize_packet_definition/1
        ),
      capability_instances:
        diff_by_id(
          compiled_binding_set.capability_instances,
          (existing_binding_set && existing_binding_set.capability_instances) || [],
          & &1.capability_instance_id,
          &normalize_capability_instance/1
        ),
      binding_rules:
        diff_by_id(
          compiled_binding_set.rules,
          (existing_binding_set && existing_binding_set.rules) || [],
          & &1.binding_rule_id,
          &normalize_binding_rule/1
        )
    }
  end

  defp diff_by_id(compiled_items, existing_items, id_fun, normalize_fun) do
    compiled_by_id = Map.new(compiled_items, fn item -> {id_fun.(item), item} end)
    existing_by_id = Map.new(existing_items, fn item -> {id_fun.(item), item} end)

    compiled_ids = Map.keys(compiled_by_id) |> Enum.sort()
    existing_ids = Map.keys(existing_by_id) |> Enum.sort()

    {matching_count, mismatches, missing_existing} =
      Enum.reduce(compiled_ids, {0, [], []}, fn id,
                                                {matching_count, mismatches, missing_existing} ->
        compiled_item = Map.fetch!(compiled_by_id, id)

        case Map.get(existing_by_id, id) do
          nil ->
            {matching_count, mismatches, [normalize_fun.(compiled_item) | missing_existing]}

          existing_item ->
            compiled_normalized = normalize_fun.(compiled_item)
            existing_normalized = normalize_fun.(existing_item)

            if compiled_normalized == existing_normalized do
              {matching_count + 1, mismatches, missing_existing}
            else
              {matching_count,
               [
                 %{id: id, compiled: compiled_normalized, existing: existing_normalized}
                 | mismatches
               ], missing_existing}
            end
        end
      end)

    extra_existing =
      existing_ids
      |> Enum.reject(&Map.has_key?(compiled_by_id, &1))
      |> Enum.map(fn id -> existing_by_id |> Map.fetch!(id) |> normalize_fun.() end)

    %{
      compared_count: length(compiled_items),
      matching_count: matching_count,
      mismatches: Enum.reverse(mismatches),
      missing_existing: Enum.reverse(missing_existing),
      extra_existing: extra_existing
    }
  end

  defp binding_set_summary(%BindingSet{} = binding_set) do
    %{
      binding_set_id: binding_set.binding_set_id,
      version: binding_set.version,
      capability_instance_count: length(binding_set.capability_instances),
      rule_count: length(binding_set.rules)
    }
  end

  defp normalize_packet_definition(%PacketDefinition{} = packet_definition) do
    %{
      packet_definition_id: packet_definition.packet_definition_id,
      packet_name: packet_definition.packet_name,
      apid: packet_definition.apid,
      version: packet_definition.version,
      fields: Enum.map(packet_definition.fields, &normalize_field_definition/1)
    }
  end

  defp normalize_field_definition(%FieldDefinition{} = field_definition) do
    %{
      field_id: field_definition.field_id,
      name: field_definition.name,
      offset_bits: field_definition.offset_bits,
      size_bits: field_definition.size_bits,
      data_type: field_definition.data_type,
      engineering_unit: field_definition.engineering_unit
    }
  end

  defp normalize_capability_instance(%CapabilityInstance{} = capability_instance) do
    %{
      capability_instance_id: capability_instance.capability_instance_id,
      family_key: capability_instance.family_key,
      target_scope: capability_instance.target_scope,
      source_endpoint_ref: capability_instance.source_endpoint_ref,
      lifecycle_state: capability_instance.lifecycle_state,
      capability_config:
        normalize_capability_config(CapabilityInstance.capability_config(capability_instance))
    }
  end

  defp normalize_capability_config(%CapabilityConfig{} = capability_config) do
    %{
      config_type: capability_config.config_type,
      document: capability_config.document
    }
  end

  defp normalize_capability_config(nil), do: nil

  defp normalize_binding_rule(%BindingRule{} = binding_rule) do
    %{
      binding_rule_id: binding_rule.binding_rule_id,
      capability_instance_id: binding_rule.capability_instance_id,
      selector: %{
        scope: %{
          target_scope: binding_rule.selector.scope.target_scope,
          source_endpoint_ref: binding_rule.selector.scope.source_endpoint_ref
        },
        match: %{
          packet_kind: binding_rule.selector.match.packet_kind,
          apid: binding_rule.selector.match.apid
        }
      },
      priority: binding_rule.priority,
      fanout_mode: binding_rule.fanout_mode
    }
  end
end
