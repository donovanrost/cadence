defmodule CadenceWeb.API.CatalogJSON do
  @moduledoc "Catalog and governed activation response serialization boundary."

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance,
    Selector,
    SelectorMatch,
    SelectorScope
  }

  alias Cadence.Catalog.{Artifact, ImporterDescriptor, ImportRun}
  alias Cadence.Catalog.Command.Compiler.Result, as: CommandCompilerResult
  alias Cadence.Catalog.Command.Snapshot, as: CommandCatalogSnapshot
  alias Cadence.Catalog.Telemetry.Compiler.Result, as: TelemetryCompilerResult
  alias Cadence.Catalog.Telemetry.Compiler.SelectorInput
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetryCatalogSnapshot
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  @spec packet_definition(PacketDefinition.t()) :: map()
  def packet_definition(%PacketDefinition{} = packet_definition) do
    %{
      packet_definition_id: packet_definition.packet_definition_id,
      organization_id: packet_definition.organization_id,
      mission_id: packet_definition.mission_id,
      packet_name: packet_definition.packet_name,
      apid: packet_definition.apid,
      version: packet_definition.version,
      fields: Enum.map(packet_definition.fields, &field_definition/1)
    }
  end

  @spec catalog_importer(%{module: module(), descriptor: ImporterDescriptor.t()}) :: map()
  def catalog_importer(%{module: module, descriptor: %ImporterDescriptor{} = descriptor}) do
    %{
      module: inspect(module),
      importer_key: descriptor.importer_key,
      importer_version: descriptor.version,
      trust: Atom.to_string(descriptor.trust),
      display_name: descriptor.display_name,
      catalog_family: Atom.to_string(descriptor.catalog_family),
      source_formats: descriptor.source_formats,
      media_types: descriptor.media_types,
      description: descriptor.description
    }
  end

  @spec catalog_artifact(Artifact.t()) :: map()
  def catalog_artifact(%Artifact{} = artifact) do
    %{
      artifact_id: artifact.artifact_id,
      organization_id: artifact.organization_id,
      mission_id: artifact.mission_id,
      catalog_database_id: artifact.catalog_database_id,
      catalog_family: Atom.to_string(artifact.catalog_family),
      artifact_name: artifact.artifact_name,
      format_key: artifact.format_key,
      format_version: artifact.format_version,
      media_type: artifact.media_type,
      source_artifact: artifact.source_artifact,
      content_sha256: artifact.content_sha256,
      uploaded_by: artifact.uploaded_by,
      uploaded_at: iso8601(artifact.uploaded_at),
      metadata: artifact.metadata
    }
  end

  @spec catalog_import_run(ImportRun.t()) :: map()
  def catalog_import_run(%ImportRun{} = import_run) do
    %{
      import_run_id: import_run.import_run_id,
      snapshot_id: import_run.snapshot_id,
      organization_id: import_run.organization_id,
      mission_id: import_run.mission_id,
      catalog_database_id: import_run.catalog_database_id,
      artifact_id: import_run.artifact_id,
      catalog_family: Atom.to_string(import_run.catalog_family),
      importer_key: import_run.importer_key,
      importer_version: import_run.importer_version,
      status: Atom.to_string(import_run.status),
      imported_definition_count: import_run.imported_definition_count,
      diagnostics: Enum.map(import_run.diagnostics, &catalog_diagnostic/1),
      result_document: import_run.result_document,
      failure_reason: import_run.failure_reason,
      requested_by: import_run.requested_by,
      started_at: iso8601(import_run.started_at),
      completed_at: iso8601(import_run.completed_at),
      metadata: import_run.metadata
    }
  end

  @spec catalog_telemetry_snapshot_summary(TelemetryCatalogSnapshot.t()) :: map()
  def catalog_telemetry_snapshot_summary(%TelemetryCatalogSnapshot{} = snapshot) do
    %{
      snapshot_id: snapshot.snapshot_id,
      organization_id: snapshot.organization_id,
      mission_id: snapshot.mission_id,
      artifact_id: snapshot.artifact_id,
      import_run_id: snapshot.import_run_id,
      importer_key: snapshot.importer_key,
      snapshot_name: snapshot.snapshot_name,
      snapshot_version: snapshot.snapshot_version,
      description: snapshot.description,
      published_at: iso8601(snapshot.published_at),
      superseded_at: iso8601(snapshot.superseded_at),
      packet_count: length(snapshot.packets),
      point_count: length(snapshot.points),
      type_count: length(snapshot.types),
      unit_count: length(snapshot.units),
      calibration_algorithm_count: length(snapshot.calibration_algorithms)
    }
  end

  @spec catalog_telemetry_snapshot(TelemetryCatalogSnapshot.t()) :: map()
  def catalog_telemetry_snapshot(%TelemetryCatalogSnapshot{} = snapshot) do
    catalog_telemetry_snapshot_summary(snapshot)
    |> Map.put(:snapshot_document, JsonDocument.encode(snapshot))
  end

  @spec catalog_command_snapshot_summary(CommandCatalogSnapshot.t()) :: map()
  def catalog_command_snapshot_summary(%CommandCatalogSnapshot{} = snapshot) do
    %{
      snapshot_id: snapshot.snapshot_id,
      organization_id: snapshot.organization_id,
      mission_id: snapshot.mission_id,
      artifact_id: snapshot.artifact_id,
      import_run_id: snapshot.import_run_id,
      importer_key: snapshot.importer_key,
      snapshot_name: snapshot.snapshot_name,
      snapshot_version: snapshot.snapshot_version,
      description: snapshot.description,
      published_at: iso8601(snapshot.published_at),
      superseded_at: iso8601(snapshot.superseded_at),
      command_count: length(snapshot.command_definitions),
      argument_count: length(snapshot.arguments),
      argument_type_count: length(snapshot.argument_types),
      encoding_layout_count: length(snapshot.encoding_layouts)
    }
  end

  @spec catalog_command_snapshot(CommandCatalogSnapshot.t()) :: map()
  def catalog_command_snapshot(%CommandCatalogSnapshot{} = snapshot) do
    catalog_command_snapshot_summary(snapshot)
    |> Map.put(:snapshot_document, JsonDocument.encode(snapshot))
  end

  @spec catalog_telemetry_recompile_result(map()) :: map()
  def catalog_telemetry_recompile_result(%{
        snapshot: %TelemetryCatalogSnapshot{} = snapshot,
        compiler_result: %TelemetryCompilerResult{} = compiler_result,
        binding_set: %BindingSet{} = binding_set
      }) do
    %{
      snapshot: catalog_telemetry_snapshot_summary(snapshot),
      compiler_result: %{
        packet_definition_count: length(compiler_result.packet_definitions),
        selector_input_count: length(compiler_result.selector_inputs),
        diagnostic_count: length(compiler_result.diagnostics),
        diagnostics: Enum.map(compiler_result.diagnostics, &catalog_diagnostic/1),
        packet_definitions:
          Enum.map(compiler_result.packet_definitions, fn packet_definition ->
            %{
              packet_definition_id: packet_definition.packet_definition_id,
              packet_name: packet_definition.packet_name,
              apid: packet_definition.apid,
              version: packet_definition.version,
              field_count: length(packet_definition.fields)
            }
          end),
        selector_inputs: Enum.map(compiler_result.selector_inputs, &catalog_selector_input/1)
      },
      binding_set: %{
        binding_set_id: binding_set.binding_set_id,
        version: binding_set.version,
        capability_instance_count: length(binding_set.capability_instances),
        rule_count: length(binding_set.rules)
      }
    }
  end

  @spec catalog_telemetry_runtime_diff(map()) :: map()
  def catalog_telemetry_runtime_diff(report) when is_map(report) do
    %{
      snapshot_id: report.snapshot_id,
      import_run_id: report.import_run_id,
      compiler_summary: report.compiler_summary,
      compiler_diagnostics: Enum.map(report.compiler_diagnostics, &catalog_diagnostic/1),
      expected_binding_set: report.expected_binding_set,
      existing_binding_set: report.existing_binding_set,
      packet_definitions: report.packet_definitions,
      capability_instances: report.capability_instances,
      binding_rules: report.binding_rules
    }
  end

  @spec catalog_telemetry_materialization_result(map()) :: map()
  def catalog_telemetry_materialization_result(result) when is_map(result) do
    catalog_telemetry_recompile_result(result)
  end

  @spec catalog_command_compile_result(CommandCatalogSnapshot.t(), CommandCompilerResult.t()) ::
          map()
  def catalog_command_compile_result(
        %CommandCatalogSnapshot{} = snapshot,
        %CommandCompilerResult{} = compiler_result
      ) do
    %{
      snapshot: catalog_command_snapshot_summary(snapshot),
      compiler_result: %{
        runtime_definition_count: length(compiler_result.runtime_definitions),
        constraint_plan_count: length(compiler_result.constraint_plans),
        verifier_plan_count: length(compiler_result.verifier_plans),
        operational_binding_count: length(compiler_result.operational_bindings),
        diagnostic_count: length(compiler_result.diagnostics),
        diagnostics: Enum.map(compiler_result.diagnostics, &catalog_diagnostic/1),
        runtime_definitions:
          Enum.map(compiler_result.runtime_definitions, fn runtime_definition ->
            %{
              command_id: runtime_definition.command_id,
              name: runtime_definition.name,
              apid: runtime_definition.apid,
              opcode: runtime_definition.opcode,
              argument_count: length(runtime_definition.argument_specs)
            }
          end)
      }
    }
  end

  @spec binding_set(BindingSet.t()) :: map()
  def binding_set(%BindingSet{} = binding_set) do
    %{
      binding_set_id: binding_set.binding_set_id,
      organization_id: binding_set.organization_id,
      mission_id: binding_set.mission_id,
      version: binding_set.version,
      capability_instances: Enum.map(binding_set.capability_instances, &capability_instance/1),
      rules: Enum.map(binding_set.rules, &binding_rule/1)
    }
  end

  defp catalog_diagnostic(diagnostic) do
    %{
      severity: maybe_atom_to_string(diagnostic.severity),
      code: diagnostic.code,
      message: diagnostic.message,
      path: diagnostic.path,
      metadata: diagnostic.metadata
    }
  end

  defp capability_instance(%CapabilityInstance{} = capability_instance) do
    %{
      capability_instance_id: capability_instance.capability_instance_id,
      family_key: maybe_atom_to_string(capability_instance.family_key),
      target_scope: Atom.to_string(capability_instance.target_scope),
      source_endpoint_ref: capability_instance.source_endpoint_ref,
      lifecycle_state: Atom.to_string(capability_instance.lifecycle_state),
      capability_config: capability_config(capability_instance.capability_config)
    }
  end

  defp binding_rule(%BindingRule{} = binding_rule) do
    %{
      binding_rule_id: binding_rule.binding_rule_id,
      capability_instance_id: binding_rule.capability_instance_id,
      handler_key: maybe_atom_to_string(binding_rule.handler_key),
      selector: selector(binding_rule.selector),
      capability_config: capability_config(binding_rule.capability_config),
      priority: binding_rule.priority,
      fanout_mode: Atom.to_string(binding_rule.fanout_mode)
    }
  end

  defp selector(%Selector{} = selector) do
    %{
      scope: selector_scope(selector.scope),
      match: selector_match(selector.match)
    }
  end

  defp selector_scope(%SelectorScope{} = selector_scope) do
    %{
      target_scope: Atom.to_string(selector_scope.target_scope),
      source_endpoint_ref: selector_scope.source_endpoint_ref
    }
  end

  defp selector_match(%SelectorMatch{} = selector_match) do
    %{
      packet_kind: maybe_atom_to_string(selector_match.packet_kind),
      apid: selector_match.apid
    }
  end

  defp capability_config(nil), do: nil

  defp capability_config(%CapabilityConfig{} = capability_config) do
    %{
      config_type: Atom.to_string(capability_config.config_type),
      document: capability_config.document
    }
  end

  defp field_definition(%FieldDefinition{} = field_definition) do
    %{
      field_id: field_definition.field_id,
      name: field_definition.name,
      offset_bits: field_definition.offset_bits,
      size_bits: field_definition.size_bits,
      data_type: Atom.to_string(field_definition.data_type),
      engineering_unit: field_definition.engineering_unit
    }
  end

  defp catalog_selector_input(%SelectorInput{} = selector_input) do
    %{
      selector_input_id: selector_input.selector_input_id,
      packet_definition_id: selector_input.packet_definition_id,
      capability_instance_id: selector_input.capability_instance_id,
      capability_family_key: Atom.to_string(selector_input.capability_family_key),
      selector: %{
        scope: %{
          target_scope: Atom.to_string(selector_input.selector.scope.target_scope),
          source_endpoint_ref: selector_input.selector.scope.source_endpoint_ref
        },
        match: %{
          packet_kind: maybe_atom_to_string(selector_input.selector.match.packet_kind),
          apid: selector_input.selector.match.apid
        }
      }
    }
  end

  defp maybe_atom_to_string(nil), do: nil
  defp maybe_atom_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_atom_to_string(value), do: value
  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
