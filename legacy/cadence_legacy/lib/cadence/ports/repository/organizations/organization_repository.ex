defmodule Cadence.Ports.Repository.Organizations.OrganizationRepository do
  @moduledoc """
  Port (behavior) defining the contract for organization persistence operations.

  This behavior abstracts the persistence layer from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Organizations.EctoOrganizationRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemoryOrganizationRepository` - In-memory for tests
  """

  alias Cadence.Domain.Organizations.Entities.Organization

  @type id :: String.t()
  @type slug :: String.t()
  @type opts :: keyword()
  @type error :: :not_found | {:validation, map()} | term()

  # ============================================================================
  # Organization CRUD Operations
  # ============================================================================

  @doc """
  Finds an organization by ID.

  Returns `{:ok, organization}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find(id()) :: {:ok, Organization.t()} | {:error, :not_found}

  @doc """
  Finds an organization by slug.
  """
  @callback find_by_slug(slug()) :: {:ok, Organization.t()} | {:error, :not_found}

  @doc """
  Persists an organization (insert or update).

  If the organization has no ID, it will be inserted.
  If it has an ID, it will be updated.
  """
  @callback save(Organization.t()) :: {:ok, Organization.t()} | {:error, error()}

  @doc """
  Lists all organizations with optional filtering.

  ## Options

  - `:status` - Filter by status (:active, :suspended, :terminated)
  - `:tier` - Filter by subscription tier
  - `:search` - Search by name
  - `:limit` - Maximum number of results
  - `:offset` - Pagination offset
  """
  @callback list(opts()) :: [Organization.t()]

  @doc """
  Deletes an organization by ID.
  """
  @callback delete(id()) :: {:ok, Organization.t()} | {:error, :not_found}

  # ============================================================================
  # Counting Operations (for quota checks)
  # ============================================================================

  @doc """
  Counts the number of missions in an organization.
  """
  @callback count_missions(id()) :: non_neg_integer()

  @doc """
  Counts the number of targets in a specific mission.
  """
  @callback count_mission_targets(mission_id :: id()) :: non_neg_integer()

  @doc """
  Counts the number of users in an organization.
  """
  @callback count_users(id()) :: non_neg_integer()

  @doc """
  Counts the number of memberships in an organization.
  """
  @callback count_memberships(id()) :: non_neg_integer()

  # ============================================================================
  # Implementation Helper
  # ============================================================================

  @doc """
  Returns the configured organization repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :organization_repository,
      Cadence.Adapters.Persistence.Ecto.Organizations.EctoOrganizationRepository
    )
  end
end
