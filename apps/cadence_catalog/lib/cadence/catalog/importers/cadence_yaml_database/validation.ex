defmodule Cadence.Catalog.Importers.CadenceYamlDatabase.Validation do
  @moduledoc false

  alias Cadence.Catalog.Source

  @supported_format_keys ["cadence_yaml_telemetry", "cadence_yaml"]
  @supported_media_types ["application/yaml", "application/x-yaml", "text/yaml", "text/x-yaml"]
  @supported_data_types ~w(uint int bool boolean float string binary)
  @supported_match_criteria_types ~w(comparison range expression compound)
  @supported_match_comparisons ~w(equal not_equal greater less greater_equal less_equal in_range not_in_range)
  @supported_match_operators ~w(and or)
  @supported_effect_operations ~w(set increment decrement toggle)

  def validate(%Source{} = artifact) do
    with :ok <- validate_format(artifact),
         {:ok, parsed} <- parse(artifact) do
      validate_root(parsed)
    end
  end

  def parse(%Source{} = artifact) do
    with {:ok, yaml_source} <- extract_yaml_source(artifact) do
      parse_yaml(yaml_source)
    end
  end

  defp validate_format(%Source{format_key: format_key} = artifact) do
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

  defp extract_yaml_source(%Source{source_artifact: yaml_source}) when is_binary(yaml_source),
    do: {:ok, yaml_source}

  defp extract_yaml_source(%Source{source_artifact: %{"yaml" => yaml_source}})
       when is_binary(yaml_source),
       do: {:ok, yaml_source}

  defp extract_yaml_source(%Source{source_artifact: %{yaml: yaml_source}})
       when is_binary(yaml_source),
       do: {:ok, yaml_source}

  defp extract_yaml_source(%Source{}), do: {:error, :invalid_cadence_yaml_source_artifact}

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
         {:ok, apid} <- optional_integer(packet, "apid"),
         :ok <- validate_apid(apid, "Packet '#{packet["name"]}'"),
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
         {:ok, bit_offset} <- optional_integer(item, "bit_offset"),
         {:ok, bit_size} <- require_integer(item, "bit_size", "item", item_index) do
      cond do
        data_type not in @supported_data_types ->
          {:error,
           {:validation_error,
            "Item '#{item["name"]}' in packet '#{packet_name}' has unsupported data_type '#{data_type}'"}}

        is_integer(bit_offset) and bit_offset < 0 ->
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
         {:ok, apid} <- optional_integer(command, "apid"),
         :ok <- validate_apid(apid, "Command '#{command["name"]}'"),
         {:ok, _opcode} <- optional_integer(command, "opcode"),
         :ok <- validate_hazard_shape(command, command_index),
         :ok <- validate_command_parameters(command),
         :ok <- validate_command_verifiers(command) do
      validate_command_effects(command)
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

  defp validate_apid(nil, _subject), do: :ok
  defp validate_apid(apid, _subject) when apid in 0..0x7FF, do: :ok

  defp validate_apid(apid, subject) do
    {:error, {:validation_error, "#{subject} APID must be between 0 and 2047, got #{apid}"}}
  end

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

  defp validate_command_effects(%{"effects" => nil}), do: :ok

  defp validate_command_effects(%{} = command) when not is_map_key(command, "effects"),
    do: :ok

  defp validate_command_effects(%{"name" => command_name, "effects" => effects} = command)
       when is_list(effects) do
    parameter_names =
      command
      |> Map.get("parameters", [])
      |> Enum.map(& &1["name"])
      |> MapSet.new()

    Enum.reduce_while(Enum.with_index(effects), :ok, fn {effect, effect_index}, :ok ->
      case validate_command_effect(command_name, effect, effect_index, parameter_names) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_command_effects(%{"name" => command_name}) do
    {:error,
     {:validation_error, "Command '#{command_name}' field 'effects' must be a list when present"}}
  end

  defp validate_command_effect(command_name, effect, effect_index, parameter_names)
       when is_map(effect) do
    operation = Map.get(effect, "operation", "set")
    argument = Map.get(effect, "argument")

    with {:ok, _target} <- require_binary(effect, "target", "effect", effect_index),
         :ok <- validate_effect_operation(command_name, operation),
         :ok <- validate_effect_argument(command_name, argument, parameter_names) do
      validate_effect_value_source(command_name, effect, operation, argument)
    end
  end

  defp validate_command_effect(command_name, _effect, effect_index, _parameter_names) do
    {:error,
     {:validation_error,
      "Effect at index #{effect_index} in command '#{command_name}' must be a map"}}
  end

  defp validate_effect_operation(_command_name, operation)
       when operation in @supported_effect_operations,
       do: :ok

  defp validate_effect_operation(command_name, operation) do
    {:error,
     {:validation_error,
      "Command '#{command_name}' effect has unsupported operation '#{operation}'"}}
  end

  defp validate_effect_argument(_command_name, nil, _parameter_names), do: :ok

  defp validate_effect_argument(command_name, argument, parameter_names)
       when is_binary(argument) do
    if MapSet.member?(parameter_names, argument) do
      :ok
    else
      {:error,
       {:validation_error,
        "Command '#{command_name}' effect references unknown argument '#{argument}'"}}
    end
  end

  defp validate_effect_argument(command_name, _argument, _parameter_names) do
    {:error, {:validation_error, "Command '#{command_name}' effect argument must be a string"}}
  end

  defp validate_effect_value_source(_command_name, _effect, "toggle", _argument), do: :ok

  defp validate_effect_value_source(command_name, effect, operation, argument) do
    if is_binary(argument) or Map.has_key?(effect, "value") do
      :ok
    else
      {:error,
       {:validation_error,
        "Command '#{command_name}' #{operation} effect requires an argument or value"}}
    end
  end

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
end
