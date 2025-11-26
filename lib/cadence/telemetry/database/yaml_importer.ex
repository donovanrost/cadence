defmodule Cadence.Telemetry.Database.YamlImporter do
  @moduledoc """
  Imports unified command and telemetry database definitions from YAML files.

  ## YAML Format

  ```yaml
  version: "1.0.0"
  description: "Initial C&T database"

  # Telemetry packets
  packets:
    - name: HEALTH
      apid: 100
      description: "Health and status telemetry"
      items:
        - name: cpu_temp
          bit_offset: 0
          bit_size: 32
          data_type: float
          endianness: big
          units: "°C"
          description: "CPU temperature"
          conversion:
            type: polynomial
            coefficients: [0, 0.01]
        - name: power_mode
          bit_offset: 32
          bit_size: 8
          data_type: uint
          conversion:
            type: state_table
            states:
              0: "OFF"
              1: "STANDBY"
              2: "ACTIVE"

  # Commands
  commands:
    - name: SAFE_MODE
      opcode: 0x01
      description: "Enter safe mode"
      is_hazardous: true
      hazard_description: "Will disable normal operations"
      requires_confirmation: true
      allowed_phases: ["commissioning", "operations"]
      has_verification: true
      verification_item: "HEALTH.MODE"
      verification_timeout_ms: 5000
      parameters:
        - name: confirm_code
          data_type: uint
          required: true
          description: "Confirmation code"
          bit_offset: 0
          bit_length: 16

    - name: SET_TEMP
      opcode: 0x02
      description: "Set target temperature"
      parameters:
        - name: target_temp
          data_type: float
          required: true
          min_value: -40.0
          max_value: 85.0
          units: "°C"
          bit_offset: 0
          bit_length: 32
  ```

  ## Derived Items

  Derived telemetry items should be created using the runtime overlay
  (DerivedItem table) instead of defining them in YAML. This allows
  derived items to persist across database version updates and be
  managed independently of the C&T database.

  See `Cadence.Telemetry.Database.DerivedItem`.

  ## Usage

      {:ok, definition_set} = YamlImporter.import_file(mission, "/path/to/db.yaml")

      # Or with explicit version override
      {:ok, definition_set} = YamlImporter.import_file(mission, "/path/to/db.yaml", version: "2.0.0")
  """

  require Logger

  alias Cadence.Repo
  alias Cadence.Telemetry.Database.DefinitionSet
  alias Cadence.Telemetry.Packet.{PacketDefinition, PacketItem}
  alias Cadence.Telemetry.Conversions.{Conversion, PolynomialConversion, StateTableConversion}
  alias Cadence.Commands.{CommandDefinition, CommandParameter}

  @doc """
  Imports a YAML file and creates a DefinitionSet with all packet definitions.

  Returns `{:ok, definition_set}` or `{:error, reason}`.
  """
  def import_file(mission, file_path, opts \\ []) do
    with {:ok, content} <- File.read(file_path),
         {:ok, parsed} <- parse_yaml(content),
         {:ok, validated} <- validate_structure(parsed) do

      version = Keyword.get(opts, :version) || validated["version"] || "1.0.0"
      description = validated["description"]
      source_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      import_parsed(mission, validated, %{
        version: version,
        description: description,
        source_format: "yaml",
        source_filename: Path.basename(file_path),
        source_hash: source_hash
      })
    end
  end

  @doc """
  Imports from a YAML string (useful for testing).
  """
  def import_string(mission, yaml_content, opts \\ []) do
    with {:ok, parsed} <- parse_yaml(yaml_content),
         {:ok, validated} <- validate_structure(parsed) do

      version = Keyword.get(opts, :version) || validated["version"] || "1.0.0"
      description = validated["description"]
      source_hash = :crypto.hash(:sha256, yaml_content) |> Base.encode16(case: :lower)

      import_parsed(mission, validated, %{
        version: version,
        description: description,
        source_format: "yaml",
        source_filename: nil,
        source_hash: source_hash
      })
    end
  end

  defp parse_yaml(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, {:yaml_parse_error, reason}}
    end
  end

  defp validate_structure(parsed) when is_map(parsed) do
    has_packets = is_list(parsed["packets"]) && not Enum.empty?(parsed["packets"])
    has_commands = is_list(parsed["commands"]) && not Enum.empty?(parsed["commands"])

    cond do
      # Must have at least packets or commands
      not has_packets and not has_commands ->
        {:error, {:validation_error, "Must define at least 'packets' or 'commands'"}}

      # Validate packets if present
      has_packets ->
        case validate_packets(parsed["packets"]) do
          :ok ->
            # Also validate commands if present
            if has_commands do
              case validate_commands(parsed["commands"]) do
                :ok -> {:ok, parsed}
                {:error, _} = error -> error
              end
            else
              {:ok, parsed}
            end

          {:error, _} = error ->
            error
        end

      # Validate commands only (no packets)
      has_commands ->
        case validate_commands(parsed["commands"]) do
          :ok -> {:ok, parsed}
          {:error, _} = error -> error
        end
    end
  end

  defp validate_structure(_), do: {:error, {:validation_error, "YAML root must be a map"}}

  defp validate_packets(packets) do
    Enum.reduce_while(packets, :ok, fn packet, :ok ->
      case validate_packet(packet) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp validate_packet(packet) when is_map(packet) do
    cond do
      not is_binary(packet["name"]) ->
        {:error, {:validation_error, "Packet missing 'name'"}}

      not is_list(packet["items"]) ->
        {:error, {:validation_error, "Packet '#{packet["name"]}' missing 'items' list"}}

      true ->
        validate_items(packet["name"], packet["items"])
    end
  end

  defp validate_packet(_), do: {:error, {:validation_error, "Packet must be a map"}}

  defp validate_items(packet_name, items) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case validate_item(packet_name, item) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp validate_item(packet_name, item) when is_map(item) do
    required = ["name", "bit_offset", "bit_size", "data_type"]
    missing = Enum.filter(required, fn key -> is_nil(item[key]) end)

    cond do
      not Enum.empty?(missing) ->
        {:error, {:validation_error, "Item in packet '#{packet_name}' missing required fields: #{Enum.join(missing, ", ")}"}}

      item["bit_size"] <= 0 ->
        {:error, {:validation_error, "Item '#{item["name"]}' in packet '#{packet_name}' must have bit_size > 0"}}

      true ->
        :ok
    end
  end

  defp validate_item(packet_name, _),
    do: {:error, {:validation_error, "Item in packet '#{packet_name}' must be a map"}}

  # Command validation functions
  defp validate_commands(commands) do
    Enum.reduce_while(commands, :ok, fn command, :ok ->
      case validate_command(command) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp validate_command(command) when is_map(command) do
    cond do
      not is_binary(command["name"]) ->
        {:error, {:validation_error, "Command missing 'name'"}}

      command["is_hazardous"] == true && is_nil(command["hazard_description"]) ->
        {:error, {:validation_error, "Hazardous command '#{command["name"]}' missing 'hazard_description'"}}

      command["has_verification"] == true && is_nil(command["verification_item"]) ->
        {:error, {:validation_error, "Command '#{command["name"]}' with verification missing 'verification_item'"}}

      true ->
        # Validate parameters if present
        case command["parameters"] do
          nil -> :ok
          params when is_list(params) -> validate_command_parameters(command["name"], params)
          _ -> {:error, {:validation_error, "Command '#{command["name"]}' 'parameters' must be a list"}}
        end
    end
  end

  defp validate_command(_), do: {:error, {:validation_error, "Command must be a map"}}

  defp validate_command_parameters(command_name, params) do
    Enum.reduce_while(params, :ok, fn param, :ok ->
      case validate_command_parameter(command_name, param) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp validate_command_parameter(command_name, param) when is_map(param) do
    required = ["name", "data_type"]
    missing = Enum.filter(required, fn key -> is_nil(param[key]) end)

    cond do
      not Enum.empty?(missing) ->
        {:error, {:validation_error, "Parameter in command '#{command_name}' missing required fields: #{Enum.join(missing, ", ")}"}}

      param["data_type"] == "enum" && (is_nil(param["valid_values"]) || param["valid_values"] == []) ->
        {:error, {:validation_error, "Enum parameter '#{param["name"]}' in command '#{command_name}' missing 'valid_values'"}}

      true ->
        :ok
    end
  end

  defp validate_command_parameter(command_name, _),
    do: {:error, {:validation_error, "Parameter in command '#{command_name}' must be a map"}}

  defp import_parsed(mission, parsed, metadata) do
    Repo.transaction(fn ->
      # Create the DefinitionSet
      {:ok, definition_set} =
        %DefinitionSet{}
        |> DefinitionSet.changeset(%{
          mission_id: mission.id,
          version: metadata.version,
          description: metadata.description,
          source_format: metadata.source_format,
          source_filename: metadata.source_filename,
          source_hash: metadata.source_hash
        })
        |> Repo.insert()

      # Import packets if present
      case parsed["packets"] do
        packets when is_list(packets) ->
          Enum.each(packets, fn packet_data ->
            import_packet(mission, definition_set, packet_data)
          end)

        _ ->
          :ok
      end

      # Import commands if present
      case parsed["commands"] do
        commands when is_list(commands) ->
          Enum.each(commands, fn command_data ->
            import_command(mission, definition_set, command_data)
          end)

        _ ->
          :ok
      end

      # Return the definition_set with packets and commands preloaded
      Repo.preload(definition_set,
        packet_definitions: :packet_items,
        command_definitions: :command_parameters
      )
    end)
  end

  defp import_packet(mission, definition_set, packet_data) do
    {:ok, packet_def} =
      %PacketDefinition{}
      |> PacketDefinition.changeset(%{
        organization_id: mission.organization_id,
        mission_id: mission.id,
        definition_set_id: definition_set.id,
        name: packet_data["name"],
        description: packet_data["description"],
        apid: packet_data["apid"],
        type_byte: packet_data["type_byte"],
        is_big_endian: packet_data["big_endian"] != false
      })
      |> Repo.insert()

    # Import items
    Enum.each(packet_data["items"] || [], fn item_data ->
      import_item(mission, definition_set, packet_def, item_data)
    end)

    packet_def
  end

  defp import_item(mission, definition_set, packet_def, item_data) do
    # Handle inline conversion if present
    conversion_id =
      case item_data["conversion"] do
        nil -> nil
        conversion_data -> create_conversion(mission, definition_set, item_data["name"], conversion_data)
      end

    {:ok, _item} =
      %PacketItem{}
      |> PacketItem.changeset(%{
        packet_definition_id: packet_def.id,
        name: item_data["name"],
        description: item_data["description"],
        bit_offset: item_data["bit_offset"],
        bit_size: item_data["bit_size"],
        data_type: item_data["data_type"],
        endianness: item_data["endianness"] || "big",
        units: item_data["units"],
        conversion_id: conversion_id
      })
      |> Repo.insert()
  end

  defp create_conversion(mission, definition_set, item_name, %{"type" => "polynomial", "coefficients" => coefficients}) do
    # Use a short hash of definition_set_id to make conversion name unique across imports
    unique_suffix = definition_set.id |> String.slice(0, 8)

    {:ok, conversion} =
      %Conversion{}
      |> Conversion.changeset(%{
        mission_id: mission.id,
        name: "#{item_name}_conv_#{unique_suffix}",
        conversion_type: "polynomial",
        description: "Auto-generated from YAML import"
      })
      |> Repo.insert()

    {:ok, _poly} =
      %PolynomialConversion{}
      |> PolynomialConversion.changeset(%{
        conversion_id: conversion.id,
        coefficients: coefficients
      })
      |> Repo.insert()

    conversion.id
  end

  defp create_conversion(mission, definition_set, item_name, %{"type" => "state_table", "states" => states}) do
    # Convert keys to strings if they're integers
    string_states =
      Enum.into(states, %{}, fn {k, v} -> {to_string(k), v} end)

    # Use a short hash of definition_set_id to make conversion name unique across imports
    unique_suffix = definition_set.id |> String.slice(0, 8)

    {:ok, conversion} =
      %Conversion{}
      |> Conversion.changeset(%{
        mission_id: mission.id,
        name: "#{item_name}_conv_#{unique_suffix}",
        conversion_type: "state_table",
        description: "Auto-generated from YAML import"
      })
      |> Repo.insert()

    {:ok, _state_table} =
      %StateTableConversion{}
      |> StateTableConversion.changeset(%{
        conversion_id: conversion.id,
        states: string_states,
        default_state: states["default"] || "UNKNOWN"
      })
      |> Repo.insert()

    conversion.id
  end

  defp create_conversion(_mission, _definition_set, _item_name, conversion_data) do
    Logger.warning("Unknown conversion type: #{inspect(conversion_data)}")
    nil
  end

  # Command import functions
  defp import_command(mission, definition_set, command_data) do
    # Parse opcode (handle hex strings like "0x01")
    opcode = parse_opcode(command_data["opcode"])

    {:ok, command_def} =
      %CommandDefinition{}
      |> CommandDefinition.changeset(%{
        organization_id: mission.organization_id,
        mission_id: mission.id,
        definition_set_id: definition_set.id,
        name: command_data["name"],
        description: command_data["description"],
        opcode: opcode,
        is_hazardous: command_data["is_hazardous"] || false,
        hazard_description: command_data["hazard_description"],
        requires_confirmation: command_data["requires_confirmation"] || false,
        allowed_phases: command_data["allowed_phases"] || [],
        encoding_format: command_data["encoding_format"],
        encoding_config: command_data["encoding_config"] || %{},
        has_verification: command_data["has_verification"] || false,
        verification_item: command_data["verification_item"],
        verification_timeout_ms: command_data["verification_timeout_ms"] || 5000,
        metadata: command_data["metadata"] || %{}
      })
      |> Repo.insert()

    # Import parameters
    Enum.each(command_data["parameters"] || [], fn param_data ->
      import_command_parameter(command_def, param_data)
    end)

    command_def
  end

  defp import_command_parameter(command_def, param_data) do
    {:ok, _param} =
      %CommandParameter{}
      |> CommandParameter.changeset(%{
        command_definition_id: command_def.id,
        name: param_data["name"],
        description: param_data["description"],
        data_type: param_data["data_type"],
        required: param_data["required"] != false,
        default_value: to_string_or_nil(param_data["default_value"]),
        min_value: param_data["min_value"],
        max_value: param_data["max_value"],
        valid_values: param_data["valid_values"] || [],
        bit_offset: param_data["bit_offset"],
        bit_length: param_data["bit_length"],
        display_order: param_data["display_order"],
        units: param_data["units"],
        metadata: param_data["metadata"] || %{}
      })
      |> Repo.insert()
  end

  # Parse opcode from various formats (int, hex string, string)
  defp parse_opcode(nil), do: nil
  defp parse_opcode(opcode) when is_integer(opcode), do: opcode

  defp parse_opcode("0x" <> hex) do
    case Integer.parse(hex, 16) do
      {value, _} -> value
      :error -> nil
    end
  end

  defp parse_opcode(str) when is_binary(str) do
    case Integer.parse(str) do
      {value, _} -> value
      :error -> nil
    end
  end

  # Convert value to string or nil (for default_value field)
  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)
end
