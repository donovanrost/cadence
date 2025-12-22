defmodule Cadence.Ports.Repository.Targeting.TargetRepository do
  @moduledoc """
  Port (behavior) defining the contract for target persistence operations.

  This behavior abstracts the persistence layer from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Targeting.EctoTargetRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemoryTargetRepository` - In-memory for tests
  """

  alias Cadence.Domain.Targeting.Entities.Target

  @type id :: String.t()
  @type mission_id :: String.t()
  @type target_identifier :: String.t()
  @type opts :: keyword()
  @type error :: :not_found | {:validation, map()} | term()

  # ============================================================================
  # Core CRUD Operations
  # ============================================================================

  @doc """
  Finds a target by its ID, scoped to a mission.

  Returns `{:ok, target}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find(id(), mission_id()) :: {:ok, Target.t()} | {:error, :not_found}

  @doc """
  Finds a target by its ID without mission scoping.

  WARNING: Only use for internal operations where mission context is verified elsewhere.
  """
  @callback find_unscoped(id()) :: {:ok, Target.t()} | {:error, :not_found}

  @doc """
  Finds a target by its identifier within a mission.

  The identifier is a unique string like "SAT-1" or "GROUND-01".
  """
  @callback find_by_identifier(mission_id(), target_identifier()) :: {:ok, Target.t()} | {:error, :not_found}

  @doc """
  Persists a target (insert or update).

  Returns `{:ok, target}` with the persisted entity, or `{:error, reason}` on failure.
  """
  @callback save(Target.t()) :: {:ok, Target.t()} | {:error, error()}

  @doc """
  Deletes a target.

  Returns `{:ok, target}` with the deleted entity, or `{:error, :not_found}`.
  """
  @callback delete(id()) :: {:ok, Target.t()} | {:error, :not_found}

  # ============================================================================
  # Query Operations
  # ============================================================================

  @doc """
  Lists targets for a mission with optional filtering.

  ## Options

  - `:status` - Filter by status(es): "online", "offline", "standby", "fault"
  - `:type` - Filter by type(s): "spacecraft", "ground_station", "simulator", "relay"
  - `:limit` - Maximum number of results
  - `:offset` - Pagination offset
  - `:preload` - List of associations to preload
  """
  @callback list(mission_id(), opts()) :: [Target.t()]

  @doc """
  Lists targets using a specific definition set.
  """
  @callback list_by_definition_set(definition_set_id :: id()) :: [Target.t()]

  # ============================================================================
  # Circuit Breaker Operations
  # ============================================================================

  @doc """
  Updates the circuit breaker state for a target.

  Used for command safety - opens when too many failures occur.
  """
  @callback update_circuit_breaker(
              id(),
              %{
                optional(:status) => String.t(),
                optional(:failures) => non_neg_integer(),
                optional(:opened_at) => DateTime.t() | nil
              }
            ) :: {:ok, Target.t()} | {:error, error()}

  # ============================================================================
  # Definition Set Operations
  # ============================================================================

  @doc """
  Gets the definition set ID for a target by mission and identifier.
  """
  @callback get_definition_set_id(mission_id(), target_identifier()) :: {:ok, id()} | {:error, :not_found}

  @doc """
  Gets the definition set ID for a target by target ID.
  """
  @callback get_definition_set_id_by_target_id(id()) :: {:ok, id()} | {:error, :not_found}

  @doc """
  Finds a target with its definition set preloaded.
  """
  @callback find_with_definition_set(id()) :: {:ok, Target.t()} | {:error, :not_found}

  # ============================================================================
  # Implementation Helper
  # ============================================================================

  @doc """
  Returns the configured target repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :target_repository,
      Cadence.Adapters.Persistence.Ecto.Targeting.EctoTargetRepository
    )
  end
end
