defmodule Cadence.Ports.Repository.Procedures.ProcedureRepository do
  @moduledoc """
  Port (behavior) defining the contract for procedure persistence operations.

  This behavior abstracts the persistence layer from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Procedures.EctoProcedureRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemoryProcedureRepository` - In-memory for tests
  """

  alias Cadence.Domain.Procedures.Entities.Procedure
  alias Cadence.Domain.Procedures.Entities.ProcedureVersion

  @type id :: String.t()
  @type mission_id :: String.t()
  @type opts :: keyword()
  @type error :: :not_found | {:validation, map()} | term()

  # ============================================================================
  # Procedure Operations
  # ============================================================================

  @doc """
  Finds a procedure by ID.

  Returns `{:ok, procedure}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find(id()) :: {:ok, Procedure.t()} | {:error, :not_found}

  @doc """
  Finds a procedure by slug within a mission.
  """
  @callback find_by_slug(mission_id(), slug :: String.t()) :: {:ok, Procedure.t()} | {:error, :not_found}

  @doc """
  Persists a procedure (insert or update).
  """
  @callback save(Procedure.t()) :: {:ok, Procedure.t()} | {:error, error()}

  @doc """
  Lists procedures for a mission with optional filtering.

  ## Options

  - `:search` - Search by name/description
  - `:category` - Filter by category
  - `:limit` - Maximum number of results
  - `:offset` - Pagination offset
  """
  @callback list(mission_id(), opts()) :: [Procedure.t()]

  @doc """
  Deletes a procedure by ID.
  """
  @callback delete(id()) :: {:ok, Procedure.t()} | {:error, :not_found}

  # ============================================================================
  # Procedure Version Operations
  # ============================================================================

  @doc """
  Finds a procedure version by ID.
  """
  @callback find_version(id()) :: {:ok, ProcedureVersion.t()} | {:error, :not_found}

  @doc """
  Persists a procedure version.
  """
  @callback save_version(ProcedureVersion.t()) :: {:ok, ProcedureVersion.t()} | {:error, error()}

  @doc """
  Lists all versions for a procedure.

  ## Options

  - `:status` - Filter by version status
  - `:limit` - Maximum number of results
  """
  @callback list_versions(procedure_id :: id(), opts()) :: [ProcedureVersion.t()]

  @doc """
  Gets the current (approved) version of a procedure.
  """
  @callback get_current_version(procedure_id :: id()) :: {:ok, ProcedureVersion.t()} | {:error, :not_found}

  @doc """
  Returns the configured procedure repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(:cadence, :procedure_repository, Cadence.Adapters.Persistence.Ecto.Procedures.EctoProcedureRepository)
  end
end
