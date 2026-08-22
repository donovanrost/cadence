defmodule Cadence.Catalog.Importers.CadenceYamlDatabase do
  @moduledoc """
  Imports Cadence YAML directly into a canonical Mission Model declaration layer.

  The format frontend retains source provenance but does not construct telemetry
  or command snapshots. Target-specific runtime artifacts are produced only by
  the Mission Model compiler.
  """

  @behaviour Cadence.Catalog.Importer

  alias Cadence.Catalog.{Diagnostic, ImporterDescriptor, ImportResult, Source}
  alias Cadence.Catalog.Importers.CadenceYamlDatabase.Validation
  alias Cadence.Catalog.MissionModel.{Declaration, Layer, Path, Provenance, Reference}

  @supported_format_keys ["cadence_yaml_telemetry", "cadence_yaml"]
  @supported_media_types ["application/yaml", "application/x-yaml", "text/yaml", "text/x-yaml"]

  @impl true
  def descriptor do
    ImporterDescriptor.new(%{
      importer_key: "cadence_yaml",
      version: 2,
      trust: :first_party,
      display_name: "Cadence YAML Database",
      catalog_family: :combined,
      source_formats: @supported_format_keys,
      media_types: @supported_media_types,
      description: "Cadence YAML frontend for the canonical Mission Model IR"
    })
  end

  @impl true
  def validate(%Source{} = source), do: Validation.validate(source)

  @impl true
  def import(%Source{} = source, %{import_run_id: import_run_id}) when is_binary(import_run_id) do
    with :ok <- validate(source),
         {:ok, parsed} <- Validation.parse(source) do
      {declarations, diagnostics} = translate(parsed, source, import_run_id)

      layer =
        Layer.new(%{
          organization_id: source.organization_id,
          mission_id: source.mission_id,
          layer_kind: :imported,
          name: source.artifact_name,
          version: 1,
          source: %{
            "artifact_id" => source.artifact_id,
            "import_run_id" => import_run_id,
            "importer_key" => descriptor().importer_key,
            "importer_version" => descriptor().version,
            "format_key" => source.format_key
          },
          declarations: declarations,
          metadata: %{"source_version" => Map.get(parsed, "version")}
        })

      {:ok,
       ImportResult.new(%{
         declaration_layers: [layer],
         imported_definition_count:
           length(Map.get(parsed, "packets", [])) + length(Map.get(parsed, "commands", [])),
         diagnostics: diagnostics,
         metadata: %{"import_run_id" => import_run_id}
       })}
    end
  end

  defp translate(parsed, source, import_run_id) do
    initial =
      declaration(
        :space_system,
        "/",
        %{"description" => Map.get(parsed, "description")},
        source,
        import_run_id,
        ["root"]
      )

    {telemetry, telemetry_diagnostics} = telemetry_declarations(parsed, source, import_run_id)
    commands = command_declarations(parsed, source, import_run_id)

    {[initial | telemetry ++ commands], telemetry_diagnostics}
  end

  defp telemetry_declarations(parsed, source, import_run_id) do
    parsed
    |> Map.get("packets", [])
    |> Enum.with_index()
    |> Enum.map_reduce([], fn {packet, packet_index}, diagnostics ->
      {declarations, item_diagnostics} =
        packet
        |> Map.fetch!("items")
        |> infer_item_bit_offsets()
        |> Enum.with_index()
        |> Enum.map_reduce([], fn {item, item_index}, item_diagnostics ->
          {item_declarations, diagnostics} =
            telemetry_item_declarations(
              packet,
              packet_index,
              item,
              item_index,
              source,
              import_run_id
            )

          {item_declarations, item_diagnostics ++ diagnostics}
        end)

      entries =
        packet
        |> Map.fetch!("items")
        |> infer_item_bit_offsets()
        |> Enum.map(fn item ->
          %{
            parameter_ref: parameter_path(packet["name"], item["name"]),
            bit_offset: item["bit_offset"],
            size_bits: item["bit_size"]
          }
        end)

      container_path = path("containers", packet["name"])

      container =
        declaration(
          :container,
          container_path,
          %{
            apid: parsed_integer(Map.get(packet, "apid")),
            packet_type: parsed_integer(Map.get(packet, "type_byte")),
            byte_order: byte_order(packet),
            entries: entries,
            description: Map.get(packet, "description")
          },
          source,
          import_run_id,
          ["packets", packet["name"]],
          references:
            Enum.map(entries, fn entry ->
              reference(:parameter, entry.parameter_ref, :entry)
            end)
        )

      {[container | List.flatten(declarations)], diagnostics ++ item_diagnostics}
    end)
    |> then(fn {declaration_groups, diagnostics} ->
      {declaration_groups |> List.flatten() |> deduplicate_declarations(), diagnostics}
    end)
  end

  # One source item intentionally contributes multiple independent semantic families.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp telemetry_item_declarations(
         packet,
         _packet_index,
         item,
         _item_index,
         source,
         import_run_id
       ) do
    packet_name = packet["name"]
    item_name = item["name"]
    source_path = ["packets", packet_name, "items", item_name]
    parameter_path = parameter_path(packet_name, item_name)
    type_path = path("types", packet_name, item_name)
    unit_path = item["units"] && path("units", item["units"])
    calibrator_path = path("calibrators", packet_name, item_name)
    monitoring_path = path("monitoring", packet_name, item_name)
    conversion = Map.get(item, "conversion")

    unit_declarations =
      if unit_path do
        [
          declaration(
            :unit,
            unit_path,
            %{symbol: item["units"]},
            source,
            import_run_id,
            source_path ++ ["units"]
          )
        ]
      else
        []
      end

    calibrator_declarations =
      case conversion do
        %{"type" => "polynomial", "coefficients" => coefficients} ->
          [
            declaration(
              :calibrator,
              calibrator_path,
              %{
                algorithm_type: :polynomial,
                coefficients: numeric_values(coefficients),
                required: false
              },
              source,
              import_run_id,
              source_path ++ ["conversion"],
              references: [reference(:parameter, parameter_path, :input)]
            )
          ]

        _other ->
          []
      end

    type_references =
      if calibrator_declarations == [],
        do: [],
        else: [reference(:calibrator, calibrator_path, :calibrator)]

    type =
      declaration(
        :parameter_type,
        type_path,
        %{
          base_type: telemetry_base_type(item),
          encoding: telemetry_encoding(item, byte_order(packet)),
          enumerations: telemetry_enumerations(conversion),
          extensions: unknown_conversion(conversion)
        },
        source,
        import_run_id,
        source_path,
        references: type_references
      )

    parameter_references =
      [reference(:parameter_type, type_path, :type)] ++
        if(unit_path, do: [reference(:unit, unit_path, :unit)], else: [])

    parameter =
      declaration(
        :parameter,
        parameter_path,
        %{
          description: Map.get(item, "description"),
          parameter_source: :telemetry
        },
        source,
        import_run_id,
        source_path,
        references: parameter_references
      )

    monitoring_declarations =
      case Map.get(item, "limits") do
        limits when is_map(limits) ->
          [
            declaration(
              :monitoring_policy,
              monitoring_path,
              %{
                policy_type: :numeric_thresholds,
                rules: limits,
                required: true
              },
              source,
              import_run_id,
              source_path ++ ["limits"],
              references: [reference(:parameter, parameter_path, :parameter)]
            )
          ]

        _other ->
          []
      end

    diagnostics =
      case unknown_conversion(conversion) do
        nil -> []
        preserved -> [unsupported_conversion_diagnostic(source_path, preserved)]
      end

    {unit_declarations ++ calibrator_declarations ++ [type, parameter] ++ monitoring_declarations,
     diagnostics}
  end

  defp command_declarations(parsed, source, import_run_id) do
    parsed
    |> Map.get("commands", [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {command, command_index} ->
      command_path = path("commands", command["name"])
      encoding_path = Path.join(command_path, "encoding")
      parameters = Map.get(command, "parameters", []) || []

      argument_declarations =
        parameters
        |> Enum.with_index()
        |> Enum.flat_map(fn {parameter, parameter_index} ->
          argument_path = Path.join(command_path, "arguments/" <> parameter["name"])
          type_path = path("command_types", command["name"], parameter["name"])
          source_path = ["commands", command["name"], "parameters", parameter["name"]]

          type =
            declaration(
              :command_argument_type,
              type_path,
              %{
                base_type: command_base_type(parameter),
                encoding: command_encoding(parameter, byte_order(command)),
                enumerations: command_enumerations(parameter),
                display_unit: Map.get(parameter, "units"),
                valid_range: %{
                  min: numeric_value(Map.get(parameter, "min_value")),
                  max: numeric_value(Map.get(parameter, "max_value"))
                }
              },
              source,
              import_run_id,
              source_path
            )

          argument =
            declaration(
              :command_argument,
              argument_path,
              %{
                description: Map.get(parameter, "description"),
                required: Map.get(parameter, "required", true),
                default_value: Map.get(parameter, "default_value"),
                display_order: parameter_index
              },
              source,
              import_run_id,
              source_path,
              references: [reference(:command_argument_type, type_path, :type)]
            )

          [type, argument]
        end)

      encoding_entries =
        parameters
        |> Enum.with_index()
        |> Enum.map(fn {parameter, parameter_index} ->
          %{
            entry_kind: :argument_ref,
            argument_ref: Path.join(command_path, "arguments/" <> parameter["name"]),
            bit_offset: parameter["bit_offset"],
            display_order: parameter_index
          }
        end)

      encoding =
        declaration(
          :command_encoding,
          encoding_path,
          %{
            layout_kind: :space_packet,
            byte_order: byte_order(command),
            size_bits: command_layout_size_bits(command),
            max_size_bits: command_layout_size_bits(command),
            apid: parsed_integer(Map.get(command, "apid", 0)),
            opcode: parsed_integer(Map.get(command, "opcode")),
            opcode_size_bits: 8,
            entries: encoding_entries
          },
          source,
          import_run_id,
          ["commands", command["name"]],
          references:
            Enum.map(encoding_entries, fn entry ->
              reference(:command_argument, entry.argument_ref, :entry)
            end)
        )

      argument_references =
        Enum.map(parameters, fn parameter ->
          reference(
            :command_argument,
            Path.join(command_path, "arguments/" <> parameter["name"]),
            :argument
          )
        end)

      {state_effects, effect_references} = state_effects(command, command_path, command_index)

      command_declaration =
        declaration(
          :command,
          command_path,
          %{
            display_name: command["name"],
            description: Map.get(command, "description"),
            state_effects: state_effects,
            operational_metadata: operational_metadata(command)
          },
          source,
          import_run_id,
          ["commands", command["name"]],
          references:
            [reference(:command_encoding, encoding_path, :encoding)] ++
              argument_references ++ effect_references
        )

      verifiers = verifier_declarations(command, command_path, source, import_run_id)

      argument_declarations ++ [encoding, command_declaration] ++ verifiers
    end)
  end

  defp state_effects(command, command_path, command_index) do
    argument_paths =
      command
      |> Map.get("parameters", [])
      |> List.wrap()
      |> Map.new(fn parameter ->
        {parameter["name"], Path.join(command_path, "arguments/" <> parameter["name"])}
      end)

    command
    |> Map.get("effects", [])
    |> Enum.with_index()
    |> Enum.map_reduce([], fn {effect, effect_index}, references ->
      target_path = external_parameter_path(Map.fetch!(effect, "target"))
      argument_path = Map.get(argument_paths, effect["argument"])

      effect_document = %{
        effect_id: "command_effect:#{command_index}:#{effect_index}",
        target_ref: target_path,
        operation: Map.get(effect, "operation", "set"),
        argument_ref: argument_path,
        value: Map.get(effect, "value"),
        metadata: map_document(Map.get(effect, "metadata"))
      }

      effect_references =
        [reference(:parameter, target_path, :effect)] ++
          if(argument_path,
            do: [reference(:command_argument, argument_path, :argument)],
            else: []
          )

      {effect_document, references ++ effect_references}
    end)
  end

  defp verifier_declarations(command, command_path, source, import_run_id) do
    command
    |> Map.get("verifiers", [])
    |> Enum.with_index()
    |> Enum.map(fn {verifier, index} ->
      qualified_name = Path.join(command_path, "verifiers/" <> verifier["name"])
      success = criteria_document(Map.get(verifier, "success_criteria"))
      failure = criteria_document(Map.get(verifier, "failure_criteria"))

      declaration(
        :command_verifier,
        qualified_name,
        %{
          phase: Map.get(verifier, "phase", "completion"),
          success_criteria: success,
          failure_criteria: failure,
          timeout_ms: parsed_integer(Map.get(verifier, "timeout_ms")),
          delay_ms: parsed_integer(Map.get(verifier, "delay_ms")),
          severity: Map.get(verifier, "severity"),
          metadata: map_document(Map.get(verifier, "metadata")),
          display_order: index
        },
        source,
        import_run_id,
        ["commands", command["name"], "verifiers", verifier["name"]],
        references:
          [reference(:command, command_path, :command)] ++
            criteria_references(success) ++
            criteria_references(failure)
      )
    end)
  end

  defp criteria_document(nil), do: nil

  defp criteria_document(criteria) when is_map(criteria) do
    %{
      criteria_type: Map.get(criteria, "criteria_type", "comparison"),
      subject_ref: normalize_criteria_subject(Map.get(criteria, "subject_ref")),
      comparison: Map.get(criteria, "comparison"),
      value: Map.get(criteria, "value"),
      range_min: numeric_value(Map.get(criteria, "range_min")),
      range_max: numeric_value(Map.get(criteria, "range_max")),
      use_calibrated: Map.get(criteria, "use_calibrated", true),
      boolean_expression: Map.get(criteria, "boolean_expression"),
      operator: Map.get(criteria, "operator"),
      conditions: Enum.map(Map.get(criteria, "conditions", []), &criteria_document/1),
      metadata: map_document(Map.get(criteria, "metadata")),
      extensions: map_document(Map.get(criteria, "extensions"))
    }
  end

  defp criteria_references(nil), do: []

  defp criteria_references(criteria) do
    current =
      case criteria.subject_ref do
        "/" <> _rest = subject_ref -> [reference(:parameter, subject_ref, :criteria)]
        _other -> []
      end

    current ++ Enum.flat_map(criteria.conditions, &criteria_references/1)
  end

  defp normalize_criteria_subject("telemetry:" <> subject), do: external_parameter_path(subject)

  defp normalize_criteria_subject(subject) when is_binary(subject),
    do: subject

  defp normalize_criteria_subject(_subject), do: nil

  defp external_parameter_path(subject) do
    case String.split(subject, ".", parts: 2) do
      [packet, parameter] -> parameter_path(packet, parameter)
      [parameter] -> path("parameters", parameter)
    end
  end

  defp operational_metadata(command) do
    hazardous? = Map.get(command, "is_hazardous") == true

    %{
      significance: if(hazardous?, do: :hazardous, else: :routine),
      critical: hazardous?,
      hazardous: hazardous?,
      release_policy_hint:
        if(Map.get(command, "requires_confirmation") == true,
          do: "confirmation_required",
          else: nil
        ),
      metadata: %{
        "hazard_description" => Map.get(command, "hazard_description"),
        "requires_confirmation" => Map.get(command, "requires_confirmation", false)
      }
    }
  end

  defp telemetry_base_type(%{"conversion" => %{"type" => "state_table"}}), do: :enumerated
  defp telemetry_base_type(%{"data_type" => data_type}), do: base_type(data_type)

  defp command_base_type(%{"valid_values" => values, "data_type" => type})
       when is_list(values) and values != [] and type in ["uint", "int"],
       do: :enumerated

  defp command_base_type(%{"data_type" => data_type}), do: base_type(data_type)

  defp telemetry_encoding(item, packet_byte_order) do
    encoding(item["data_type"], item["bit_size"], item_byte_order(item, packet_byte_order))
  end

  defp command_encoding(parameter, command_byte_order) do
    encoding(
      parameter["data_type"],
      parameter["bit_length"],
      item_byte_order(parameter, command_byte_order)
    )
  end

  defp encoding(data_type, size_bits, byte_order) do
    %{
      encoding_type: encoding_type(data_type),
      size_bits: size_bits,
      byte_order: byte_order,
      signed: data_type == "int",
      integer_encoding: if(data_type == "int", do: :twos_complement, else: :unsigned),
      float_encoding: if(data_type == "float", do: :ieee754, else: nil),
      dynamic_size_ref: nil
    }
  end

  defp telemetry_enumerations(%{"type" => "state_table", "states" => states})
       when is_map(states) do
    states
    |> Enum.flat_map(fn {value, label} ->
      case parsed_integer(value) do
        integer when is_integer(integer) and is_binary(label) -> [%{value: integer, label: label}]
        _other -> []
      end
    end)
    |> Enum.sort_by(& &1.value)
  end

  defp telemetry_enumerations(_conversion), do: []

  defp command_enumerations(%{"valid_values" => values}) when is_list(values) do
    values
    |> Enum.flat_map(fn value ->
      case parsed_integer(value) do
        integer when is_integer(integer) -> [%{value: integer, label: Integer.to_string(integer)}]
        _other -> []
      end
    end)
    |> Enum.sort_by(& &1.value)
  end

  defp command_enumerations(_parameter), do: []

  defp unknown_conversion(%{"type" => type} = conversion)
       when type not in ["polynomial", "state_table"],
       do: conversion

  defp unknown_conversion(_conversion), do: nil

  defp unsupported_conversion_diagnostic(source_path, conversion) do
    Diagnostic.new(%{
      severity: :warning,
      code: "CADENCE_YAML_CONVERSION_PRESERVED",
      message: "conversion is preserved but is not executable by a current Mission Model target",
      path: source_path ++ ["conversion"],
      metadata: %{"conversion" => conversion}
    })
  end

  defp declaration(
         kind,
         qualified_name,
         definition,
         source,
         import_run_id,
         source_path,
         opts \\ []
       ) do
    Declaration.new(%{
      kind: kind,
      qualified_name: qualified_name,
      definition: definition,
      references: Keyword.get(opts, :references, []),
      provenance:
        Provenance.new(%{
          artifact_id: source.artifact_id,
          importer_key: descriptor().importer_key,
          importer_version: Integer.to_string(descriptor().version),
          source_path: source_path,
          metadata: %{"import_run_id" => import_run_id}
        })
    })
  end

  defp reference(kind, source_ref, role) do
    Reference.new(%{expected_kind: kind, source_ref: source_ref, role: role, required: true})
  end

  defp deduplicate_declarations(declarations) do
    declarations
    |> Enum.reduce(%{}, fn declaration, acc ->
      Map.put_new(acc, declaration.semantic_id, declaration)
    end)
    |> Map.values()
    |> Enum.sort_by(&{&1.qualified_name, &1.kind})
  end

  defp infer_item_bit_offsets(items) do
    items
    |> Enum.map_reduce(0, fn item, next_offset ->
      bit_offset = Map.get(item, "bit_offset", next_offset)
      bit_size = Map.get(item, "bit_size", 0)
      {Map.put(item, "bit_offset", bit_offset), max(next_offset, bit_offset + bit_size)}
    end)
    |> elem(0)
  end

  defp command_layout_size_bits(command) do
    command
    |> Map.get("parameters", [])
    |> List.wrap()
    |> Enum.reduce(nil, &accumulate_layout_size/2)
  end

  defp accumulate_layout_size(
         %{"bit_offset" => offset, "bit_length" => length},
         max_bits
       )
       when is_integer(offset) and is_integer(length) and is_integer(max_bits),
       do: max(max_bits, offset + length)

  defp accumulate_layout_size(
         %{"bit_offset" => offset, "bit_length" => length},
         nil
       )
       when is_integer(offset) and is_integer(length),
       do: offset + length

  defp accumulate_layout_size(_parameter, max_bits), do: max_bits

  defp parameter_path(packet, parameter), do: path("parameters", packet, parameter)

  defp path(group, segments) when is_binary(segments),
    do: Path.join("/", group <> "/" <> segment(segments))

  defp path(group, first, second),
    do: Path.join("/", Enum.join([group, segment(first), segment(second)], "/"))

  defp segment(value), do: value |> to_string() |> String.replace("/", "_")

  defp byte_order(%{"big_endian" => false}), do: :little_endian
  defp byte_order(_document), do: :big_endian

  defp item_byte_order(%{"endianness" => "little"}, _default), do: :little_endian
  defp item_byte_order(%{"endianness" => "big"}, _default), do: :big_endian
  defp item_byte_order(_document, default), do: default

  defp base_type("uint"), do: :integer
  defp base_type("int"), do: :integer
  defp base_type(type) when type in ["bool", "boolean"], do: :boolean
  defp base_type("float"), do: :float
  defp base_type("string"), do: :string
  defp base_type("binary"), do: :binary

  defp encoding_type("uint"), do: :integer
  defp encoding_type("int"), do: :integer
  defp encoding_type(type) when type in ["bool", "boolean"], do: :boolean
  defp encoding_type("float"), do: :float
  defp encoding_type("string"), do: :string
  defp encoding_type("binary"), do: :binary

  defp numeric_values(values) when is_list(values),
    do: Enum.map(values, &numeric_value/1) |> Enum.reject(&is_nil/1)

  defp numeric_values(_values), do: []

  defp numeric_value(value) when is_number(value), do: value

  defp numeric_value(value) when is_binary(value) do
    case Float.parse(value) do
      {numeric, ""} -> numeric
      _error -> nil
    end
  end

  defp numeric_value(_value), do: nil

  defp parsed_integer(nil), do: nil
  defp parsed_integer(value) when is_integer(value), do: value

  defp parsed_integer("0x" <> hex) do
    case Integer.parse(hex, 16) do
      {integer, ""} -> integer
      _error -> nil
    end
  end

  defp parsed_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _error -> nil
    end
  end

  defp parsed_integer(_value), do: nil

  defp map_document(value) when is_map(value), do: value
  defp map_document(_value), do: %{}
end
