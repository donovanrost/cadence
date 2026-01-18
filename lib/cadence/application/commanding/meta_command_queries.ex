defmodule Cadence.Application.Commanding.MetaCommandQueries do
  @moduledoc """
  Use case module for querying MetaCommand definitions.

  MetaCommands are command definitions stored in the MissionDatabase
  as part of a DefinitionSet. Each target references a specific
  DefinitionSet version.

  ## Usage

      # Get command by name
      cmd = MetaCommandQueries.get_by_name(definition_set_id, "SAFE_MODE")

      # List all commands
      commands = MetaCommandQueries.list(definition_set_id)

      # Get hazardous commands
      hazardous = MetaCommandQueries.list_hazardous(definition_set_id)
  """

  import Ecto.Query

  alias Cadence.MissionDatabase.MetaCommand
  alias Cadence.Repo

  @type definition_set_id :: String.t()

  @doc """
  Gets a MetaCommand by name for a DefinitionSet.

  Preloads arguments and verifiers for command execution.
  """
  @spec get_by_name(definition_set_id(), String.t()) :: MetaCommand.t() | nil
  def get_by_name(definition_set_id, name) do
    from(c in MetaCommand,
      where: c.definition_set_id == ^definition_set_id,
      where: c.name == ^name,
      preload: [:arguments, :verifiers]
    )
    |> Repo.one()
  end

  @doc """
  Gets a MetaCommand by ID.

  Preloads arguments and verifiers.
  """
  @spec get_by_id(String.t()) :: MetaCommand.t() | nil
  def get_by_id(id) do
    from(c in MetaCommand,
      where: c.id == ^id,
      preload: [:arguments, :verifiers]
    )
    |> Repo.one()
  end

  @doc """
  Gets a MetaCommand by ID, raising if not found.
  """
  @spec get_by_id!(String.t()) :: MetaCommand.t()
  def get_by_id!(id) do
    case get_by_id(id) do
      nil -> raise "MetaCommand not found: #{id}"
      cmd -> cmd
    end
  end

  @doc """
  Gets a MetaCommand by opcode for a DefinitionSet.

  Preloads arguments and verifiers.
  """
  @spec get_by_opcode(definition_set_id(), non_neg_integer()) :: MetaCommand.t() | nil
  def get_by_opcode(definition_set_id, opcode) do
    from(c in MetaCommand,
      where: c.definition_set_id == ^definition_set_id,
      where: c.opcode == ^opcode,
      preload: [:arguments, :verifiers]
    )
    |> Repo.one()
  end

  @doc """
  Lists all MetaCommands for a DefinitionSet.

  Preloads arguments and verifiers.
  """
  @spec list(definition_set_id()) :: [MetaCommand.t()]
  def list(definition_set_id) do
    from(c in MetaCommand,
      where: c.definition_set_id == ^definition_set_id,
      order_by: [asc: c.name],
      preload: [:arguments, :verifiers]
    )
    |> Repo.all()
  end

  @doc """
  Lists hazardous MetaCommands for a DefinitionSet.
  """
  @spec list_hazardous(definition_set_id()) :: [MetaCommand.t()]
  def list_hazardous(definition_set_id) do
    from(c in MetaCommand,
      where: c.definition_set_id == ^definition_set_id,
      where: c.is_hazardous == true,
      order_by: [asc: c.name],
      preload: [:arguments, :verifiers]
    )
    |> Repo.all()
  end

  @doc """
  Lists MetaCommands allowed for a specific mission phase.
  """
  @spec list_for_phase(definition_set_id(), String.t()) :: [MetaCommand.t()]
  def list_for_phase(definition_set_id, phase) do
    list(definition_set_id)
    |> Enum.filter(fn cmd ->
      is_nil(cmd.allowed_phases) or phase in cmd.allowed_phases
    end)
  end

  @doc """
  Counts MetaCommands for a DefinitionSet.
  """
  @spec count(definition_set_id()) :: non_neg_integer()
  def count(definition_set_id) do
    from(c in MetaCommand,
      where: c.definition_set_id == ^definition_set_id,
      select: count(c.id)
    )
    |> Repo.one()
  end
end
