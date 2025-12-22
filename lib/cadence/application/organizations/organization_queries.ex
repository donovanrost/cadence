defmodule Cadence.Application.Organizations.OrganizationQueries do
  @moduledoc """
  Use case module for querying organizations.

  Provides read-only operations for finding and listing organizations.

  ## Usage

      # Find by ID
      {:ok, org} = OrganizationQueries.find(org_id)

      # Find by slug
      {:ok, org} = OrganizationQueries.find_by_slug("acme-corp")

      # List all organizations
      orgs = OrganizationQueries.list()

      # Get organization stats
      stats = OrganizationQueries.get_stats(org_id)
  """

  alias Cadence.Domain.Organizations.Entities.Organization

  @type org_id :: String.t()
  @type opts :: keyword()

  # Get configured repository
  defp repo do
    Cadence.Ports.Repository.Organizations.OrganizationRepository.impl()
  end

  @doc """
  Finds an organization by ID.

  Returns `{:ok, organization}` if found, `{:error, :not_found}` otherwise.
  """
  @spec find(org_id()) :: {:ok, Organization.t()} | {:error, :not_found}
  def find(id), do: repo().find(id)

  @doc """
  Finds an organization by ID, raising if not found.
  """
  @spec find!(org_id()) :: Organization.t()
  def find!(id) do
    case find(id) do
      {:ok, org} -> org
      {:error, :not_found} -> raise "Organization not found: #{id}"
    end
  end

  @doc """
  Finds an organization by slug.

  Returns `{:ok, organization}` if found, `{:error, :not_found}` otherwise.
  """
  @spec find_by_slug(String.t()) :: {:ok, Organization.t()} | {:error, :not_found}
  def find_by_slug(slug), do: repo().find_by_slug(slug)

  @doc """
  Lists all organizations with optional filtering.

  ## Options

  - `:status` - Filter by status (:active, :suspended, :terminated)
  - `:tier` - Filter by subscription tier (:free, :pro, :enterprise)
  - `:search` - Search by name
  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Pagination offset

  ## Examples

      # All organizations
      OrganizationQueries.list()

      # Active organizations only
      OrganizationQueries.list(status: :active)

      # Search by name
      OrganizationQueries.list(search: "acme")
  """
  @spec list(opts()) :: [Organization.t()]
  def list(opts \\ []), do: repo().list(opts)

  @doc """
  Returns statistics about an organization's resource usage.

  ## Returns

  A map containing:
  - `:mission_count` - Current number of missions
  - `:mission_quota` - Maximum missions allowed
  - `:user_count` - Current number of users
  - `:user_quota` - Maximum users allowed
  - `:membership_count` - Number of organization memberships
  """
  @spec get_stats(org_id()) :: {:ok, map()} | {:error, :not_found}
  def get_stats(org_id) do
    with {:ok, org} <- find(org_id) do
      mission_count = repo().count_missions(org_id)
      user_count = repo().count_users(org_id)
      membership_count = repo().count_memberships(org_id)

      {:ok,
       %{
         mission_count: mission_count,
         mission_quota: org.quotas.max_missions,
         user_count: user_count,
         user_quota: org.quotas.max_users,
         membership_count: membership_count,
         storage_quota_gb: org.quotas.storage_quota_gb
       }}
    end
  end

  @doc """
  Checks if an organization is active.
  """
  @spec active?(org_id()) :: boolean()
  def active?(org_id) do
    case find(org_id) do
      {:ok, org} -> Organization.active?(org)
      {:error, :not_found} -> false
    end
  end

  @doc """
  Counts the number of missions in an organization.
  """
  @spec count_missions(org_id()) :: non_neg_integer()
  def count_missions(org_id), do: repo().count_missions(org_id)

  @doc """
  Counts the number of users in an organization.
  """
  @spec count_users(org_id()) :: non_neg_integer()
  def count_users(org_id), do: repo().count_users(org_id)

  @doc """
  Counts the number of targets in a mission.
  """
  @spec count_mission_targets(String.t()) :: non_neg_integer()
  def count_mission_targets(mission_id), do: repo().count_mission_targets(mission_id)
end
