defmodule Cadence.MissionDatabase.YamlImporter do
  @moduledoc """
  Imports unified command and telemetry database definitions from YAML files.

  This importer creates a complete DefinitionSet with all associated entities:
  - DataTypes (with encoding, calibration, and alarm definitions)
  - Algorithms (polynomial, spline, state_table)
  - Units
  - Containers (packet definitions)
  - ContainerEntries (packet item mappings)
  - Parameters (telemetry items)
  - MetaCommands (command definitions)
  - Arguments (command parameters)

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
          limits:
            red_low: -40.0
            yellow_low: -20.0
            yellow_high: 70.0
            red_high: 85.0
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
      parameters:
        - name: confirm_code
          data_type: uint
          required: true
          bit_offset: 0
          bit_length: 16
  ```

  ## Usage

      {:ok, definition_set} = YamlImporter.import_file(mission, "/path/to/db.yaml")

      # Or with explicit version override
      {:ok, definition_set} = YamlImporter.import_file(mission, "/path/to/db.yaml", version: "2.0.0")
  """

  require Logger

  alias Cadence.Config.VersionRegistry
  alias Cadence.MissionDatabase.{
    Algorithm,
    Argument,
    Container,
    ContainerEntry,
    DataType,
    DefinitionSet,
    MetaCommand,
    Parameter,
    Unit
  }
  alias Cadence.Repo

  @doc """
  Imports a YAML file and creates a DefinitionSet with all definitions.

  Returns `{:ok, definition_set}` or `{:error, reason}`.
  """
  def import_file(database, file_path, opts \\ []) do
    with {:ok, content} <- File.read(file_path),
         {:ok, parsed} <- parse_yaml(content),
         {:ok, validated} <- validate_structure(parsed) do
      version = Keyword.get(opts, :version) || validated["version"] || "1.0.0"
      description = validated["description"]
      source_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      result =
        import_parsed(database, validated, %{
          version: version,
          description: description,
          source_format: :yaml,
          source_filename: Path.basename(file_path),
          source_hash: source_hash
        })

      # Invalidate cache after successful import
      case result do
        {:ok, definition_set} ->
          VersionRegistry.invalidate(:definition_set, definition_set.id)
          {:ok, definition_set}

        error ->
          error
      end
    end
  end

  @doc """
  Imports from a YAML string (useful for testing).
  """
  def import_string(database, yaml_content, opts \\ []) do
    with {:ok, parsed} <- parse_yaml(yaml_content),
         {:ok, validated} <- validate_structure(parsed) do
      version = Keyword.get(opts, :version) || validated["version"] || "1.0.0"
      description = validated["description"]
      source_hash = :crypto.hash(:sha256, yaml_content) |> Base.encode16(case: :lower)

      result =
        import_parsed(database, validated, %{
          version: version,
          description: description,
          source_format: :yaml,
          source_filename: nil,
          source_hash: source_hash
        })

      # Invalidate cache after successful import
      case result do
        {:ok, definition_set} ->
          VersionRegistry.invalidate(:definition_set, definition_set.id)
          {:ok, definition_set}

        error ->
          error
      end
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
      not has_packets and not has_commands ->
        {:error, {:validation_error, "Must define at least 'packets' or 'commands'"}}

      has_packets ->
        case validate_packets(parsed["packets"]) do
          :ok ->
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
        {:error,
         {:validation_error,
          "Item in packet '#{packet_name}' missing required fields: #{Enum.join(missing, ", ")}"}}

      item["bit_size"] <= 0 ->
        {:error,
         {:validation_error,
          "Item '#{item["name"]}' in packet '#{packet_name}' must have bit_size > 0"}}

      true ->
        :ok
    end
  end

  defp validate_item(packet_name, _),
    do: {:error, {:validation_error, "Item in packet '#{packet_name}' must be a map"}}

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
        {:error,
         {:validation_error,
          "Hazardous command '#{command["name"]}' missing 'hazard_description'"}}

      true ->
        case command["parameters"] do
          nil ->
            :ok

          params when is_list(params) ->
            validate_command_parameters(command["name"], params)

          _ ->
            {:error,
             {:validation_error, "Command '#{command["name"]}' 'parameters' must be a list"}}
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
        {:error,
         {:validation_error,
          "Parameter in command '#{command_name}' missing required fields: #{Enum.join(missing, ", ")}"}}

      param["data_type"] == "enum" &&
          (is_nil(param["valid_values"]) || param["valid_values"] == []) ->
        {:error,
         {:validation_error,
          "Enum parameter '#{param["name"]}' in command '#{command_name}' missing 'valid_values'"}}

      true ->
        :ok
    end
  end

  defp validate_command_parameter(command_name, _),
    do: {:error, {:validation_error, "Parameter in command '#{command_name}' must be a map"}}

  # ============================================================================
  # Import Logic
  # ============================================================================

  defp import_parsed(database, parsed, metadata) do
    # Preload mission to get organization_id
    database = Repo.preload(database, :mission)
    organization_id = database.mission.organization_id

    Repo.transaction(fn ->
      # Create the DefinitionSet
      {:ok, definition_set} =
        %DefinitionSet{}
        |> DefinitionSet.changeset(%{
          organization_id: organization_id,
          database_id: database.id,
          version: metadata.version,
          description: metadata.description,
          source_format: metadata.source_format,
          source_filename: metadata.source_filename,
          source_hash: metadata.source_hash
        })
        |> Repo.insert()

      # Create a context for tracking created entities
      ctx = %{
        database: database,
        definition_set: definition_set,
        data_types: %{},
        algorithms: %{},
        units: %{},
        parameters: %{}
      }

      # Import packets (creates containers, parameters, data_types, algorithms)
      ctx =
        case parsed["packets"] do
          packets when is_list(packets) ->
            Enum.reduce(packets, ctx, fn packet_data, acc ->
              import_packet(acc, packet_data)
            end)

          _ ->
            ctx
        end

      # Import commands (creates meta_commands, arguments)
      _ctx =
        case parsed["commands"] do
          commands when is_list(commands) ->
            Enum.reduce(commands, ctx, fn command_data, acc ->
              import_command(acc, command_data)
            end)

          _ ->
            ctx
        end

      # Return the definition_set with associations preloaded
      Repo.preload(definition_set, [
        :data_types,
        :algorithms,
        :units,
        containers: :container_entries,
        parameters: :data_type,
        meta_commands: :arguments
      ])
    end)
  end

  # ============================================================================
  # Packet Import
  # ============================================================================

  defp import_packet(ctx, packet_data) do
    # Create the container (packet)
    {:ok, container} =
      %Container{}
      |> Container.changeset(%{
        organization_id: ctx.database.mission.organization_id,
        mission_id: ctx.database.mission_id,
        definition_set_id: ctx.definition_set.id,
        name: packet_data["name"],
        description: packet_data["description"],
        apid: packet_data["apid"],
        packet_type: packet_data["type_byte"],
        byte_order: parse_byte_order(packet_data["big_endian"])
      })
      |> Repo.insert()

    # Import items (creates parameters, data_types, container_entries)
    ctx =
      (packet_data["items"] || [])
      |> Enum.with_index()
      |> Enum.reduce(ctx, fn {item_data, index}, acc ->
        import_item(acc, container, item_data, index)
      end)

    ctx
  end

  defp parse_byte_order(nil), do: :big_endian
  defp parse_byte_order(true), do: :big_endian
  defp parse_byte_order(false), do: :little_endian

  # ============================================================================
  # Item Import
  # ============================================================================

  defp import_item(ctx, container, item_data, display_order) do
    # Determine the base type from the YAML data_type
    base_type = parse_base_type(item_data["data_type"])

    # Create or get the data type
    {ctx, data_type} = get_or_create_data_type(ctx, container, item_data, base_type)

    # Create the parameter
    {:ok, parameter} =
      %Parameter{}
      |> Parameter.changeset(%{
        organization_id: ctx.database.mission.organization_id,
        mission_id: ctx.database.mission_id,
        definition_set_id: ctx.definition_set.id,
        name: "#{container.name}.#{item_data["name"]}",
        description: item_data["description"],
        data_type_id: data_type.id,
        parameter_source: :telemetry
      })
      |> Repo.insert()

    # Create the container entry
    {:ok, _entry} =
      %ContainerEntry{}
      |> ContainerEntry.changeset(%{
        container_id: container.id,
        entry_type: :parameter_ref,
        parameter_id: parameter.id,
        parameter_ref: parameter.name,
        bit_offset: item_data["bit_offset"],
        bit_offset_from: :container_start,
        display_order: display_order
      })
      |> Repo.insert()

    # Track the parameter for later reference
    put_in(ctx, [:parameters, parameter.name], parameter)
  end

  defp parse_base_type("float"), do: :float
  defp parse_base_type("int"), do: :integer
  defp parse_base_type("uint"), do: :integer
  defp parse_base_type("string"), do: :string
  defp parse_base_type("binary"), do: :binary
  defp parse_base_type("bool"), do: :boolean
  defp parse_base_type("boolean"), do: :boolean
  defp parse_base_type(_), do: :integer

  # ============================================================================
  # DataType Creation
  # ============================================================================

  defp get_or_create_data_type(ctx, container, item_data, base_type) do
    type_name = generate_type_name(container.name, item_data["name"])

    # Check if we have a conversion (which creates an Algorithm)
    {ctx, algorithm_id} =
      case item_data["conversion"] do
        nil -> {ctx, nil}
        conversion_data -> create_algorithm(ctx, type_name, conversion_data)
      end

    # Parse limits into alarm definition
    alarm_definition = parse_limits_to_alarm(item_data["limits"])

    # Create or get unit if specified
    {ctx, unit_id} =
      case item_data["units"] do
        nil -> {ctx, nil}
        units_str -> get_or_create_unit(ctx, units_str)
      end

    # Build the encoding
    encoding = %{
      encoding_type: parse_encoding_type(item_data["data_type"]),
      size_in_bits: item_data["bit_size"],
      byte_order: parse_byte_order_atom(item_data["endianness"]),
      integer_encoding: parse_integer_encoding(item_data["data_type"])
    }

    # Create the DataType
    attrs = %{
      organization_id: ctx.database.mission.organization_id,
      mission_id: ctx.database.mission_id,
      definition_set_id: ctx.definition_set.id,
      name: type_name,
      description: item_data["description"],
      base_type: base_type,
      encoding: encoding,
      default_calibrator_id: algorithm_id,
      unit_id: unit_id
    }

    # Add alarm definition if present
    attrs = if alarm_definition, do: Map.put(attrs, :default_alarm, alarm_definition), else: attrs

    {:ok, data_type} =
      %DataType{}
      |> DataType.changeset(attrs)
      |> Repo.insert()

    ctx = put_in(ctx, [:data_types, type_name], data_type)
    {ctx, data_type}
  end

  defp generate_type_name(container_name, item_name) do
    "#{container_name}_#{item_name}_Type"
  end

  defp parse_encoding_type("float"), do: :float
  defp parse_encoding_type("int"), do: :integer
  defp parse_encoding_type("uint"), do: :integer
  defp parse_encoding_type("string"), do: :string
  defp parse_encoding_type("binary"), do: :binary
  defp parse_encoding_type("bool"), do: :integer
  defp parse_encoding_type("boolean"), do: :integer
  defp parse_encoding_type(_), do: :integer

  defp parse_byte_order_atom(nil), do: :big_endian
  defp parse_byte_order_atom("big"), do: :big_endian
  defp parse_byte_order_atom("little"), do: :little_endian
  defp parse_byte_order_atom(_), do: :big_endian

  defp parse_integer_encoding("uint"), do: :unsigned
  defp parse_integer_encoding("int"), do: :twos_complement
  defp parse_integer_encoding("bool"), do: :unsigned
  defp parse_integer_encoding("boolean"), do: :unsigned
  defp parse_integer_encoding(_), do: nil

  # ============================================================================
  # Algorithm Creation
  # ============================================================================

  defp create_algorithm(ctx, item_name, %{"type" => "polynomial", "coefficients" => coefficients}) do
    algo_name = "#{item_name}_cal"

    {:ok, algorithm} =
      %Algorithm{}
      |> Algorithm.changeset(%{
        organization_id: ctx.database.mission.organization_id,
        mission_id: ctx.database.mission_id,
        definition_set_id: ctx.definition_set.id,
        name: algo_name,
        description: "Auto-generated from YAML import",
        algorithm_type: :polynomial,
        polynomial_coefficients: Enum.map(coefficients, &to_float/1)
      })
      |> Repo.insert()

    ctx = put_in(ctx, [:algorithms, algo_name], algorithm)
    {ctx, algorithm.id}
  end

  defp create_algorithm(ctx, item_name, %{"type" => "state_table", "states" => states}) do
    algo_name = "#{item_name}_states"

    # Convert keys to strings
    string_states =
      Enum.into(states, %{}, fn {k, v} -> {to_string(k), v} end)

    {:ok, algorithm} =
      %Algorithm{}
      |> Algorithm.changeset(%{
        organization_id: ctx.database.mission.organization_id,
        mission_id: ctx.database.mission_id,
        definition_set_id: ctx.definition_set.id,
        name: algo_name,
        description: "Auto-generated from YAML import",
        algorithm_type: :state_table,
        state_table: string_states,
        state_table_default: states["default"] || "UNKNOWN"
      })
      |> Repo.insert()

    ctx = put_in(ctx, [:algorithms, algo_name], algorithm)
    {ctx, algorithm.id}
  end

  defp create_algorithm(ctx, _item_name, conversion_data) do
    Logger.warning("Unknown conversion type: #{inspect(conversion_data)}")
    {ctx, nil}
  end

  defp to_float(x) when is_float(x), do: x
  defp to_float(x) when is_integer(x), do: x * 1.0
  defp to_float(x) when is_binary(x), do: String.to_float(x)

  # ============================================================================
  # Unit Creation
  # ============================================================================

  defp get_or_create_unit(ctx, units_str) do
    case Map.get(ctx.units, units_str) do
      nil ->
        {:ok, unit} =
          %Unit{}
          |> Unit.changeset(%{
            organization_id: ctx.database.mission.organization_id,
            mission_id: ctx.database.mission_id,
            definition_set_id: ctx.definition_set.id,
            name: units_str,
            symbol: units_str,
            description: "Auto-generated from YAML import"
          })
          |> Repo.insert()

        ctx = put_in(ctx, [:units, units_str], unit)
        {ctx, unit.id}

      existing_unit ->
        {ctx, existing_unit.id}
    end
  end

  # ============================================================================
  # Alarm/Limits Parsing
  # ============================================================================

  defp parse_limits_to_alarm(nil), do: nil

  defp parse_limits_to_alarm(limits) when is_map(limits) do
    # Build alarm ranges from YAML limit thresholds
    watch_range = build_range(limits["yellow_low"], limits["yellow_high"])
    warning_range = build_range(limits["red_low"], limits["red_high"])

    if watch_range || warning_range do
      %{
        watch_range: watch_range,
        warning_range: warning_range
      }
    else
      nil
    end
  end

  defp parse_limits_to_alarm(_), do: nil

  defp build_range(nil, nil), do: nil

  defp build_range(min, max) do
    range = %{}
    range = if min, do: Map.put(range, :min_inclusive, min), else: range
    range = if max, do: Map.put(range, :max_inclusive, max), else: range
    if map_size(range) > 0, do: range, else: nil
  end

  # ============================================================================
  # Command Import
  # ============================================================================

  defp import_command(ctx, command_data) do
    opcode = parse_opcode(command_data["opcode"])

    {:ok, meta_command} =
      %MetaCommand{}
      |> MetaCommand.changeset(%{
        organization_id: ctx.database.mission.organization_id,
        mission_id: ctx.database.mission_id,
        definition_set_id: ctx.definition_set.id,
        name: command_data["name"],
        description: command_data["description"],
        opcode: opcode,
        is_hazardous: command_data["is_hazardous"] || false,
        hazard_description: command_data["hazard_description"],
        requires_confirmation: command_data["requires_confirmation"] || false,
        allowed_phases: command_data["allowed_phases"] || []
      })
      |> Repo.insert()

    # Import parameters/arguments
    (command_data["parameters"] || [])
    |> Enum.with_index()
    |> Enum.each(fn {param_data, index} ->
      import_command_argument(ctx, meta_command, param_data, index)
    end)

    ctx
  end

  defp import_command_argument(_ctx, meta_command, param_data, display_order) do
    # Parse valid_values as strings
    valid_values =
      case param_data["valid_values"] do
        nil -> []
        values when is_list(values) -> Enum.map(values, &to_string/1)
        _ -> []
      end

    {:ok, _argument} =
      %Argument{}
      |> Argument.changeset(%{
        meta_command_id: meta_command.id,
        name: param_data["name"],
        description: param_data["description"],
        data_type_ref: param_data["data_type"],
        bit_offset: param_data["bit_offset"],
        bit_length: param_data["bit_length"],
        required: param_data["required"] != false,
        default_value: to_string_or_nil(param_data["default_value"]),
        min_value: param_data["min_value"],
        max_value: param_data["max_value"],
        valid_values: valid_values,
        display_order: display_order
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
