defmodule Cadence.Catalog.MissionModel.Adapters.Snapshots do
  @moduledoc """
  Transitional adapter from the canonical telemetry and command snapshots to
  Mission Model declaration layers.
  """

  alias Cadence.Catalog.Bundle
  alias Cadence.Catalog.Command.Snapshot, as: CommandSnapshot

  alias Cadence.Catalog.MissionModel.{
    Declaration,
    Layer,
    LegacyNames,
    Path,
    Provenance,
    Reference
  }

  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetrySnapshot

  @spec to_layer(Bundle.t()) :: Layer.t()
  def to_layer(%Bundle{} = bundle) do
    telemetry = bundle.telemetry_snapshot
    command = bundle.command_snapshot
    scope = telemetry || command

    Layer.new(%{
      organization_id: scope.organization_id,
      mission_id: scope.mission_id,
      layer_kind: :imported,
      name: layer_name(telemetry, command),
      source: source(scope),
      declarations:
        root_declaration(scope) ++
          telemetry_declarations(telemetry) ++ command_declarations(command),
      metadata: %{"adapter" => "canonical_snapshots_v1"}
    })
  end

  defp layer_name(%TelemetrySnapshot{snapshot_name: name}, nil), do: name
  defp layer_name(nil, %CommandSnapshot{snapshot_name: name}), do: name

  defp layer_name(%TelemetrySnapshot{snapshot_name: telemetry}, %CommandSnapshot{
         snapshot_name: command
       }),
       do: telemetry <> " + " <> command

  defp source(snapshot) do
    %{
      "artifact_id" => snapshot.artifact_id,
      "import_run_id" => snapshot.import_run_id,
      "importer_key" => snapshot.importer_key,
      "adapter" => "canonical_snapshots_v1"
    }
  end

  defp root_declaration(snapshot) do
    [
      Declaration.new(%{
        kind: :space_system,
        name: "/",
        qualified_name: "/",
        definition: %{"description" => snapshot.description},
        provenance: provenance(snapshot, ["root"])
      })
    ]
  end

  defp telemetry_declarations(nil), do: []

  defp telemetry_declarations(%TelemetrySnapshot{} = snapshot) do
    unit_paths = LegacyNames.paths(snapshot.units, & &1.unit_id, :unit, & &1.name)

    calibrator_paths =
      LegacyNames.paths(
        snapshot.calibration_algorithms,
        & &1.algorithm_id,
        :calibrator,
        & &1.name
      )

    type_paths = LegacyNames.paths(snapshot.types, & &1.type_id, :parameter_type, & &1.name)
    parameter_paths = LegacyNames.paths(snapshot.points, & &1.point_id, :parameter, & &1.name)
    container_paths = LegacyNames.paths(snapshot.packets, & &1.packet_id, :container, & &1.name)

    Enum.map(snapshot.units, fn unit ->
      declaration(:unit, Map.fetch!(unit_paths, unit.unit_id), unit, snapshot, [])
    end) ++
      Enum.map(snapshot.calibration_algorithms, fn calibrator ->
        references =
          Enum.flat_map(calibrator.input_point_refs, fn point_id ->
            reference(parameter_paths, point_id, :parameter, :input)
          end)

        declaration(
          :calibrator,
          Map.fetch!(calibrator_paths, calibrator.algorithm_id),
          calibrator,
          snapshot,
          references
        )
      end) ++
      Enum.map(snapshot.types, fn type ->
        references =
          reference(
            calibrator_paths,
            type.default_calibration_algorithm_id,
            :calibrator,
            :calibrator
          )

        declaration(
          :parameter_type,
          Map.fetch!(type_paths, type.type_id),
          type,
          snapshot,
          references
        )
      end) ++
      Enum.map(snapshot.points, fn point ->
        references =
          reference(type_paths, point.type_id, :parameter_type, :type) ++
            reference(unit_paths, point.unit_id, :unit, :unit)

        declaration(
          :parameter,
          Map.fetch!(parameter_paths, point.point_id),
          point,
          snapshot,
          references,
          %{"source" => Atom.to_string(point.parameter_source)}
        )
      end) ++
      Enum.map(snapshot.packets, fn packet ->
        references =
          reference(container_paths, packet.base_packet_id, :container, :base) ++
            Enum.flat_map(packet.entries, fn entry ->
              reference(parameter_paths, entry.point_id, :parameter, :entry) ++
                reference(container_paths, entry.nested_packet_id, :container, :nested_container)
            end)

        declaration(
          :container,
          Map.fetch!(container_paths, packet.packet_id),
          packet,
          snapshot,
          references
        )
      end)
  end

  defp command_declarations(nil), do: []

  defp command_declarations(%CommandSnapshot{} = snapshot) do
    argument_type_paths =
      LegacyNames.paths(
        snapshot.argument_types,
        & &1.argument_type_id,
        :command_argument_type,
        & &1.name
      )

    argument_paths =
      LegacyNames.paths(snapshot.arguments, & &1.argument_id, :command_argument, & &1.name)

    encoding_paths =
      LegacyNames.paths(
        snapshot.encoding_layouts,
        & &1.layout_id,
        :command_encoding,
        & &1.name
      )

    command_paths =
      LegacyNames.paths(snapshot.command_definitions, & &1.command_id, :command, & &1.name)

    Enum.map(snapshot.argument_types, fn type ->
      declaration(
        :command_argument_type,
        Map.fetch!(argument_type_paths, type.argument_type_id),
        type,
        snapshot,
        []
      )
    end) ++
      Enum.map(snapshot.arguments, fn argument ->
        references =
          reference(
            argument_type_paths,
            argument.argument_type_id,
            :command_argument_type,
            :type
          )

        declaration(
          :command_argument,
          Map.fetch!(argument_paths, argument.argument_id),
          argument,
          snapshot,
          references
        )
      end) ++
      Enum.map(snapshot.encoding_layouts, fn layout ->
        references =
          Enum.flat_map(layout.entries, fn entry ->
            reference(argument_paths, entry.argument_id, :command_argument, :entry) ++
              reference(
                encoding_paths,
                entry.nested_layout_id,
                :command_encoding,
                :nested_encoding
              )
          end)

        declaration(
          :command_encoding,
          Map.fetch!(encoding_paths, layout.layout_id),
          layout,
          snapshot,
          references
        )
      end) ++
      Enum.flat_map(snapshot.command_definitions, fn command ->
        command_path = Map.fetch!(command_paths, command.command_id)

        command_references =
          reference(command_paths, command.base_command_id, :command, :base) ++
            reference(encoding_paths, command.encoding_layout_id, :command_encoding, :encoding) ++
            Enum.flat_map(command.argument_ids, fn argument_id ->
              reference(argument_paths, argument_id, :command_argument, :argument)
            end)

        command_declaration =
          declaration(:command, command_path, command, snapshot, command_references)

        [command_declaration] ++
          constraint_declarations(command, command_path, snapshot) ++
          verifier_declarations(command, command_path, snapshot)
      end)
  end

  defp constraint_declarations(command, command_path, snapshot) do
    Enum.map(command.transmission_constraints, fn constraint ->
      path = Path.join(command_path, "constraints/" <> constraint.name)

      declaration(
        :command_constraint,
        path,
        constraint,
        snapshot,
        criteria_references(constraint.criteria)
      )
    end)
  end

  defp verifier_declarations(command, command_path, snapshot) do
    Enum.map(command.verifiers, fn verifier ->
      path = Path.join(command_path, "verifiers/" <> verifier.name)

      references =
        criteria_references(verifier.success_criteria) ++
          criteria_references(verifier.failure_criteria)

      declaration(:command_verifier, path, verifier, snapshot, references)
    end)
  end

  defp criteria_references(nil), do: []

  defp criteria_references(criteria) do
    current =
      case Map.get(criteria, :subject_ref) do
        "telemetry:" <> source_ref ->
          [
            Reference.new(%{
              expected_kind: :parameter,
              source_ref: normalize_external_parameter_ref(source_ref),
              role: :criteria,
              required: true
            })
          ]

        _other ->
          []
      end

    current ++ Enum.flat_map(Map.get(criteria, :conditions, []), &criteria_references/1)
  end

  defp normalize_external_parameter_ref(source_ref) do
    case String.contains?(source_ref, "/") do
      true -> Path.normalize(source_ref)
      false -> qualified(:parameter, source_ref)
    end
  end

  defp declaration(
         kind,
         qualified_name,
         definition,
         snapshot,
         references,
         extra_definition \\ %{}
       ) do
    document =
      definition
      |> Map.from_struct()
      |> Map.drop([:__struct__, :provenance])
      |> Map.merge(extra_definition)

    Declaration.new(%{
      kind: kind,
      qualified_name: qualified_name,
      definition: document,
      references: references,
      provenance: provenance(snapshot, [Atom.to_string(kind), qualified_name])
    })
  end

  defp provenance(snapshot, path) do
    Provenance.new(%{
      artifact_id: snapshot.artifact_id,
      importer_key: snapshot.importer_key,
      source_path: path,
      metadata: %{"import_run_id" => snapshot.import_run_id}
    })
  end

  defp qualified(kind, name), do: Path.join("/", Atom.to_string(kind) <> "s/" <> name)

  defp reference(_paths, nil, _kind, _role), do: []

  defp reference(paths, source_id, kind, role) do
    source_ref = Map.get(paths, source_id, source_id)
    [Reference.new(%{expected_kind: kind, source_ref: source_ref, role: role})]
  end
end
