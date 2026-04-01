defmodule Cadence.Ports.Repository.Organizations.MembershipRepository do
  @moduledoc """
  Port (behavior) defining the contract for organization membership persistence operations.

  This behavior abstracts the persistence layer from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Organizations.EctoMembershipRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemoryMembershipRepository` - In-memory for tests
  """

  alias Cadence.Domain.Organizations.Entities.OrganizationMembership

  @type id :: String.t()
  @type user_id :: String.t()
  @type organization_id :: String.t()
  @type opts :: keyword()
  @type error :: :not_found | {:validation, map()} | :already_exists | term()

  # ============================================================================
  # Membership CRUD Operations
  # ============================================================================

  @doc """
  Finds a membership by ID.

  Returns `{:ok, membership}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find(id()) :: {:ok, OrganizationMembership.t()} | {:error, :not_found}

  @doc """
  Finds a membership by user and organization.
  """
  @callback find_by_user_and_org(user_id(), organization_id()) ::
              {:ok, OrganizationMembership.t()} | {:error, :not_found}

  @doc """
  Persists a membership (insert or update).

  If the membership has no ID, it will be inserted.
  If it has an ID, it will be updated.
  """
  @callback save(OrganizationMembership.t()) ::
              {:ok, OrganizationMembership.t()} | {:error, error()}

  @doc """
  Lists memberships for an organization with optional filtering.

  ## Options

  - `:role` - Filter by role (:owner, :admin, :member)
  - `:limit` - Maximum number of results
  - `:offset` - Pagination offset
  - `:preload` - List of associations to preload (e.g., [:user])
  """
  @callback list_for_organization(organization_id(), opts()) :: [OrganizationMembership.t()]

  @doc """
  Lists memberships for a user.
  """
  @callback list_for_user(user_id(), opts()) :: [OrganizationMembership.t()]

  @doc """
  Deletes a membership by ID.
  """
  @callback delete(id()) :: {:ok, OrganizationMembership.t()} | {:error, :not_found}

  @doc """
  Deletes all memberships for a user.
  """
  @callback delete_all_for_user(user_id()) :: :ok

  @doc """
  Deletes all memberships for an organization.
  """
  @callback delete_all_for_organization(organization_id()) :: :ok

  # ============================================================================
  # Query Operations
  # ============================================================================

  @doc """
  Checks if a user has a membership in an organization.
  """
  @callback exists?(user_id(), organization_id()) :: boolean()

  @doc """
  Counts the number of memberships for an organization.
  """
  @callback count_for_organization(organization_id()) :: non_neg_integer()

  @doc """
  Counts the number of owners in an organization.
  Used to prevent deleting the last owner.
  """
  @callback count_owners(organization_id()) :: non_neg_integer()

  # ============================================================================
  # Implementation Helper
  # ============================================================================

  @doc """
  Returns the configured membership repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :membership_repository,
      Cadence.Adapters.Persistence.Ecto.Organizations.EctoMembershipRepository
    )
  end
end
