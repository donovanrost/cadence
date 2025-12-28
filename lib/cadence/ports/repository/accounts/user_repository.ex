defmodule Cadence.Ports.Repository.Accounts.UserRepository do
  @moduledoc """
  Port (behavior) defining the contract for user persistence operations.

  This behavior abstracts the persistence layer from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Accounts.EctoUserRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemoryUserRepository` - In-memory for tests
  """

  alias Cadence.Domain.Accounts.Entities.User

  @type id :: String.t()
  @type email :: String.t()
  @type org_id :: String.t()
  @type opts :: keyword()
  @type error :: :not_found | :email_already_taken | {:validation, map()} | term()

  # ============================================================================
  # User CRUD Operations
  # ============================================================================

  @doc """
  Finds a user by ID.

  Returns `{:ok, user}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find(id()) :: {:ok, User.t()} | {:error, :not_found}

  @doc """
  Finds a user by email address.

  Email lookup is case-insensitive.
  """
  @callback find_by_email(email()) :: {:ok, User.t()} | {:error, :not_found}

  @doc """
  Persists a user (insert or update).

  If the user has no ID, it will be inserted.
  If it has an ID, it will be updated.

  Returns `{:error, :email_already_taken}` if email uniqueness is violated.
  """
  @callback save(User.t()) :: {:ok, User.t()} | {:error, error()}

  @doc """
  Lists users with optional filtering.

  ## Options

  - `:organization_id` - Filter by organization
  - `:role` - Filter by role
  - `:system_admin` - Filter by system admin status
  - `:confirmed` - Filter by confirmation status
  - `:search` - Search by email
  - `:limit` - Maximum number of results
  - `:offset` - Pagination offset
  """
  @callback list(opts()) :: [User.t()]

  @doc """
  Deletes a user by ID.
  """
  @callback delete(id()) :: {:ok, User.t()} | {:error, :not_found}

  # ============================================================================
  # Organization-scoped Operations
  # ============================================================================

  @doc """
  Lists all users in an organization.
  """
  @callback list_for_organization(org_id(), opts()) :: [User.t()]

  @doc """
  Counts the number of users in an organization.
  """
  @callback count_for_organization(org_id()) :: non_neg_integer()

  @doc """
  Finds a user by email within an organization.
  """
  @callback find_by_email_in_organization(org_id(), email()) ::
              {:ok, User.t()} | {:error, :not_found}

  # ============================================================================
  # Email Uniqueness
  # ============================================================================

  @doc """
  Checks if an email is already taken.

  Optionally excludes a specific user ID from the check (for updates).
  """
  @callback email_taken?(email(), exclude_user_id :: id() | nil) :: boolean()

  # ============================================================================
  # Implementation Helper
  # ============================================================================

  @doc """
  Returns the configured user repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :user_repository,
      Cadence.Adapters.Persistence.Ecto.Accounts.EctoUserRepository
    )
  end
end
