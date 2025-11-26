defmodule Cadence.Commands do
  @moduledoc """
  Context module for managing spacecraft command definitions.

  Commands are part of the unified C&T database (DefinitionSet), versioned
  alongside telemetry packets. This context provides CRUD operations for
  command definitions and parameters.

  ## Safety Features

  Commands support safety metadata per ADR-004:

  - Hazardous command flagging
  - Operator confirmation requirements
  - Mission phase restrictions

  ## Example

      # List commands for a mission's active DefinitionSet
      commands = Commands.list_commands(mission_id)

      # Get a specific command by name
      {:ok, cmd} = Commands.get_command_by_name(mission_id, "SAFE_MODE")

      # Validate command arguments
      :ok = Commands.validate_parameters(cmd, %{"target_temp" => 25.0})
  """

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Commands.{CommandDefinition, CommandParameter}
  alias Cadence.Telemetry.Database.DefinitionSet

  # ============================================================================
  # Command Definition Operations
  # ============================================================================

  @doc """
  Creates a command definition.
  """
  def create_command(attrs) do
    %CommandDefinition{}
    |> CommandDefinition.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a command definition.

  Note: Commands within a published DefinitionSet should be treated as immutable.
  Use this only for draft/unpublished definition sets.
  """
  def update_command(%CommandDefinition{} = command, attrs) do
    command
    |> CommandDefinition.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a command definition and its parameters.
  """
  def delete_command(%CommandDefinition{} = command) do
    Repo.delete(command)
  end

  @doc """
  Gets a command definition by ID.
  """
  def get_command(id) do
    CommandDefinition
    |> Repo.get(id)
    |> Repo.preload(:command_parameters)
  end

  @doc """
  Gets a command definition by name for a mission.

  Looks up the command in the active DefinitionSet for the mission.
  """
  def get_command_by_name(mission_id, name) do
    case DefinitionSet.get_active(mission_id) do
      nil ->
        # Fall back to legacy query (no definition_set)
        from(c in CommandDefinition,
          where: c.mission_id == ^mission_id,
          where: c.name == ^name,
          where: is_nil(c.definition_set_id),
          preload: :command_parameters,
          limit: 1
        )
        |> Repo.one()

      %DefinitionSet{id: definition_set_id} ->
        from(c in CommandDefinition,
          where: c.definition_set_id == ^definition_set_id,
          where: c.name == ^name,
          preload: :command_parameters,
          limit: 1
        )
        |> Repo.one()
    end
  end

  @doc """
  Gets a command definition by opcode for a mission.
  """
  def get_command_by_opcode(mission_id, opcode) do
    case DefinitionSet.get_active(mission_id) do
      nil ->
        from(c in CommandDefinition,
          where: c.mission_id == ^mission_id,
          where: c.opcode == ^opcode,
          where: is_nil(c.definition_set_id),
          preload: :command_parameters,
          limit: 1
        )
        |> Repo.one()

      %DefinitionSet{id: definition_set_id} ->
        from(c in CommandDefinition,
          where: c.definition_set_id == ^definition_set_id,
          where: c.opcode == ^opcode,
          preload: :command_parameters,
          limit: 1
        )
        |> Repo.one()
    end
  end

  @doc """
  Lists all commands for a mission's active DefinitionSet.
  """
  def list_commands(mission_id) do
    case DefinitionSet.get_active(mission_id) do
      nil ->
        # Fall back to legacy query
        from(c in CommandDefinition,
          where: c.mission_id == ^mission_id,
          where: is_nil(c.definition_set_id),
          order_by: [asc: c.name],
          preload: :command_parameters
        )
        |> Repo.all()

      %DefinitionSet{id: definition_set_id} ->
        from(c in CommandDefinition,
          where: c.definition_set_id == ^definition_set_id,
          order_by: [asc: c.name],
          preload: :command_parameters
        )
        |> Repo.all()
    end
  end

  @doc """
  Lists all commands for a specific DefinitionSet.
  """
  def list_commands_for_definition_set(definition_set_id) do
    from(c in CommandDefinition,
      where: c.definition_set_id == ^definition_set_id,
      order_by: [asc: c.name],
      preload: :command_parameters
    )
    |> Repo.all()
  end

  @doc """
  Lists hazardous commands for a mission.
  """
  def list_hazardous_commands(mission_id) do
    case DefinitionSet.get_active(mission_id) do
      nil ->
        from(c in CommandDefinition,
          where: c.mission_id == ^mission_id,
          where: c.is_hazardous == true,
          where: is_nil(c.definition_set_id),
          order_by: [asc: c.name],
          preload: :command_parameters
        )
        |> Repo.all()

      %DefinitionSet{id: definition_set_id} ->
        from(c in CommandDefinition,
          where: c.definition_set_id == ^definition_set_id,
          where: c.is_hazardous == true,
          order_by: [asc: c.name],
          preload: :command_parameters
        )
        |> Repo.all()
    end
  end

  @doc """
  Lists commands allowed in a specific mission phase.
  """
  def list_commands_for_phase(mission_id, phase) do
    list_commands(mission_id)
    |> Enum.filter(&CommandDefinition.allowed_in_phase?(&1, phase))
  end

  # ============================================================================
  # Command Parameter Operations
  # ============================================================================

  @doc """
  Creates a command parameter.
  """
  def create_parameter(attrs) do
    %CommandParameter{}
    |> CommandParameter.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a command parameter.
  """
  def update_parameter(%CommandParameter{} = parameter, attrs) do
    parameter
    |> CommandParameter.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a command parameter.
  """
  def delete_parameter(%CommandParameter{} = parameter) do
    Repo.delete(parameter)
  end

  @doc """
  Gets a command parameter by ID.
  """
  def get_parameter(id) do
    Repo.get(CommandParameter, id)
  end

  @doc """
  Lists parameters for a command, ordered by display_order.
  """
  def list_parameters(command_definition_id) do
    from(p in CommandParameter,
      where: p.command_definition_id == ^command_definition_id,
      order_by: [asc: p.display_order, asc: p.name]
    )
    |> Repo.all()
  end

  # ============================================================================
  # Validation
  # ============================================================================

  @doc """
  Validates command arguments against parameter definitions.

  Returns `:ok` if all validations pass, or `{:error, errors}` with a list
  of validation errors.

  ## Example

      case Commands.validate_parameters(command, %{"target_temp" => 25.0}) do
        :ok -> send_command(command, args)
        {:error, errors} -> handle_validation_errors(errors)
      end
  """
  def validate_parameters(%CommandDefinition{} = command, args) when is_map(args) do
    command = Repo.preload(command, :command_parameters)

    errors =
      command.command_parameters
      |> Enum.flat_map(fn param ->
        validate_single_parameter(param, args)
      end)

    # Check for unknown parameters
    known_names = MapSet.new(command.command_parameters, & &1.name)

    unknown_errors =
      args
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(known_names, to_string(&1)))
      |> Enum.map(fn name -> {name, "unknown parameter"} end)

    all_errors = errors ++ unknown_errors

    if Enum.empty?(all_errors) do
      :ok
    else
      {:error, all_errors}
    end
  end

  defp validate_single_parameter(%CommandParameter{} = param, args) do
    value = Map.get(args, param.name) || Map.get(args, String.to_atom(param.name))

    cond do
      # Required parameter missing
      CommandParameter.required?(param) && is_nil(value) ->
        [{param.name, "is required"}]

      # Optional parameter not provided - OK
      is_nil(value) ->
        []

      # Validate the provided value
      true ->
        case CommandParameter.validate_value(param, value) do
          :ok -> []
          {:error, reason} -> [{param.name, reason}]
        end
    end
  end

  # ============================================================================
  # Bulk Operations (for importers)
  # ============================================================================

  @doc """
  Creates a command definition with parameters in a single transaction.
  """
  def create_command_with_parameters(command_attrs, parameters_attrs) do
    Repo.transaction(fn ->
      case create_command(command_attrs) do
        {:ok, command} ->
          parameters =
            Enum.map(parameters_attrs, fn param_attrs ->
              param_attrs = Map.put(param_attrs, :command_definition_id, command.id)

              case create_parameter(param_attrs) do
                {:ok, param} -> param
                {:error, changeset} -> Repo.rollback({:parameter_error, changeset})
              end
            end)

          %{command | command_parameters: parameters}

        {:error, changeset} ->
          Repo.rollback({:command_error, changeset})
      end
    end)
  end

  @doc """
  Counts commands in a DefinitionSet.
  """
  def count_commands(definition_set_id) do
    from(c in CommandDefinition,
      where: c.definition_set_id == ^definition_set_id,
      select: count(c.id)
    )
    |> Repo.one()
  end
end
