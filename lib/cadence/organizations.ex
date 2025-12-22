defmodule Cadence.Organizations do
  @moduledoc """
  The Organizations context - facade for organization-related operations.

  This module delegates to hexagonal architecture application services while
  maintaining backward compatibility with existing code that uses Ecto schemas.

  ## Architecture

  This context is built on hexagonal architecture with the following layers:

  - **Domain**: `Cadence.Domain.Organizations.Entities.*` - Pure business entities
  - **Ports**: `Cadence.Ports.Repository.Organizations.*` - Repository contracts
  - **Adapters**: `Cadence.Adapters.Persistence.Ecto.Organizations.*` - Ecto implementations
  - **Application**: `Cadence.Application.Organizations.*` - Use case orchestration

  ## For New Code

  Prefer using the application services directly:

      alias Cadence.Application.Organizations.{OrganizationQueries, OrganizationOperations}

      # Find organization
      {:ok, org} = OrganizationQueries.find(id)

      # Create organization
      {:ok, org} = OrganizationOperations.create(%{name: "Acme", slug: "acme"})

  ## Legacy Support

  Functions in this module maintain backward compatibility with existing code
  that works with Ecto schemas directly.
  """

  import Ecto.Query, warn: false
  alias Cadence.Repo

  alias Cadence.Organizations.Organization
  alias Cadence.Organizations.OrganizationMembership
  alias Cadence.Accounts.User

  # Application services
  alias Cadence.Application.Organizations.OrganizationQueries
  alias Cadence.Application.Organizations.OrganizationOperations
  alias Cadence.Application.Organizations.MembershipOperations
  alias Cadence.Application.Organizations.QuotaService

  # ===========================================================================
  # Organization CRUD (Legacy API - Returns Ecto Schemas)
  # ===========================================================================

  @doc """
  Returns the list of all organizations.

  Returns Ecto schemas for backward compatibility.
  """
  def list_organizations do
    Organization
    |> order_by([o], desc: o.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single organization.

  Raises `Ecto.NoResultsError` if the Organization does not exist.
  Returns Ecto schema for backward compatibility.
  """
  def get_organization!(id), do: Repo.get!(Organization, id)

  @doc """
  Gets a single organization by slug.

  Returns Ecto schema for backward compatibility.
  """
  def get_organization_by_slug(slug) do
    Repo.get_by(Organization, slug: slug)
  end

  @doc """
  Creates an organization.

  Returns Ecto schema for backward compatibility.
  For new code, prefer `Cadence.Application.Organizations.OrganizationOperations.create/1`.
  """
  def create_organization(attrs \\ %{}) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an organization.

  Returns Ecto schema for backward compatibility.
  For new code, prefer `Cadence.Application.Organizations.OrganizationOperations.update/2`.
  """
  def update_organization(%Organization{} = organization, attrs) do
    organization
    |> Organization.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an organization.

  This will cascade delete all missions, targets, and users.
  Returns Ecto schema for backward compatibility.
  """
  def delete_organization(%Organization{} = organization) do
    Repo.delete(organization)
  end

  # ===========================================================================
  # Organization Membership (Legacy API - Returns Ecto Schemas)
  # ===========================================================================

  @doc """
  Lists all users in an organization.

  Returns Ecto schemas for backward compatibility.
  """
  def list_organization_users(%Organization{id: org_id}) do
    User
    |> where([u], u.organization_id == ^org_id)
    |> order_by([u], [u.role, u.email])
    |> Repo.all()
  end

  @doc """
  Gets a user by email within an organization.

  Returns Ecto schema for backward compatibility.
  """
  def get_organization_user_by_email(%Organization{id: org_id}, email) do
    User
    |> where([u], u.organization_id == ^org_id and u.email == ^email)
    |> Repo.one()
  end

  @doc """
  Lists all organization memberships for an organization.

  Returns Ecto schemas for backward compatibility.
  For new code, prefer `Cadence.Application.Organizations.MembershipOperations.list_for_organization/2`.
  """
  def list_organization_memberships(org_id) do
    OrganizationMembership
    |> where([om], om.organization_id == ^org_id)
    |> order_by([om], om.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates an organization membership.

  Returns Ecto schema for backward compatibility.
  For new code, prefer `Cadence.Application.Organizations.MembershipOperations.create/1`.
  """
  def create_organization_membership(attrs \\ %{}) do
    %OrganizationMembership{}
    |> OrganizationMembership.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an organization membership.

  Returns Ecto schema for backward compatibility.
  """
  def update_organization_membership(%OrganizationMembership{} = membership, attrs) do
    membership
    |> OrganizationMembership.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets a single organization membership.

  Raises `Ecto.NoResultsError` if the OrganizationMembership does not exist.
  Returns Ecto schema for backward compatibility.
  """
  def get_organization_membership!(id) do
    Repo.get!(OrganizationMembership, id)
  end

  @doc """
  Deletes an organization membership.

  Returns Ecto schema for backward compatibility.
  """
  def delete_organization_membership(%OrganizationMembership{} = membership) do
    Repo.delete(membership)
  end

  @doc """
  Lists all organization memberships for an organization, preloaded with users.

  Returns Ecto schemas for backward compatibility.
  """
  def list_organization_memberships_with_users(org_id) do
    OrganizationMembership
    |> where([om], om.organization_id == ^org_id)
    |> order_by([om], om.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  # ===========================================================================
  # Quota Management (Delegates to QuotaService)
  # ===========================================================================

  @doc """
  Checks if an organization can create a new mission.

  Returns `:ok` if under quota, `{:error, :quota_exceeded}` otherwise.

  For new code, prefer `Cadence.Application.Organizations.QuotaService.check_mission_quota/1`.
  """
  def check_mission_quota(%Organization{id: org_id}) do
    QuotaService.check_mission_quota(org_id)
  end

  @doc """
  Checks if a mission can create a new target.

  Returns `:ok` if under quota, `{:error, :quota_exceeded}` otherwise.

  For new code, prefer `Cadence.Application.Organizations.QuotaService.check_target_quota/2`.
  """
  def check_target_quota(%Organization{id: org_id}, mission_id) do
    QuotaService.check_target_quota(org_id, mission_id)
  end

  @doc """
  Checks if an organization can add a new user.

  Returns `:ok` if under quota, `{:error, :quota_exceeded}` otherwise.

  For new code, prefer `Cadence.Application.Organizations.QuotaService.check_user_quota/1`.
  """
  def check_user_quota(%Organization{id: org_id}) do
    QuotaService.check_user_quota(org_id)
  end

  @doc """
  Returns statistics about an organization's resource usage.

  For new code, prefer `Cadence.Application.Organizations.OrganizationQueries.get_stats/1`.
  """
  def get_organization_stats(%Organization{id: org_id} = org) do
    case OrganizationQueries.get_stats(org_id) do
      {:ok, stats} ->
        # Convert to legacy format (with org-level fields for compatibility)
        %{
          mission_count: stats.mission_count,
          mission_quota: org.max_missions,
          user_count: stats.user_count,
          user_quota: org.max_users,
          storage_quota_gb: org.storage_quota_gb
        }

      {:error, _} ->
        # Fallback to legacy implementation if not found
        %{
          mission_count: 0,
          mission_quota: org.max_missions,
          user_count: 0,
          user_quota: org.max_users,
          storage_quota_gb: org.storage_quota_gb
        }
    end
  end

  # ===========================================================================
  # Domain Entity Access (New API - Returns Domain Entities)
  # ===========================================================================

  @doc """
  Finds an organization and returns a domain entity.

  Use this when you want to work with the hexagonal architecture.
  """
  @spec find_organization(String.t()) ::
          {:ok, Cadence.Domain.Organizations.Entities.Organization.t()} | {:error, :not_found}
  def find_organization(id), do: OrganizationQueries.find(id)

  @doc """
  Lists organizations as domain entities.
  """
  @spec list_organizations_as_entities(keyword()) ::
          [Cadence.Domain.Organizations.Entities.Organization.t()]
  def list_organizations_as_entities(opts \\ []), do: OrganizationQueries.list(opts)

  @doc """
  Creates an organization using the hexagonal architecture.

  Returns a domain entity.
  """
  @spec create_organization_entity(map()) ::
          {:ok, Cadence.Domain.Organizations.Entities.Organization.t()} | {:error, term()}
  def create_organization_entity(attrs), do: OrganizationOperations.create(attrs)

  @doc """
  Updates an organization using the hexagonal architecture.

  Returns a domain entity.
  """
  @spec update_organization_entity(String.t(), map()) ::
          {:ok, Cadence.Domain.Organizations.Entities.Organization.t()} | {:error, term()}
  def update_organization_entity(org_id, attrs), do: OrganizationOperations.update(org_id, attrs)

  @doc """
  Finds a membership and returns a domain entity.
  """
  @spec find_membership(String.t()) ::
          {:ok, Cadence.Domain.Organizations.Entities.OrganizationMembership.t()}
          | {:error, :not_found}
  def find_membership(id), do: MembershipOperations.find(id)

  @doc """
  Creates a membership using the hexagonal architecture.

  Returns a domain entity.
  """
  @spec create_membership_entity(map()) ::
          {:ok, Cadence.Domain.Organizations.Entities.OrganizationMembership.t()}
          | {:error, term()}
  def create_membership_entity(attrs), do: MembershipOperations.create(attrs)
end
