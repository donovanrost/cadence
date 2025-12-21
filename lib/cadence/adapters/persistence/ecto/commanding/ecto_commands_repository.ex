defmodule Cadence.Adapters.Persistence.Ecto.Commanding.EctoCommandsRepository do
  @moduledoc """
  Ecto-based implementation of the CommandsRepository port.

  This adapter provides MetaCommand lookups using PostgreSQL via Ecto.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :commands_repository, Cadence.Adapters.Persistence.Ecto.Commanding.EctoCommandsRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Commanding.CommandsRepository.impl()
      {:ok, command} = repo.find_by_name(definition_set_id, "POWER_ON")
  """

  @behaviour Cadence.Ports.Repository.Commanding.CommandsRepository

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.MissionDatabase.MetaCommand

  # ============================================================================
  # MetaCommand Lookup Operations
  # ============================================================================

  @impl true
  def find_by_name(definition_set_id, name) do
    query =
      from c in MetaCommand,
        where: c.definition_set_id == ^definition_set_id,
        where: c.name == ^name,
        preload: [:arguments, :verifiers],
        limit: 1

    case Repo.one(query) do
      nil -> {:error, :not_found}
      command -> {:ok, command}
    end
  end

  @impl true
  def find(id) do
    case Repo.get(MetaCommand, id) do
      nil ->
        {:error, :not_found}

      command ->
        {:ok, Repo.preload(command, [:arguments, :verifiers])}
    end
  end

  @impl true
  def find_by_opcode(definition_set_id, opcode) do
    query =
      from c in MetaCommand,
        where: c.definition_set_id == ^definition_set_id,
        where: c.opcode == ^opcode,
        preload: [:arguments, :verifiers],
        limit: 1

    case Repo.one(query) do
      nil -> {:error, :not_found}
      command -> {:ok, command}
    end
  end

  @impl true
  def list(definition_set_id, opts \\ []) do
    include_abstract = Keyword.get(opts, :include_abstract, false)
    preloads = Keyword.get(opts, :preload, [:arguments])

    query =
      from c in MetaCommand,
        where: c.definition_set_id == ^definition_set_id,
        order_by: [asc: c.name]

    query =
      if include_abstract do
        query
      else
        from c in query, where: c.abstract == false or is_nil(c.abstract)
      end

    query
    |> preload(^preloads)
    |> Repo.all()
  end

  @impl true
  def list_hazardous(definition_set_id) do
    query =
      from c in MetaCommand,
        where: c.definition_set_id == ^definition_set_id,
        where: c.is_hazardous == true,
        order_by: [asc: c.name],
        preload: [:arguments]

    Repo.all(query)
  end

  @impl true
  def count(definition_set_id) do
    query =
      from c in MetaCommand,
        where: c.definition_set_id == ^definition_set_id,
        where: c.abstract == false or is_nil(c.abstract),
        select: count(c.id)

    Repo.one(query) || 0
  end
end
