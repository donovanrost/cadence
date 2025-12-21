defmodule Cadence.Organizations do
  @moduledoc """
  The Organizations context - boundary for organization-related operations.

  This context handles:
  - Organization CRUD operations
  - Organization membership management
  - Quota enforcement
  - Organization lifecycle
  """

  import Ecto.Query, warn: false
  alias Cadence.Repo

  alias Cadence.Organizations.Organization
  alias Cadence.Accounts.User

  ## Organization CRUD

  @doc """
  Returns the list of all organizations.
  """
  def list_organizations do
    Organization
    |> order_by([o], desc: o.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single organization.

  Raises `Ecto.NoResultsError` if the Organization does not exist.
  """
  def get_organization!(id), do: Repo.get!(Organization, id)

  @doc """
  Gets a single organization by slug.
  """
  def get_organization_by_slug(slug) do
    Repo.get_by(Organization, slug: slug)
  end

  @doc """
  Creates an organization.
  """
  def create_organization(attrs \\ %{}) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an organization.
  """
  def update_organization(%Organization{} = organization, attrs) do
    organization
    |> Organization.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an organization.

  This will cascade delete all missions, targets, and users.
  """
  def delete_organization(%Organization{} = organization) do
    Repo.delete(organization)
  end

  ## Organization Membership

  @doc """
  Lists all users in an organization.
  """
  def list_organization_users(%Organization{id: org_id}) do
    User
    |> where([u], u.organization_id == ^org_id)
    |> order_by([u], [u.role, u.email])
    |> Repo.all()
  end

  @doc """
  Gets a user by email within an organization.
  """
  def get_organization_user_by_email(%Organization{id: org_id}, email) do
    User
    |> where([u], u.organization_id == ^org_id and u.email == ^email)
    |> Repo.one()
  end

  @doc """
  Lists all organization memberships for an organization.
  """
  def list_organization_memberships(org_id) do
    alias Cadence.Organizations.OrganizationMembership

    OrganizationMembership
    |> where([om], om.organization_id == ^org_id)
    |> order_by([om], om.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates an organization membership.
  """
  def create_organization_membership(attrs \\ %{}) do
    alias Cadence.Organizations.OrganizationMembership

    %OrganizationMembership{}
    |> OrganizationMembership.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an organization membership.
  """
  def update_organization_membership(
        %Cadence.Organizations.OrganizationMembership{} = membership,
        attrs
      ) do
    alias Cadence.Organizations.OrganizationMembership

    membership
    |> OrganizationMembership.changeset(attrs)
    |> Repo.update()
  end

  ## Quota Management

  @doc """
  Checks if an organization can create a new mission.

  Returns `:ok` if under quota, `{:error, :quota_exceeded}` otherwise.
  """
  def check_mission_quota(%Organization{} = org) do
    mission_count = count_missions(org)

    if mission_count < org.max_missions do
      :ok
    else
      {:error, :quota_exceeded}
    end
  end

  @doc """
  Checks if a mission can create a new target.

  Returns `:ok` if under quota, `{:error, :quota_exceeded}` otherwise.
  """
  def check_target_quota(%Organization{} = org, mission_id) do
    target_count = count_mission_targets(mission_id)

    if target_count < org.max_targets_per_mission do
      :ok
    else
      {:error, :quota_exceeded}
    end
  end

  @doc """
  Checks if an organization can add a new user.

  Returns `:ok` if under quota, `{:error, :quota_exceeded}` otherwise.
  """
  def check_user_quota(%Organization{} = org) do
    user_count = count_users(org)

    if user_count < org.max_users do
      :ok
    else
      {:error, :quota_exceeded}
    end
  end

  @doc """
  Returns statistics about an organization's resource usage.
  """
  def get_organization_stats(%Organization{} = org) do
    %{
      mission_count: count_missions(org),
      mission_quota: org.max_missions,
      user_count: count_users(org),
      user_quota: org.max_users,
      storage_quota_gb: org.storage_quota_gb
    }
  end

  ## Private Functions

  defp count_missions(%Organization{id: org_id}) do
    Repo.one(
      from m in Cadence.Missions.Mission,
        where: m.organization_id == ^org_id,
        select: count(m.id)
    )
  end

  defp count_mission_targets(mission_id) do
    Repo.one(
      from t in Cadence.Targets.Target,
        where: t.mission_id == ^mission_id,
        select: count(t.id)
    )
  end

  defp count_users(%Organization{id: org_id}) do
    Repo.one(
      from u in User,
        where: u.organization_id == ^org_id,
        select: count(u.id)
    )
  end
end
