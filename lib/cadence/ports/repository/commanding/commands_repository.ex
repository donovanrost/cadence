defmodule Cadence.Ports.Repository.Commanding.CommandsRepository do
  @moduledoc """
  Port (behavior) defining the contract for MetaCommand persistence operations.

  This behavior abstracts MetaCommand lookups from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Commanding.EctoCommandsRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemoryCommandsRepository` - In-memory for tests

  ## Note on Queue Operations

  Queue operations (enqueue, dequeue, pause, resume) use the separate
  `Cadence.Ports.Repository.Commanding.QueueRepository` port. This repository
  only handles MetaCommand definition lookups.
  """

  alias Cadence.MissionDatabase.MetaCommand

  @type id :: String.t()
  @type definition_set_id :: String.t()
  @type name :: String.t()
  @type opcode :: non_neg_integer()
  @type opts :: keyword()
  @type error :: :not_found | term()

  # ============================================================================
  # MetaCommand Lookup Operations
  # ============================================================================

  @doc """
  Finds a MetaCommand by name within a definition set.

  Returns `{:ok, command}` if found (with arguments and verifiers preloaded),
  `{:error, :not_found}` otherwise.
  """
  @callback find_by_name(definition_set_id(), name()) ::
              {:ok, MetaCommand.t()} | {:error, :not_found}

  @doc """
  Finds a MetaCommand by ID.

  Returns `{:ok, command}` if found (with arguments and verifiers preloaded),
  `{:error, :not_found}` otherwise.
  """
  @callback find(id()) :: {:ok, MetaCommand.t()} | {:error, :not_found}

  @doc """
  Finds a MetaCommand by opcode within a definition set.

  Returns `{:ok, command}` if found (with arguments and verifiers preloaded),
  `{:error, :not_found}` otherwise.
  """
  @callback find_by_opcode(definition_set_id(), opcode()) ::
              {:ok, MetaCommand.t()} | {:error, :not_found}

  @doc """
  Lists all MetaCommands for a definition set.

  Excludes abstract commands by default.

  ## Options

  - `:include_abstract` - Include abstract commands (default: false)
  - `:preload` - Associations to preload (default: [:arguments])
  """
  @callback list(definition_set_id(), opts()) :: [MetaCommand.t()]

  @doc """
  Lists hazardous MetaCommands for a definition set.

  Returns only commands where `is_hazardous == true`.
  """
  @callback list_hazardous(definition_set_id()) :: [MetaCommand.t()]

  @doc """
  Counts MetaCommands in a definition set.

  Excludes abstract commands.
  """
  @callback count(definition_set_id()) :: non_neg_integer()

  @doc """
  Returns the configured commands repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :commands_repository,
      Cadence.Adapters.Persistence.Ecto.Commanding.EctoCommandsRepository
    )
  end
end
