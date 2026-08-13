defmodule Cadence.Catalog.MissionModel.LegacyTargetLowering do
  @moduledoc "Lowers snapshot-adapted Mission Model declarations into existing runtime contracts."

  alias Cadence.Catalog.Command.Compiler, as: CommandCompiler
  alias Cadence.Catalog.Command.Compiler.{ConstraintPlan, VerifierPlan}
  alias Cadence.Catalog.Command.MatchCriteria
  alias Cadence.Catalog.Command.Snapshot, as: CommandSnapshot
  alias Cadence.Catalog.MissionModel.{Declaration, Diagnostic, Revision}
  alias Cadence.Catalog.Telemetry.Compiler, as: TelemetryCompiler
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetrySnapshot

  @spec telemetry(Revision.t(), [Declaration.t()]) :: {map(), [Diagnostic.t()]}
  def telemetry(%Revision{} = revision, declarations) do
    if legacy_declarations?(declarations, :container, :packet_id) do
      snapshot = telemetry_snapshot(revision, declarations)
      result = TelemetryCompiler.compile(snapshot)

      plan = %{
        "target" => "telemetry",
        "runtime_contract" => "definition_bound_telemetry_v1",
        "packet_definitions" => Enum.map(result.packet_definitions, &document/1),
        "selector_inputs" => Enum.map(result.selector_inputs, &document/1)
      }

      {plan, diagnostics(result.diagnostics, :telemetry)}
    else
      {%{
         "target" => "telemetry",
         "runtime_contract" => "mission_model_container_v1",
         "packet_definitions" => [],
         "declarations" => declarations
       }, []}
    end
  end

  @spec command(Revision.t(), [Declaration.t()]) :: {map(), [Diagnostic.t()]}
  def command(%Revision{} = revision, declarations) do
    if legacy_declarations?(declarations, :command, :command_id) do
      snapshot = command_snapshot(revision, declarations)
      result = CommandCompiler.compile(snapshot)

      plan = %{
        "target" => "command",
        "runtime_contract" => "command_runtime_v1",
        "runtime_definitions" => Enum.map(result.runtime_definitions, &document/1),
        "constraint_plans" =>
          Enum.map(result.constraint_plans, fn plan ->
            plan |> resolve_constraint_criteria(declarations) |> document()
          end),
        "verifier_plans" =>
          Enum.map(result.verifier_plans, fn plan ->
            plan |> resolve_verifier_criteria(declarations) |> document()
          end),
        "operational_bindings" => Enum.map(result.operational_bindings, &document/1)
      }

      {plan, diagnostics(result.diagnostics, :command)}
    else
      {%{
         "target" => "command",
         "runtime_contract" => "mission_model_command_v1",
         "runtime_definitions" => [],
         "constraint_plans" => [],
         "verifier_plans" => [],
         "operational_bindings" => [],
         "declarations" => declarations
       }, []}
    end
  end

  defp telemetry_snapshot(revision, declarations) do
    snapshot_id = snapshot_id(declarations, "mission_model_telemetry:" <> revision.revision_id)

    TelemetrySnapshot.new(%{
      snapshot_id: snapshot_id,
      organization_id: revision.organization_id,
      mission_id: revision.mission_id,
      artifact_id: "mission_model:" <> revision.revision_id,
      import_run_id: revision.revision_id,
      importer_key: "mission_model_compiler",
      snapshot_name: "Mission Model " <> revision.revision_id,
      units: definitions(declarations, :unit),
      calibration_algorithms: definitions(declarations, :calibrator),
      types: definitions(declarations, :parameter_type),
      points: Enum.map(declarations_of(declarations, :parameter), &telemetry_point/1),
      packets: Enum.map(declarations_of(declarations, :container), &telemetry_packet/1)
    })
  end

  defp telemetry_point(declaration) do
    declaration.definition
    |> put_if_present(:type_ref, value(declaration.definition, :type_id))
    |> put_if_present(:unit_ref, value(declaration.definition, :unit_id))
  end

  defp telemetry_packet(declaration) do
    entries =
      declaration.definition
      |> value(:entries, [])
      |> Enum.map(fn entry ->
        entry
        |> put_if_present(:point_ref, value(entry, :point_id))
        |> put_if_present(:nested_packet_ref, value(entry, :nested_packet_id))
      end)

    Map.put(declaration.definition, :entries, entries)
  end

  defp command_snapshot(revision, declarations) do
    snapshot_id = snapshot_id(declarations, "mission_model_command:" <> revision.revision_id)

    CommandSnapshot.new(%{
      snapshot_id: snapshot_id,
      organization_id: revision.organization_id,
      mission_id: revision.mission_id,
      artifact_id: "mission_model:" <> revision.revision_id,
      import_run_id: revision.revision_id,
      importer_key: "mission_model_compiler",
      snapshot_name: "Mission Model " <> revision.revision_id,
      argument_types: definitions(declarations, :command_argument_type),
      arguments: Enum.map(declarations_of(declarations, :command_argument), &command_argument/1),
      encoding_layouts:
        Enum.map(declarations_of(declarations, :command_encoding), &command_encoding/1),
      command_definitions: Enum.map(declarations_of(declarations, :command), &command/1)
    })
  end

  defp command_argument(declaration) do
    put_if_present(
      declaration.definition,
      :argument_type_ref,
      value(declaration.definition, :argument_type_id)
    )
  end

  defp command_encoding(declaration) do
    entries =
      declaration.definition
      |> value(:entries, [])
      |> Enum.map(fn entry ->
        entry
        |> put_if_present(:argument_ref, value(entry, :argument_id))
        |> put_if_present(:nested_layout_ref, value(entry, :nested_layout_id))
      end)

    Map.put(declaration.definition, :entries, entries)
  end

  defp command(declaration) do
    put_if_present(
      declaration.definition,
      :encoding_layout_ref,
      value(declaration.definition, :encoding_layout_id)
    )
  end

  defp resolve_constraint_criteria(%ConstraintPlan{} = plan, declarations) do
    references =
      declaration_references(
        declarations,
        :command_constraint,
        :constraint_id,
        plan.constraint_id
      )

    %ConstraintPlan{plan | criteria: resolve_criteria(plan.criteria, references)}
  end

  defp resolve_verifier_criteria(%VerifierPlan{} = plan, declarations) do
    references =
      declaration_references(declarations, :command_verifier, :verifier_id, plan.verifier_id)

    %VerifierPlan{
      plan
      | success_criteria: resolve_criteria(plan.success_criteria, references),
        failure_criteria: resolve_criteria(plan.failure_criteria, references)
    }
  end

  defp declaration_references(declarations, kind, identity_key, identity) do
    declarations
    |> Enum.find(fn declaration ->
      declaration.kind == kind and value(declaration.definition, identity_key) == identity
    end)
    |> case do
      nil -> []
      declaration -> declaration.references
    end
  end

  defp resolve_criteria(nil, _references), do: nil

  defp resolve_criteria(%MatchCriteria{} = criteria, references) do
    subject_ref = resolved_subject(criteria.subject_ref, references)

    %MatchCriteria{
      criteria
      | subject_ref: subject_ref,
        conditions: Enum.map(criteria.conditions, &resolve_criteria(&1, references))
    }
  end

  defp resolved_subject(nil, _references), do: nil

  defp resolved_subject(subject_ref, references) do
    normalized = normalize_criteria_subject(subject_ref)

    Enum.find_value(references, subject_ref, fn reference ->
      if reference.role == :criteria and reference.source_ref == normalized and
           is_binary(reference.resolved_id) do
        reference.resolved_id
      end
    end)
  end

  defp normalize_criteria_subject("telemetry:" <> subject_ref) do
    if String.contains?(subject_ref, "/") do
      Cadence.Catalog.MissionModel.Path.normalize(subject_ref)
    else
      Cadence.Catalog.MissionModel.Path.join("/", "parameters/" <> subject_ref)
    end
  end

  defp normalize_criteria_subject(subject_ref), do: subject_ref

  defp definitions(declarations, kind),
    do: declarations |> declarations_of(kind) |> Enum.map(& &1.definition)

  defp declarations_of(declarations, kind), do: Enum.filter(declarations, &(&1.kind == kind))

  defp snapshot_id(declarations, default) do
    declarations
    |> Enum.find_value(fn declaration -> value(declaration.definition, :snapshot_id) end)
    |> case do
      nil -> default
      id -> id
    end
  end

  defp legacy_declarations?(declarations, kind, identity_key) do
    case declarations_of(declarations, kind) do
      [] -> false
      items -> Enum.all?(items, &(not is_nil(value(&1.definition, identity_key))))
    end
  end

  defp diagnostics(diagnostics, target) do
    Enum.map(diagnostics, fn diagnostic ->
      Diagnostic.new(%{
        code: diagnostic.code,
        severity: diagnostic.severity,
        stage: :target_lowering,
        target: target,
        support: if(diagnostic.severity == :error, do: :invalid, else: :transformed),
        message: diagnostic.message,
        metadata: %{path: diagnostic.path, source_metadata: diagnostic.metadata}
      })
    end)
  end

  defp document(%_{} = struct), do: struct |> Map.from_struct() |> document()

  defp document(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), document(value)} end)

  defp document(list) when is_list(list), do: Enum.map(list, &document/1)
  defp document(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&document/1)
  defp document(value), do: value

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
