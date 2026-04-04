defmodule Cadence.Catalog.Importers.CadenceYamlDatabase do
  @moduledoc """
  Legacy Cadence YAML command-and-telemetry importer intended for development
  bootstrap.

  This importer accepts the legacy Cadence YAML mission database shape with
  `packets` and `commands`, maps it into the new canonical telemetry and
  command snapshot models, and compiles the telemetry half into the currently
  supported runtime telemetry artifacts.
  """

  @behaviour Cadence.Catalog.Importer

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Catalog
  alias Cadence.Catalog.{Artifact, Diagnostic, ImportResult, ImporterDescriptor}
  alias Cadence.Catalog.Command.Compiler, as: CommandCompiler
  alias Cadence.Catalog.Command.Compiler.Result, as: CommandCompilerResult

  alias Cadence.Catalog.Command.{
    Argument,
    ArgumentType,
    Definition,
    EncodingEntry,
    EncodingLayout,
    MatchCriteria,
    OperationalMetadata
  }

  alias Cadence.Catalog.Telemetry.{
    CalibrationAlgorithm,
    Packet,
    PacketEntry,
    Point,
    Type,
    Unit,
    RuntimeArtifacts
  }

  alias Cadence.Governance

  alias Cadence.Catalog.Command.EnumerationValue, as: CommandEnumerationValue
  alias Cadence.Catalog.Command.Provenance, as: CommandProvenance
  alias Cadence.Catalog.Command.Snapshot, as: CommandSnapshot
  alias Cadence.Catalog.Command.TypeEncoding, as: CommandTypeEncoding
  alias Cadence.Catalog.Command.Verifier, as: CommandVerifier
  alias Cadence.Catalog.Telemetry.EnumerationValue, as: TelemetryEnumerationValue
  alias Cadence.Catalog.Telemetry.Provenance, as: TelemetryProvenance
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetrySnapshot
  alias Cadence.Catalog.Telemetry.TypeEncoding, as: TelemetryTypeEncoding

  @supported_format_keys ["cadence_yaml_telemetry", "cadence_yaml"]
  @supported_media_types ["application/yaml", "application/x-yaml", "text/yaml", "text/x-yaml"]
  @supported_data_types ~w(uint int bool boolean float string binary)
  @supported_match_criteria_types ~w(comparison range expression compound)
  @supported_match_comparisons ~w(equal not_equal greater less greater_equal less_equal in_range not_in_range)
  @supported_match_operators ~w(and or)

  @impl true
  def descriptor do
    ImporterDescriptor.new(%{
      importer_key: "cadence_yaml",
      display_name: "Cadence YAML Database",
      catalog_family: :combined,
      source_formats: @supported_format_keys,
      media_types: @supported_media_types,
      description:
        "Dev importer for the legacy Cadence combined command and telemetry YAML format"
    })
  end

  @impl true
  def validate_artifact(%Artifact{} = artifact) do
    with :ok <- validate_format(artifact),
         {:ok, yaml_source} <- extract_yaml_source(artifact),
         {:ok, parsed} <- parse_yaml(yaml_source) do
      validate_root(parsed)
    end
  end

  @impl true
  def import(%Artifact{} = artifact, %{import_run_id: import_run_id})
      when is_binary(import_run_id) do
    with :ok <- validate_artifact(artifact) do
      {:ok, yaml_source} = extract_yaml_source(artifact)
      {:ok, parsed} = parse_yaml(yaml_source)

      {telemetry_snapshot, telemetry_importer_diagnostics} =
        build_telemetry_snapshot(artifact, import_run_id, parsed)

      telemetry_runtime_artifacts =
        case telemetry_snapshot do
          %Cadence.Catalog.Telemetry.Snapshot{} = snapshot ->
            RuntimeArtifacts.compile(snapshot,
              packet_definition_version: 1,
              capability_family_key: :definition_bound_telemetry
            )

          nil ->
            nil
        end

      {command_snapshot, command_importer_diagnostics} =
        build_command_snapshot(artifact, import_run_id, parsed)

      command_compiler_result =
        case command_snapshot do
          %Cadence.Catalog.Command.Snapshot{} = snapshot -> CommandCompiler.compile(snapshot)
          nil -> CommandCompilerResult.new()
        end

      with {:ok, persisted_telemetry_snapshot} <-
             maybe_persist_telemetry_snapshot(artifact.organization_id, telemetry_snapshot),
           {:ok, binding_set} <-
             maybe_persist_runtime_artifacts(
               persisted_telemetry_snapshot,
               import_run_id,
               telemetry_runtime_artifacts
             ),
           {:ok, persisted_command_snapshot} <-
             maybe_persist_command_snapshot(artifact.organization_id, command_snapshot) do
        {:ok,
         ImportResult.new(%{
           snapshot_id:
             primary_snapshot_id(persisted_telemetry_snapshot, persisted_command_snapshot),
           imported_definition_count:
             imported_definition_count(telemetry_snapshot, command_snapshot),
           diagnostics:
             telemetry_importer_diagnostics ++
               command_importer_diagnostics ++
               telemetry_compiler_diagnostics(telemetry_runtime_artifacts) ++
               command_compiler_result.diagnostics,
           result_document:
             build_result_document(
               import_run_id,
               persisted_telemetry_snapshot,
               telemetry_runtime_artifacts,
               binding_set,
               persisted_command_snapshot,
               command_compiler_result
             )
         })}
      end
    end
  end

  defp validate_format(%Artifact{format_key: format_key} = artifact) do
    cond do
      format_key not in @supported_format_keys ->
        {:error, {:unsupported_source_format, format_key}}

      is_nil(artifact.media_type) ->
        :ok

      artifact.media_type in @supported_media_types ->
        :ok

      true ->
        {:error, {:unsupported_media_type, artifact.media_type}}
    end
  end

  defp extract_yaml_source(%Artifact{source_artifact: yaml_source}) when is_binary(yaml_source),
    do: {:ok, yaml_source}

  defp extract_yaml_source(%Artifact{source_artifact: %{"yaml" => yaml_source}})
       when is_binary(yaml_source),
       do: {:ok, yaml_source}

  defp extract_yaml_source(%Artifact{source_artifact: %{yaml: yaml_source}})
       when is_binary(yaml_source),
       do: {:ok, yaml_source}

  defp extract_yaml_source(%Artifact{}), do: {:error, :invalid_cadence_yaml_source_artifact}

  defp parse_yaml(yaml_source) when is_binary(yaml_source) do
    case YamlElixir.read_from_string(yaml_source) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, {:yaml_parse_error, reason}}
    end
  end

  defp validate_root(parsed) when is_map(parsed) do
    has_packets = section_present?(parsed, "packets")
    has_commands = section_present?(parsed, "commands")

    case {has_packets, has_commands} do
      {false, false} ->
        {:error, {:validation_error, "YAML must define a non-empty 'packets' or 'commands' list"}}

      _other ->
        with :ok <- maybe_validate_packets(parsed["packets"], has_packets) do
          maybe_validate_commands(parsed["commands"], has_commands)
        end
    end
  end

  defp validate_root(_parsed), do: {:error, {:validation_error, "YAML root must be a map"}}

  defp section_present?(parsed, key) when is_map(parsed) and is_binary(key) do
    case Map.get(parsed, key) do
      values when is_list(values) and values != [] -> true
      _other -> false
    end
  end

  defp maybe_validate_packets(_packets, false), do: :ok
  defp maybe_validate_packets(packets, true), do: validate_packets(packets)

  defp maybe_validate_commands(_commands, false), do: :ok
  defp maybe_validate_commands(commands, true), do: validate_commands(commands)

  defp validate_packets(packets) do
    Enum.reduce_while(Enum.with_index(packets), :ok, fn {packet, packet_index}, :ok ->
      case validate_packet(packet, packet_index) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_packet(packet, packet_index) when is_map(packet) do
    with {:ok, _name} <- require_binary(packet, "name", "packet", packet_index),
         {:ok, _apid} <- optional_integer(packet, "apid"),
         {:ok, items} <- require_list(packet, "items", "packet", packet_index) do
      validate_items(packet["name"], items)
    end
  end

  defp validate_packet(_packet, packet_index),
    do: {:error, {:validation_error, "Packet at index #{packet_index} must be a map"}}

  defp validate_items(packet_name, items) do
    Enum.reduce_while(Enum.with_index(items), :ok, fn {item, item_index}, :ok ->
      case validate_item(packet_name, item, item_index) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_item(packet_name, item, item_index) when is_map(item) do
    with {:ok, data_type} <- require_binary(item, "data_type", "item", item_index),
         {:ok, _name} <- require_binary(item, "name", "item", item_index),
         {:ok, bit_offset} <- require_integer(item, "bit_offset", "item", item_index),
         {:ok, bit_size} <- require_integer(item, "bit_size", "item", item_index) do
      cond do
        data_type not in @supported_data_types ->
          {:error,
           {:validation_error,
            "Item '#{item["name"]}' in packet '#{packet_name}' has unsupported data_type '#{data_type}'"}}

        bit_offset < 0 ->
          {:error,
           {:validation_error,
            "Item '#{item["name"]}' in packet '#{packet_name}' must have non-negative bit_offset"}}

        bit_size <= 0 ->
          {:error,
           {:validation_error,
            "Item '#{item["name"]}' in packet '#{packet_name}' must have bit_size > 0"}}

        true ->
          :ok
      end
    end
  end

  defp validate_item(packet_name, _item, item_index),
    do:
      {:error,
       {:validation_error, "Item at index #{item_index} in packet '#{packet_name}' must be a map"}}

  defp validate_commands(commands) do
    Enum.reduce_while(Enum.with_index(commands), :ok, fn {command, command_index}, :ok ->
      case validate_command(command, command_index) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_command(command, command_index) when is_map(command) do
    with {:ok, _name} <- require_binary(command, "name", "command", command_index),
         {:ok, _opcode} <- optional_integer(command, "opcode"),
         :ok <- validate_hazard_shape(command, command_index),
         :ok <- validate_command_parameters(command) do
      validate_command_verifiers(command)
    end
  end

  defp validate_command(_command, command_index),
    do: {:error, {:validation_error, "Command at index #{command_index} must be a map"}}

  defp validate_hazard_shape(
         %{"is_hazardous" => true, "hazard_description" => hazard_description},
         _
       )
       when is_binary(hazard_description) and hazard_description != "",
       do: :ok

  defp validate_hazard_shape(%{"is_hazardous" => true, "name" => name}, _command_index) do
    {:error, {:validation_error, "Hazardous command '#{name}' must define a hazard_description"}}
  end

  defp validate_hazard_shape(_command, _command_index), do: :ok

  defp validate_command_parameters(%{"parameters" => nil}), do: :ok

  defp validate_command_parameters(%{} = command) when not is_map_key(command, "parameters"),
    do: :ok

  defp validate_command_parameters(%{"name" => command_name, "parameters" => parameters})
       when is_list(parameters) do
    Enum.reduce_while(Enum.with_index(parameters), :ok, fn {parameter, parameter_index}, :ok ->
      case validate_command_parameter(command_name, parameter, parameter_index) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_command_parameters(%{"name" => command_name}) do
    {:error,
     {:validation_error,
      "Command '#{command_name}' field 'parameters' must be a list when present"}}
  end

  defp validate_command_verifiers(%{"verifiers" => nil}), do: :ok

  defp validate_command_verifiers(%{} = command) when not is_map_key(command, "verifiers"),
    do: :ok

  defp validate_command_verifiers(%{"name" => command_name, "verifiers" => verifiers})
       when is_list(verifiers) do
    Enum.reduce_while(Enum.with_index(verifiers), :ok, fn {verifier, verifier_index}, :ok ->
      case validate_command_verifier(command_name, verifier, verifier_index) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_command_verifiers(%{"name" => command_name}) do
    {:error,
     {:validation_error,
      "Command '#{command_name}' field 'verifiers' must be a list when present"}}
  end

  defp validate_command_verifier(command_name, verifier, verifier_index) when is_map(verifier) do
    with {:ok, _name} <- require_binary(verifier, "name", "verifier", verifier_index),
         {:ok, _timeout_ms} <- optional_integer(verifier, "timeout_ms"),
         {:ok, _delay_ms} <- optional_integer(verifier, "delay_ms"),
         :ok <- validate_command_verifier_phase(verifier),
         :ok <- validate_command_verifier_severity(verifier),
         :ok <- validate_command_match_criteria(verifier["success_criteria"], "success_criteria"),
         :ok <- validate_command_match_criteria(verifier["failure_criteria"], "failure_criteria") do
      :ok
    else
      {:error, {:validation_error, reason}} ->
        {:error,
         {:validation_error,
          "Verifier at index #{verifier_index} in command '#{command_name}' #{reason}"}}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_command_verifier(command_name, _verifier, verifier_index) do
    {:error,
     {:validation_error,
      "Verifier at index #{verifier_index} in command '#{command_name}' must be a map"}}
  end

  defp validate_command_verifier_phase(%{"phase" => phase})
       when phase not in ["acceptance", "start", "completion", "custom"] do
    {:error, {:validation_error, "has unsupported phase '#{phase}'"}}
  end

  defp validate_command_verifier_phase(_verifier), do: :ok

  defp validate_command_verifier_severity(%{"severity" => severity})
       when severity not in ["info", "warning", "error", "critical"] do
    {:error, {:validation_error, "has unsupported severity '#{severity}'"}}
  end

  defp validate_command_verifier_severity(_verifier), do: :ok

  defp validate_command_match_criteria(nil, _field), do: :ok

  defp validate_command_match_criteria(criteria, field) when is_map(criteria) do
    criteria_type = Map.get(criteria, "criteria_type", "comparison")

    cond do
      unsupported_match_criteria_type?(criteria_type) ->
        invalid_match_criteria_type(field, criteria_type)

      criteria_type == "comparison" ->
        validate_comparison_match_criteria(criteria, field)

      criteria_type == "compound" ->
        validate_compound_match_criteria(criteria, field)

      true ->
        :ok
    end
  end

  defp validate_command_match_criteria(_criteria, field) do
    {:error, {:validation_error, "#{field} must be a map when present"}}
  end

  defp unsupported_match_criteria_type?(criteria_type) do
    criteria_type not in @supported_match_criteria_types
  end

  defp invalid_match_criteria_type(field, criteria_type) do
    {:error, {:validation_error, "#{field} has unsupported criteria_type '#{criteria_type}'"}}
  end

  defp validate_comparison_match_criteria(criteria, field) do
    comparison = Map.get(criteria, "comparison")

    if comparison in @supported_match_comparisons do
      :ok
    else
      {:error, {:validation_error, "#{field} has unsupported comparison '#{comparison}'"}}
    end
  end

  defp validate_compound_match_criteria(criteria, field) do
    with :ok <- validate_compound_match_operator(criteria, field),
         {:ok, conditions} <- validate_compound_match_conditions(criteria, field) do
      Enum.reduce_while(conditions, :ok, fn nested_criteria, :ok ->
        reduce_nested_match_criteria(nested_criteria, field)
      end)
    end
  end

  defp validate_compound_match_operator(criteria, field) do
    operator = Map.get(criteria, "operator")

    if operator in @supported_match_operators do
      :ok
    else
      {:error, {:validation_error, "#{field} has unsupported operator '#{operator}'"}}
    end
  end

  defp validate_compound_match_conditions(criteria, field) do
    conditions = Map.get(criteria, "conditions", [])

    if is_list(conditions) do
      {:ok, conditions}
    else
      {:error, {:validation_error, "#{field} conditions must be a list"}}
    end
  end

  defp reduce_nested_match_criteria(nested_criteria, field) do
    case validate_command_match_criteria(nested_criteria, field <> ".conditions") do
      :ok -> {:cont, :ok}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp validate_command_parameter(command_name, parameter, parameter_index)
       when is_map(parameter) do
    with {:ok, data_type} <- require_binary(parameter, "data_type", "parameter", parameter_index),
         {:ok, _name} <- require_binary(parameter, "name", "parameter", parameter_index),
         {:ok, bit_offset} <-
           require_integer(parameter, "bit_offset", "parameter", parameter_index),
         {:ok, bit_length} <-
           require_integer(parameter, "bit_length", "parameter", parameter_index) do
      cond do
        data_type not in @supported_data_types ->
          {:error,
           {:validation_error,
            "Parameter '#{parameter["name"]}' in command '#{command_name}' has unsupported data_type '#{data_type}'"}}

        bit_offset < 0 ->
          {:error,
           {:validation_error,
            "Parameter '#{parameter["name"]}' in command '#{command_name}' must have non-negative bit_offset"}}

        bit_length <= 0 ->
          {:error,
           {:validation_error,
            "Parameter '#{parameter["name"]}' in command '#{command_name}' must have bit_length > 0"}}

        true ->
          :ok
      end
    end
  end

  defp validate_command_parameter(command_name, _parameter, parameter_index) do
    {:error,
     {:validation_error,
      "Parameter at index #{parameter_index} in command '#{command_name}' must be a map"}}
  end

  defp build_telemetry_snapshot(%Artifact{} = artifact, import_run_id, parsed) do
    if section_present?(parsed, "packets") do
      build_present_telemetry_snapshot(artifact, import_run_id, parsed)
    else
      {nil, []}
    end
  end

  defp build_present_telemetry_snapshot(%Artifact{} = artifact, import_run_id, parsed) do
    snapshot_id = "telemetry_snapshot:" <> import_run_id

    initial_state = %{
      artifact: artifact,
      import_run_id: import_run_id,
      snapshot_id: snapshot_id,
      diagnostics: build_root_diagnostics(parsed),
      units_by_symbol: %{},
      units: [],
      algorithms: [],
      types: [],
      points: []
    }

    {packets, final_state} =
      parsed["packets"]
      |> Enum.with_index()
      |> Enum.map_reduce(initial_state, fn {packet_data, packet_index}, state ->
        build_packet(packet_data, packet_index, state)
      end)

    snapshot =
      TelemetrySnapshot.new(%{
        snapshot_id: snapshot_id,
        organization_id: artifact.organization_id,
        mission_id: artifact.mission_id,
        artifact_id: artifact.artifact_id,
        import_run_id: import_run_id,
        importer_key: descriptor().importer_key,
        snapshot_name: artifact.artifact_name,
        snapshot_version: Map.get(parsed, "version", artifact.format_version),
        description: Map.get(parsed, "description"),
        units: Enum.reverse(final_state.units),
        calibration_algorithms: Enum.reverse(final_state.algorithms),
        types: Enum.reverse(final_state.types),
        points: Enum.reverse(final_state.points),
        packets: packets,
        provenance: provenance(artifact, import_run_id, ["root"], "artifact"),
        extensions: %{
          "source_format" => artifact.format_key,
          "command_count" => parsed |> Map.get("commands", []) |> List.wrap() |> length()
        }
      })

    {snapshot, Enum.reverse(final_state.diagnostics)}
  end

  defp build_packet(packet_data, packet_index, state) do
    packet_id = state.snapshot_id <> ":packet:" <> Integer.to_string(packet_index)
    packet_name = Map.fetch!(packet_data, "name")
    packet_byte_order = packet_byte_order(packet_data)

    {entries, state} =
      packet_data["items"]
      |> Enum.with_index()
      |> Enum.map_reduce(state, fn {item_data, item_index}, acc ->
        build_item(packet_data, packet_index, item_data, item_index, packet_byte_order, acc)
      end)

    packet =
      Packet.new(%{
        packet_id: packet_id,
        snapshot_id: state.snapshot_id,
        name: packet_name,
        description: Map.get(packet_data, "description"),
        apid: parsed_integer(Map.get(packet_data, "apid")),
        packet_type: parsed_integer(Map.get(packet_data, "type_byte")),
        byte_order: packet_byte_order,
        entries: entries,
        provenance:
          provenance(state.artifact, state.import_run_id, ["packets", packet_name], packet_name),
        extensions: %{
          "cadence_yaml" => %{
            "packet_index" => packet_index
          }
        }
      })

    {packet, state}
  end

  defp build_item(packet_data, packet_index, item_data, item_index, packet_byte_order, state) do
    point_id =
      state.snapshot_id <>
        ":point:" <> Integer.to_string(packet_index) <> ":" <> Integer.to_string(item_index)

    type_id =
      state.snapshot_id <>
        ":type:" <> Integer.to_string(packet_index) <> ":" <> Integer.to_string(item_index)

    path = ["packets", packet_data["name"], "items", item_data["name"]]

    {state, unit_id} = maybe_put_unit(state, item_data["units"])

    {state, default_calibration_algorithm_id} =
      maybe_put_calibration_algorithm(state, packet_data, item_data, point_id, path)

    {type_base_type, enumerations} = build_type_semantics(item_data)

    type =
      Type.new(%{
        type_id: type_id,
        snapshot_id: state.snapshot_id,
        name: packet_data["name"] <> "_" <> item_data["name"] <> "_type",
        description: Map.get(item_data, "description"),
        base_type: type_base_type,
        encoding: build_type_encoding(item_data, packet_byte_order),
        enumerations: enumerations,
        default_calibration_algorithm: default_calibration_algorithm_id,
        provenance: provenance(state.artifact, state.import_run_id, path, item_data["name"]),
        extensions: type_extensions(item_data)
      })

    point =
      Point.new(%{
        point_id: point_id,
        snapshot_id: state.snapshot_id,
        name: item_data["name"],
        description: Map.get(item_data, "description"),
        type_ref: type_id,
        unit_ref: unit_id,
        provenance: provenance(state.artifact, state.import_run_id, path, item_data["name"]),
        extensions: point_extensions(item_data)
      })

    entry =
      PacketEntry.new(%{
        packet_entry_id:
          state.snapshot_id <>
            ":entry:" <> Integer.to_string(packet_index) <> ":" <> Integer.to_string(item_index),
        entry_kind: :point_ref,
        point_ref: point_id,
        bit_offset: item_data["bit_offset"],
        display_order: item_index,
        provenance: provenance(state.artifact, state.import_run_id, path, item_data["name"])
      })

    {
      entry,
      %{
        state
        | types: [type | state.types],
          points: [point | state.points],
          diagnostics: item_diagnostics(packet_data, item_data, path) ++ state.diagnostics
      }
    }
  end

  defp maybe_put_unit(state, nil), do: {state, nil}

  defp maybe_put_unit(state, units_symbol) when is_binary(units_symbol) do
    case Map.fetch(state.units_by_symbol, units_symbol) do
      {:ok, unit_id} ->
        {state, unit_id}

      :error ->
        unit_id =
          state.snapshot_id <> ":unit:" <> Integer.to_string(map_size(state.units_by_symbol))

        unit =
          Unit.new(%{
            unit_id: unit_id,
            snapshot_id: state.snapshot_id,
            name: units_symbol,
            symbol: units_symbol,
            description: "Imported from Cadence YAML telemetry",
            provenance:
              provenance(
                state.artifact,
                state.import_run_id,
                ["units", units_symbol],
                units_symbol
              )
          })

        {
          %{
            state
            | units_by_symbol: Map.put(state.units_by_symbol, units_symbol, unit_id),
              units: [unit | state.units]
          },
          unit_id
        }
    end
  end

  defp maybe_put_calibration_algorithm(state, packet_data, item_data, point_id, path) do
    case Map.get(item_data, "conversion") do
      %{"type" => "polynomial", "coefficients" => coefficients} ->
        algorithm_id =
          state.snapshot_id <>
            ":algorithm:" <>
            Integer.to_string(length(state.algorithms))

        algorithm =
          CalibrationAlgorithm.new(%{
            algorithm_id: algorithm_id,
            snapshot_id: state.snapshot_id,
            name: packet_data["name"] <> "_" <> item_data["name"] <> "_polynomial",
            description: "Imported polynomial calibration from Cadence YAML",
            algorithm_type: :polynomial,
            polynomial_coefficients: numeric_values(coefficients),
            input_point_refs: [point_id],
            provenance: provenance(state.artifact, state.import_run_id, path, item_data["name"])
          })

        {%{state | algorithms: [algorithm | state.algorithms]}, algorithm_id}

      _other ->
        {state, nil}
    end
  end

  defp build_type_semantics(item_data) do
    case Map.get(item_data, "conversion") do
      %{"type" => "state_table", "states" => states} when is_map(states) ->
        {:enumerated, build_enumerations(states)}

      _other ->
        {base_type(Map.fetch!(item_data, "data_type")), []}
    end
  end

  defp build_type_encoding(item_data, packet_byte_order) do
    data_type = Map.fetch!(item_data, "data_type")
    byte_order = item_byte_order(item_data, packet_byte_order)
    size_bits = item_data["bit_size"]

    TelemetryTypeEncoding.new(%{
      encoding_type: encoding_type(data_type),
      size_bits: size_bits,
      byte_order: byte_order,
      signed: data_type == "int",
      integer_encoding: integer_encoding(data_type),
      float_encoding: float_encoding(data_type)
    })
  end

  defp build_enumerations(states) when is_map(states) do
    states
    |> Enum.reduce([], fn {key, label}, acc ->
      case {parsed_integer(key), label} do
        {value, label} when is_integer(value) and is_binary(label) ->
          [TelemetryEnumerationValue.new(%{value: value, label: label}) | acc]

        _other ->
          acc
      end
    end)
    |> Enum.sort_by(& &1.value)
  end

  defp build_command_snapshot(%Artifact{} = artifact, import_run_id, parsed) do
    if section_present?(parsed, "commands") do
      snapshot_id = "command_snapshot:" <> import_run_id

      initial_state = %{
        artifact: artifact,
        import_run_id: import_run_id,
        snapshot_id: snapshot_id,
        argument_types: [],
        arguments: [],
        encoding_layouts: [],
        diagnostics: []
      }

      {command_definitions, final_state} =
        parsed["commands"]
        |> Enum.with_index()
        |> Enum.map_reduce(initial_state, fn {command_data, command_index}, state ->
          build_command_definition(command_data, command_index, state)
        end)

      snapshot =
        CommandSnapshot.new(%{
          snapshot_id: snapshot_id,
          organization_id: artifact.organization_id,
          mission_id: artifact.mission_id,
          artifact_id: artifact.artifact_id,
          import_run_id: import_run_id,
          importer_key: descriptor().importer_key,
          snapshot_name: artifact.artifact_name,
          snapshot_version: Map.get(parsed, "version", artifact.format_version),
          description: Map.get(parsed, "description"),
          argument_types: Enum.reverse(final_state.argument_types),
          arguments: Enum.reverse(final_state.arguments),
          encoding_layouts: Enum.reverse(final_state.encoding_layouts),
          command_definitions: command_definitions,
          provenance: command_provenance(artifact, import_run_id, ["root"], "artifact"),
          extensions: %{"source_format" => artifact.format_key}
        })

      {snapshot, Enum.reverse(final_state.diagnostics)}
    else
      {nil, []}
    end
  end

  defp build_command_definition(command_data, command_index, state) do
    command_name = Map.fetch!(command_data, "name")
    command_id = state.snapshot_id <> ":command:" <> Integer.to_string(command_index)
    layout_id = state.snapshot_id <> ":layout:" <> Integer.to_string(command_index)
    byte_order = command_byte_order(command_data)

    {entries, {argument_ids, state}} =
      command_data
      |> Map.get("parameters", [])
      |> Enum.with_index()
      |> Enum.map_reduce({[], state}, fn {parameter_data, parameter_index}, {argument_ids, acc} ->
        {entry, argument_id, next_state} =
          build_command_parameter(
            command_data,
            command_index,
            parameter_data,
            parameter_index,
            byte_order,
            acc
          )

        {entry, {argument_ids ++ [argument_id], next_state}}
      end)

    layout =
      EncodingLayout.new(%{
        layout_id: layout_id,
        snapshot_id: state.snapshot_id,
        name: command_name <> "_layout",
        description: Map.get(command_data, "description"),
        layout_kind: :space_packet,
        byte_order: byte_order,
        size_bits: command_layout_size_bits(command_data),
        max_size_bits: command_layout_size_bits(command_data),
        opcode: parsed_integer(Map.get(command_data, "opcode")),
        opcode_size_bits: 8,
        entries: entries,
        provenance:
          command_provenance(
            state.artifact,
            state.import_run_id,
            ["commands", command_name],
            command_name
          ),
        extensions: %{"cadence_yaml" => %{"command_index" => command_index}}
      })

    definition =
      Definition.new(%{
        command_id: command_id,
        snapshot_id: state.snapshot_id,
        name: command_name,
        display_name: command_name,
        description: Map.get(command_data, "description"),
        encoding_layout_ref: layout_id,
        arguments: argument_ids,
        verifiers: build_command_verifiers(command_data, command_index, state, command_name),
        operational_metadata: build_command_operational_metadata(command_data),
        provenance:
          command_provenance(
            state.artifact,
            state.import_run_id,
            ["commands", command_name],
            command_name
          ),
        extensions: command_definition_extensions(command_data)
      })

    {
      definition,
      %{
        state
        | encoding_layouts: [layout | state.encoding_layouts]
      }
    }
  end

  defp build_command_verifiers(command_data, command_index, state, command_name) do
    command_data
    |> Map.get("verifiers", [])
    |> Enum.with_index()
    |> Enum.map(fn {verifier_data, verifier_index} ->
      verifier_name = Map.fetch!(verifier_data, "name")
      verifier_path = ["commands", command_name, "verifiers", verifier_name]

      CommandVerifier.new(%{
        verifier_id:
          state.snapshot_id <>
            ":verifier:" <>
            Integer.to_string(command_index) <>
            ":" <>
            Integer.to_string(verifier_index),
        name: verifier_name,
        description: Map.get(verifier_data, "description"),
        phase: Map.get(verifier_data, "phase", "completion"),
        success_criteria:
          build_command_match_criteria(Map.get(verifier_data, "success_criteria")),
        failure_criteria:
          build_command_match_criteria(Map.get(verifier_data, "failure_criteria")),
        timeout_ms: parsed_integer(Map.get(verifier_data, "timeout_ms")),
        delay_ms: parsed_integer(Map.get(verifier_data, "delay_ms")),
        severity: Map.get(verifier_data, "severity"),
        metadata: map_document(Map.get(verifier_data, "metadata")),
        provenance:
          command_provenance(state.artifact, state.import_run_id, verifier_path, verifier_name)
      })
    end)
  end

  defp build_command_match_criteria(nil), do: nil

  defp build_command_match_criteria(criteria_data) when is_map(criteria_data) do
    MatchCriteria.new(%{
      criteria_type: Map.get(criteria_data, "criteria_type", "comparison"),
      subject_ref: Map.get(criteria_data, "subject_ref"),
      comparison: Map.get(criteria_data, "comparison"),
      value: Map.get(criteria_data, "value"),
      range_min: numeric_value(Map.get(criteria_data, "range_min")),
      range_max: numeric_value(Map.get(criteria_data, "range_max")),
      use_calibrated: Map.get(criteria_data, "use_calibrated", true),
      boolean_expression: Map.get(criteria_data, "boolean_expression"),
      operator: Map.get(criteria_data, "operator"),
      conditions:
        criteria_data
        |> Map.get("conditions", [])
        |> Enum.map(&build_command_match_criteria/1),
      metadata: map_document(Map.get(criteria_data, "metadata")),
      extensions: map_document(Map.get(criteria_data, "extensions"))
    })
  end

  defp build_command_parameter(
         command_data,
         command_index,
         parameter_data,
         parameter_index,
         command_byte_order,
         state
       ) do
    command_name = Map.fetch!(command_data, "name")
    parameter_name = Map.fetch!(parameter_data, "name")

    argument_type_id =
      state.snapshot_id <>
        ":argument_type:" <>
        Integer.to_string(command_index) <> ":" <> Integer.to_string(parameter_index)

    argument_id =
      state.snapshot_id <>
        ":argument:" <>
        Integer.to_string(command_index) <> ":" <> Integer.to_string(parameter_index)

    path = ["commands", command_name, "parameters", parameter_name]

    argument_type =
      ArgumentType.new(%{
        argument_type_id: argument_type_id,
        snapshot_id: state.snapshot_id,
        name: command_name <> "_" <> parameter_name <> "_type",
        description: Map.get(parameter_data, "description"),
        base_type: command_argument_base_type(parameter_data),
        encoding: build_command_type_encoding(parameter_data, command_byte_order),
        enumerations: build_command_enumerations(parameter_data),
        display_unit: Map.get(parameter_data, "units"),
        valid_range_min: numeric_value(Map.get(parameter_data, "min_value")),
        valid_range_max: numeric_value(Map.get(parameter_data, "max_value")),
        provenance: command_provenance(state.artifact, state.import_run_id, path, parameter_name),
        extensions: command_argument_type_extensions(parameter_data)
      })

    argument =
      Argument.new(%{
        argument_id: argument_id,
        snapshot_id: state.snapshot_id,
        name: parameter_name,
        description: Map.get(parameter_data, "description"),
        argument_type_ref: argument_type_id,
        required: Map.get(parameter_data, "required", true),
        default_value: Map.get(parameter_data, "default_value"),
        display_order: parameter_index,
        provenance: command_provenance(state.artifact, state.import_run_id, path, parameter_name),
        extensions: command_argument_extensions(parameter_data)
      })

    entry =
      EncodingEntry.new(%{
        layout_entry_id:
          state.snapshot_id <>
            ":layout_entry:" <>
            Integer.to_string(command_index) <> ":" <> Integer.to_string(parameter_index),
        entry_kind: :argument_ref,
        argument_ref: argument_id,
        bit_offset: parameter_data["bit_offset"],
        display_order: parameter_index,
        provenance: command_provenance(state.artifact, state.import_run_id, path, parameter_name)
      })

    {
      entry,
      argument_id,
      %{
        state
        | argument_types: [argument_type | state.argument_types],
          arguments: [argument | state.arguments]
      }
    }
  end

  defp build_command_type_encoding(parameter_data, command_byte_order) do
    data_type = Map.fetch!(parameter_data, "data_type")

    CommandTypeEncoding.new(%{
      encoding_type: command_encoding_type(data_type),
      size_bits: parameter_data["bit_length"],
      byte_order: command_parameter_byte_order(parameter_data, command_byte_order),
      signed: data_type == "int",
      integer_encoding: integer_encoding(data_type),
      float_encoding: float_encoding(data_type)
    })
  end

  defp build_command_enumerations(%{"valid_values" => values}) when is_list(values) do
    values
    |> Enum.reduce([], fn value, acc ->
      case parsed_integer(value) do
        integer when is_integer(integer) ->
          [
            CommandEnumerationValue.new(%{value: integer, label: Integer.to_string(integer)})
            | acc
          ]

        _other ->
          acc
      end
    end)
    |> Enum.sort_by(& &1.value)
  end

  defp build_command_enumerations(_parameter_data), do: []

  defp build_command_operational_metadata(command_data) do
    hazardous? = Map.get(command_data, "is_hazardous") == true
    requires_confirmation? = Map.get(command_data, "requires_confirmation") == true

    OperationalMetadata.new(%{
      significance: if(hazardous?, do: :hazardous, else: :routine),
      critical: hazardous?,
      hazardous: hazardous?,
      release_policy_hint: if(requires_confirmation?, do: "confirmation_required", else: nil),
      metadata:
        %{}
        |> maybe_put_extension("hazard_description", Map.get(command_data, "hazard_description"))
        |> maybe_put_extension("requires_confirmation", requires_confirmation?)
    })
  end

  defp command_definition_extensions(command_data) do
    %{}
    |> maybe_put_extension(
      "requires_confirmation",
      Map.get(command_data, "requires_confirmation")
    )
  end

  defp command_argument_type_extensions(parameter_data) do
    %{}
    |> maybe_put_extension("valid_values", Map.get(parameter_data, "valid_values"))
  end

  defp command_argument_extensions(parameter_data) do
    %{}
    |> maybe_put_extension("min_value", Map.get(parameter_data, "min_value"))
    |> maybe_put_extension("max_value", Map.get(parameter_data, "max_value"))
  end

  defp command_argument_base_type(%{"valid_values" => values, "data_type" => data_type})
       when is_list(values) and data_type in ["uint", "int"] and values != [] do
    :enumerated
  end

  defp command_argument_base_type(%{"data_type" => data_type}), do: base_type(data_type)

  defp command_encoding_type(data_type), do: encoding_type(data_type)

  defp command_layout_size_bits(command_data) do
    command_data
    |> Map.get("parameters", [])
    |> Enum.reduce(nil, fn
      %{"bit_offset" => bit_offset, "bit_length" => bit_length}, nil
      when is_integer(bit_offset) and is_integer(bit_length) ->
        bit_offset + bit_length

      %{"bit_offset" => bit_offset, "bit_length" => bit_length}, max_bits
      when is_integer(bit_offset) and is_integer(bit_length) ->
        max(max_bits, bit_offset + bit_length)

      _parameter, max_bits ->
        max_bits
    end)
  end

  defp maybe_persist_telemetry_snapshot(_organization_id, nil), do: {:ok, nil}

  defp maybe_persist_telemetry_snapshot(organization_id, %TelemetrySnapshot{} = snapshot) do
    Catalog.persist_telemetry_snapshot(organization_id, snapshot)
  end

  defp maybe_persist_command_snapshot(_organization_id, nil), do: {:ok, nil}

  defp maybe_persist_command_snapshot(organization_id, %CommandSnapshot{} = snapshot) do
    Catalog.persist_command_snapshot(organization_id, snapshot)
  end

  defp maybe_persist_runtime_artifacts(_snapshot, _import_run_id, nil), do: {:ok, nil}

  defp maybe_persist_runtime_artifacts(
         %TelemetrySnapshot{} = snapshot,
         import_run_id,
         %{compiler_result: compiler_result}
       ) do
    persist_runtime_artifacts(snapshot, import_run_id, compiler_result)
  end

  defp persist_runtime_artifacts(
         %TelemetrySnapshot{organization_id: organization_id, mission_id: mission_id},
         _import_run_id,
         %{selector_inputs: [], packet_definitions: []}
       ) do
    if is_binary(organization_id) and is_binary(mission_id) do
      {:ok, nil}
    else
      {:error, :catalog_import_missing_scope}
    end
  end

  defp persist_runtime_artifacts(
         %TelemetrySnapshot{organization_id: organization_id, mission_id: mission_id} = snapshot,
         _import_run_id,
         compiler_result
       ) do
    if is_binary(organization_id) and is_binary(mission_id) do
      binding_set = compiled_binding_set(snapshot, compiler_result)

      case Governance.persist_binding_set(organization_id, binding_set) do
        {:ok, %BindingSet{} = persisted_binding_set} -> {:ok, persisted_binding_set}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :catalog_import_missing_scope}
    end
  end

  defp compiled_binding_set(%TelemetrySnapshot{} = snapshot, compiler_result) do
    RuntimeArtifacts.build_binding_set(snapshot, compiler_result)
  end

  defp build_result_document(
         import_run_id,
         telemetry_snapshot,
         telemetry_runtime_artifacts,
         binding_set,
         command_snapshot,
         command_compiler_result
       ) do
    %{
      "import_run_id" => import_run_id,
      "primary_snapshot_id" => primary_snapshot_id(telemetry_snapshot, command_snapshot),
      "snapshot" =>
        telemetry_snapshot_summary(telemetry_snapshot) ||
          command_snapshot_summary(command_snapshot),
      "telemetry_snapshot" => telemetry_snapshot_summary(telemetry_snapshot),
      "packet_definitions" => telemetry_packet_definitions(telemetry_runtime_artifacts),
      "selector_input_count" => telemetry_selector_input_count(telemetry_runtime_artifacts),
      "binding_set" =>
        case binding_set do
          %BindingSet{} ->
            %{
              "binding_set_id" => binding_set.binding_set_id,
              "version" => binding_set.version,
              "capability_instance_count" => length(binding_set.capability_instances),
              "rule_count" => length(binding_set.rules)
            }

          nil ->
            nil
        end,
      "command_snapshot" => command_snapshot_summary(command_snapshot),
      "command_runtime" => command_runtime_summary(command_compiler_result)
    }
  end

  defp build_root_diagnostics(_parsed), do: []

  defp primary_snapshot_id(%TelemetrySnapshot{snapshot_id: snapshot_id}, _command_snapshot),
    do: snapshot_id

  defp primary_snapshot_id(nil, %CommandSnapshot{snapshot_id: snapshot_id}), do: snapshot_id
  defp primary_snapshot_id(nil, nil), do: nil

  defp imported_definition_count(telemetry_snapshot, command_snapshot) do
    telemetry_count =
      case telemetry_snapshot do
        %TelemetrySnapshot{} = snapshot -> length(snapshot.packets)
        nil -> 0
      end

    command_count =
      case command_snapshot do
        %CommandSnapshot{} = snapshot -> length(snapshot.command_definitions)
        nil -> 0
      end

    telemetry_count + command_count
  end

  defp telemetry_compiler_diagnostics(nil), do: []

  defp telemetry_compiler_diagnostics(%{compiler_result: %{diagnostics: diagnostics}})
       when is_list(diagnostics),
       do: diagnostics

  defp telemetry_compiler_diagnostics(_other), do: []

  defp telemetry_snapshot_summary(nil), do: nil

  defp telemetry_snapshot_summary(%TelemetrySnapshot{} = snapshot) do
    %{
      "snapshot_id" => snapshot.snapshot_id,
      "snapshot_name" => snapshot.snapshot_name,
      "snapshot_version" => snapshot.snapshot_version,
      "packet_count" => length(snapshot.packets),
      "point_count" => length(snapshot.points),
      "type_count" => length(snapshot.types),
      "unit_count" => length(snapshot.units),
      "calibration_algorithm_count" => length(snapshot.calibration_algorithms)
    }
  end

  defp telemetry_packet_definitions(nil), do: []

  defp telemetry_packet_definitions(%{compiler_result: %{packet_definitions: packet_definitions}})
       when is_list(packet_definitions) do
    Enum.map(packet_definitions, fn packet_definition ->
      %{
        "packet_definition_id" => packet_definition.packet_definition_id,
        "packet_name" => packet_definition.packet_name,
        "apid" => packet_definition.apid,
        "field_count" => length(packet_definition.fields)
      }
    end)
  end

  defp telemetry_packet_definitions(_other), do: []

  defp telemetry_selector_input_count(nil), do: 0

  defp telemetry_selector_input_count(%{compiler_result: %{selector_inputs: selector_inputs}})
       when is_list(selector_inputs),
       do: length(selector_inputs)

  defp telemetry_selector_input_count(_other), do: 0

  defp command_snapshot_summary(nil), do: nil

  defp command_snapshot_summary(%CommandSnapshot{} = snapshot) do
    %{
      "snapshot_id" => snapshot.snapshot_id,
      "snapshot_name" => snapshot.snapshot_name,
      "snapshot_version" => snapshot.snapshot_version,
      "command_count" => length(snapshot.command_definitions),
      "argument_count" => length(snapshot.arguments),
      "argument_type_count" => length(snapshot.argument_types),
      "encoding_layout_count" => length(snapshot.encoding_layouts)
    }
  end

  defp command_runtime_summary(%CommandCompilerResult{} = compiler_result) do
    %{
      "runtime_definition_count" => length(compiler_result.runtime_definitions),
      "constraint_plan_count" => length(compiler_result.constraint_plans),
      "verifier_plan_count" => length(compiler_result.verifier_plans),
      "operational_binding_count" => length(compiler_result.operational_bindings),
      "runtime_definitions" =>
        Enum.map(compiler_result.runtime_definitions, fn runtime_definition ->
          %{
            "command_id" => runtime_definition.command_id,
            "name" => runtime_definition.name,
            "apid" => runtime_definition.apid,
            "opcode" => runtime_definition.opcode,
            "argument_count" => length(runtime_definition.argument_specs)
          }
        end)
    }
  end

  defp command_provenance(%Artifact{} = artifact, import_run_id, source_path, source_ref) do
    CommandProvenance.new(%{
      artifact_id: artifact.artifact_id,
      import_run_id: import_run_id,
      importer_key: descriptor().importer_key,
      source_ref: source_ref,
      source_path: source_path
    })
  end

  defp item_diagnostics(packet_data, item_data, path) do
    []
    |> maybe_add_limits_warning(item_data, path)
    |> maybe_add_polynomial_warning(packet_data, item_data, path)
    |> maybe_add_state_table_warning(packet_data, item_data, path)
    |> maybe_add_unknown_conversion_warning(packet_data, item_data, path)
  end

  defp maybe_add_limits_warning(diagnostics, %{"limits" => limits}, path) when is_map(limits) do
    [
      Diagnostic.new(%{
        severity: :warning,
        code: "cadence_yaml_telemetry.limits_preserved_as_extensions",
        message:
          "Imported YAML limits are preserved as catalog extensions and are not activated as governed limit definitions",
        path: path ++ ["limits"],
        metadata: %{"limit_keys" => Map.keys(limits)}
      })
      | diagnostics
    ]
  end

  defp maybe_add_limits_warning(diagnostics, _item_data, _path), do: diagnostics

  defp maybe_add_polynomial_warning(diagnostics, packet_data, item_data, path) do
    case Map.get(item_data, "conversion") do
      %{"type" => "polynomial"} ->
        [
          Diagnostic.new(%{
            severity: :warning,
            code: "cadence_yaml_telemetry.polynomial_preserved_not_executed",
            message:
              "Imported polynomial calibrations are preserved in the catalog snapshot but not yet executed by the current telemetry runtime",
            path: path ++ ["conversion"],
            metadata: %{
              "packet_name" => packet_data["name"],
              "item_name" => item_data["name"]
            }
          })
          | diagnostics
        ]

      _other ->
        diagnostics
    end
  end

  defp maybe_add_state_table_warning(diagnostics, packet_data, item_data, path) do
    case Map.get(item_data, "conversion") do
      %{"type" => "state_table"} ->
        [
          Diagnostic.new(%{
            severity: :warning,
            code: "cadence_yaml_telemetry.state_table_preserved_not_executed",
            message:
              "Imported state-table labels are preserved in the catalog snapshot but the current telemetry runtime still emits numeric engineering values",
            path: path ++ ["conversion"],
            metadata: %{
              "packet_name" => packet_data["name"],
              "item_name" => item_data["name"]
            }
          })
          | diagnostics
        ]

      _other ->
        diagnostics
    end
  end

  defp maybe_add_unknown_conversion_warning(diagnostics, packet_data, item_data, path) do
    case Map.get(item_data, "conversion") do
      %{"type" => conversion_type}
      when conversion_type not in ["polynomial", "state_table"] ->
        [
          Diagnostic.new(%{
            severity: :warning,
            code: "cadence_yaml_telemetry.conversion_preserved_as_extension",
            message:
              "Imported YAML conversion is preserved as a catalog extension because this importer does not model it directly",
            path: path ++ ["conversion"],
            metadata: %{
              "packet_name" => packet_data["name"],
              "item_name" => item_data["name"],
              "conversion_type" => conversion_type
            }
          })
          | diagnostics
        ]

      _other ->
        diagnostics
    end
  end

  defp point_extensions(item_data) do
    %{}
    |> maybe_put_extension("limits", Map.get(item_data, "limits"))
  end

  defp type_extensions(item_data) do
    %{}
    |> maybe_put_extension(
      "conversion",
      unknown_conversion_extension(Map.get(item_data, "conversion"))
    )
  end

  defp unknown_conversion_extension(%{"type" => conversion_type} = conversion)
       when conversion_type not in ["polynomial", "state_table"],
       do: conversion

  defp unknown_conversion_extension(_conversion), do: nil

  defp map_document(value) when is_map(value), do: value
  defp map_document(_value), do: %{}

  defp maybe_put_extension(extensions, _key, nil), do: extensions

  defp maybe_put_extension(extensions, _key, %{} = value) when map_size(value) == 0,
    do: extensions

  defp maybe_put_extension(extensions, key, value), do: Map.put(extensions, key, value)

  defp provenance(%Artifact{} = artifact, import_run_id, source_path, source_ref) do
    TelemetryProvenance.new(%{
      artifact_id: artifact.artifact_id,
      import_run_id: import_run_id,
      importer_key: descriptor().importer_key,
      source_ref: source_ref,
      source_path: source_path
    })
  end

  defp packet_byte_order(%{"big_endian" => false}), do: :little_endian
  defp packet_byte_order(_packet_data), do: :big_endian

  defp command_byte_order(%{"big_endian" => false}), do: :little_endian
  defp command_byte_order(_command_data), do: :big_endian

  defp item_byte_order(%{"endianness" => "little"}, _packet_byte_order), do: :little_endian
  defp item_byte_order(%{"endianness" => "big"}, _packet_byte_order), do: :big_endian
  defp item_byte_order(_item_data, packet_byte_order), do: packet_byte_order

  defp command_parameter_byte_order(%{"endianness" => "little"}, _command_byte_order),
    do: :little_endian

  defp command_parameter_byte_order(%{"endianness" => "big"}, _command_byte_order),
    do: :big_endian

  defp command_parameter_byte_order(_parameter_data, command_byte_order), do: command_byte_order

  defp base_type("uint"), do: :integer
  defp base_type("int"), do: :integer
  defp base_type("bool"), do: :boolean
  defp base_type("boolean"), do: :boolean
  defp base_type("float"), do: :float
  defp base_type("string"), do: :string
  defp base_type("binary"), do: :binary

  defp encoding_type("uint"), do: :integer
  defp encoding_type("int"), do: :integer
  defp encoding_type("bool"), do: :boolean
  defp encoding_type("boolean"), do: :boolean
  defp encoding_type("float"), do: :float
  defp encoding_type("string"), do: :string
  defp encoding_type("binary"), do: :binary

  defp integer_encoding("int"), do: :twos_complement
  defp integer_encoding(_data_type), do: :unsigned

  defp float_encoding("float"), do: :ieee754
  defp float_encoding(_data_type), do: nil

  defp numeric_values(values) when is_list(values) do
    Enum.reduce(values, [], fn value, acc ->
      case numeric_value(value) do
        nil -> acc
        numeric -> acc ++ [numeric]
      end
    end)
  end

  defp numeric_values(_values), do: []

  defp numeric_value(value) when is_integer(value), do: value
  defp numeric_value(value) when is_float(value), do: value

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

  defp require_binary(data, key, subject, index) when is_map(data) do
    case Map.get(data, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:validation_error, "#{subject} at index #{index} is missing '#{key}'"}}
    end
  end

  defp require_list(data, key, subject, index) when is_map(data) do
    case Map.get(data, key) do
      value when is_list(value) and value != [] ->
        {:ok, value}

      _other ->
        {:error, {:validation_error, "#{subject} at index #{index} is missing '#{key}' list"}}
    end
  end

  defp require_integer(data, key, subject, index) when is_map(data) do
    case parsed_integer(Map.get(data, key)) do
      value when is_integer(value) -> {:ok, value}
      _other -> {:error, {:validation_error, "#{subject} at index #{index} has invalid '#{key}'"}}
    end
  end

  defp optional_integer(data, key) when is_map(data) do
    case Map.get(data, key) do
      nil ->
        {:ok, nil}

      value ->
        if(is_integer(parsed_integer(value)),
          do: {:ok, parsed_integer(value)},
          else: {:error, {:validation_error, "Invalid '#{key}'"}}
        )
    end
  end
end
