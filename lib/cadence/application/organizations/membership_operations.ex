defmodule Cadence.Application.Organizations.MembershipOperations do
  @moduledoc """
  Use case module for organization membership operations.

  Provides operations for managing organization memberships including
  creating, updating roles, and removing members.

  ## Usage

      # Add a member
      {:ok, membership} = MembershipOperations.create(%{
        user_id: user_id,
        organization_id: org_id,
        role: :member
      })

      # Change role
      {:ok, membership} = MembershipOperations.change_role(membership_id, :admin)

      # Remove member
      {:ok, membership} = MembershipOperations.delete(membership_id)
  """

  alias Cadence.Domain.Organizations.Entities.OrganizationMembership
  alias Cadence.Domain.Organizations.ValueObjects.MembershipRole
  alias Cadence.Ports.Repository.Organizations.{MembershipRepository, OrganizationRepository}

  @type membership_id :: String.t()
  @type user_id :: String.t()
  @type org_id :: String.t()
  @type attrs :: map()

  # Get configured repositories
  defp repo do
    MembershipRepository.impl()
  end

  defp org_repo do
    OrganizationRepository.impl()
  end

  @doc """
  Creates a new organization membership.

  ## Attributes

  Required:
  - `:user_id` - ID of the user
  - `:organization_id` - ID of the organization

  Optional:
  - `:role` - Role (:owner, :admin, :member), defaults to :member

  ## Examples

      {:ok, membership} = MembershipOperations.create(%{
        user_id: user_id,
        organization_id: org_id,
        role: :admin
      })
  """
  @spec create(attrs()) :: {:ok, OrganizationMembership.t()} | {:error, term()}
  def create(attrs) do
    with :ok <- check_user_quota(attrs[:organization_id]),
         {:ok, membership} <- OrganizationMembership.new(attrs) do
      repo().save(membership)
    end
  end

  @doc """
  Changes the role of an existing membership.

  ## Examples

      {:ok, membership} = MembershipOperations.change_role(membership_id, :admin)
  """
  @spec change_role(membership_id(), MembershipRole.t()) ::
          {:ok, OrganizationMembership.t()} | {:error, term()}
  def change_role(membership_id, new_role) do
    with {:ok, membership} <- repo().find(membership_id),
         {:ok, updated} <- OrganizationMembership.change_role(membership, new_role) do
      repo().save(updated)
    end
  end

  @doc """
  Promotes a member to a higher role.

  The new role must be higher in the hierarchy than the current role.
  """
  @spec promote(membership_id(), MembershipRole.t()) ::
          {:ok, OrganizationMembership.t()} | {:error, term()}
  def promote(membership_id, new_role) do
    with {:ok, membership} <- repo().find(membership_id),
         {:ok, promoted} <- OrganizationMembership.promote(membership, new_role) do
      repo().save(promoted)
    end
  end

  @doc """
  Demotes a member to a lower role.

  The new role must be lower in the hierarchy than the current role.
  """
  @spec demote(membership_id(), MembershipRole.t()) ::
          {:ok, OrganizationMembership.t()} | {:error, term()}
  def demote(membership_id, new_role) do
    with {:ok, membership} <- repo().find(membership_id),
         {:ok, demoted} <- OrganizationMembership.demote(membership, new_role) do
      repo().save(demoted)
    end
  end

  @doc """
  Deletes a membership.

  Prevents deleting the last owner of an organization.
  """
  @spec delete(membership_id()) :: {:ok, OrganizationMembership.t()} | {:error, term()}
  def delete(membership_id) do
    with {:ok, membership} <- repo().find(membership_id),
         :ok <- check_not_last_owner(membership) do
      repo().delete(membership_id)
    end
  end

  @doc """
  Finds a membership by ID.
  """
  @spec find(membership_id()) :: {:ok, OrganizationMembership.t()} | {:error, :not_found}
  def find(membership_id), do: repo().find(membership_id)

  @doc """
  Finds a user's membership in an organization.
  """
  @spec find_by_user_and_org(user_id(), org_id()) ::
          {:ok, OrganizationMembership.t()} | {:error, :not_found}
  def find_by_user_and_org(user_id, org_id), do: repo().find_by_user_and_org(user_id, org_id)

  @doc """
  Lists all memberships for an organization.

  ## Options

  - `:role` - Filter by role
  - `:limit` - Maximum results
  - `:offset` - Pagination offset
  - `:preload` - Associations to preload (e.g., [:user])
  """
  @spec list_for_organization(org_id(), keyword()) :: [OrganizationMembership.t()]
  def list_for_organization(org_id, opts \\ []), do: repo().list_for_organization(org_id, opts)

  @doc """
  Lists all memberships for a user.
  """
  @spec list_for_user(user_id(), keyword()) :: [OrganizationMembership.t()]
  def list_for_user(user_id, opts \\ []), do: repo().list_for_user(user_id, opts)

  @doc """
  Checks if a user has a membership in an organization.
  """
  @spec member?(user_id(), org_id()) :: boolean()
  def member?(user_id, org_id), do: repo().exists?(user_id, org_id)

  @doc """
  Gets the count of memberships for an organization.
  """
  @spec count_for_organization(org_id()) :: non_neg_integer()
  def count_for_organization(org_id), do: repo().count_for_organization(org_id)

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp check_user_quota(org_id) do
    with {:ok, org} <- org_repo().find(org_id) do
      user_count = org_repo().count_users(org_id)

      if user_count < org.quotas.max_users do
        :ok
      else
        {:error, :quota_exceeded}
      end
    end
  end

  defp check_not_last_owner(%OrganizationMembership{role: :owner, organization_id: org_id}) do
    owner_count = repo().count_owners(org_id)

    if owner_count > 1 do
      :ok
    else
      {:error, :cannot_remove_last_owner}
    end
  end

  defp check_not_last_owner(_membership), do: :ok
end
