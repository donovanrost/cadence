defmodule Cadence.Application.Organizations.OrganizationOperations do
  @moduledoc """
  Use case module for organization write operations.

  Provides operations for creating, updating, and managing organizations.

  ## Usage

      # Create an organization
      {:ok, org} = OrganizationOperations.create(%{name: "Acme", slug: "acme"})

      # Update an organization
      {:ok, org} = OrganizationOperations.update(org_id, %{name: "Acme Corp"})

      # Suspend an organization
      {:ok, org} = OrganizationOperations.suspend(org_id)
  """

  alias Cadence.Application.Organizations.OrganizationQueries
  alias Cadence.Domain.Organizations.Entities.Organization
  alias Cadence.Ports.Repository.Organizations.OrganizationRepository

  @type org_id :: String.t()
  @type attrs :: map()

  # Get configured repository
  defp repo do
    OrganizationRepository.impl()
  end

  @doc """
  Creates a new organization.

  ## Attributes

  Required:
  - `:name` - Organization display name
  - `:slug` - URL-safe identifier (lowercase alphanumeric with hyphens)

  Optional:
  - `:subscription_tier` - Tier (:free, :pro, :enterprise), defaults to :free
  - `:max_missions` - Mission quota override
  - `:max_users` - User quota override
  - `:settings` - Organization settings map
  - `:metadata` - Additional metadata

  ## Examples

      {:ok, org} = OrganizationOperations.create(%{
        name: "Acme Corp",
        slug: "acme-corp"
      })

      {:ok, org} = OrganizationOperations.create(%{
        name: "Enterprise Org",
        slug: "enterprise",
        subscription_tier: :enterprise
      })
  """
  @spec create(attrs()) :: {:ok, Organization.t()} | {:error, term()}
  def create(attrs) do
    with {:ok, org} <- Organization.new(attrs) do
      repo().save(org)
    end
  end

  @doc """
  Updates an existing organization.

  ## Examples

      {:ok, org} = OrganizationOperations.update(org_id, %{name: "New Name"})
  """
  @spec update(org_id(), attrs()) :: {:ok, Organization.t()} | {:error, term()}
  def update(org_id, attrs) do
    with {:ok, org} <- OrganizationQueries.find(org_id),
         {:ok, updated} <- Organization.update(org, attrs) do
      repo().save(updated)
    end
  end

  @doc """
  Updates an organization's quotas.

  ## Examples

      {:ok, org} = OrganizationOperations.update_quotas(org_id, %{
        max_missions: 50,
        max_users: 100
      })
  """
  @spec update_quotas(org_id(), attrs()) :: {:ok, Organization.t()} | {:error, term()}
  def update_quotas(org_id, quota_attrs) do
    with {:ok, org} <- OrganizationQueries.find(org_id),
         {:ok, updated} <- Organization.update_quotas(org, quota_attrs) do
      repo().save(updated)
    end
  end

  @doc """
  Suspends an organization.

  A suspended organization cannot perform operations but data is preserved.
  """
  @spec suspend(org_id()) :: {:ok, Organization.t()} | {:error, term()}
  def suspend(org_id) do
    with {:ok, org} <- OrganizationQueries.find(org_id),
         {:ok, suspended} <- Organization.suspend(org) do
      repo().save(suspended)
    end
  end

  @doc """
  Reactivates a suspended organization.
  """
  @spec reactivate(org_id()) :: {:ok, Organization.t()} | {:error, term()}
  def reactivate(org_id) do
    with {:ok, org} <- OrganizationQueries.find(org_id),
         {:ok, reactivated} <- Organization.reactivate(org) do
      repo().save(reactivated)
    end
  end

  @doc """
  Terminates an organization permanently.

  This is an irreversible operation. Consider suspending first.
  """
  @spec terminate(org_id()) :: {:ok, Organization.t()} | {:error, term()}
  def terminate(org_id) do
    with {:ok, org} <- OrganizationQueries.find(org_id),
         {:ok, terminated} <- Organization.terminate(org) do
      repo().save(terminated)
    end
  end

  @doc """
  Deletes an organization.

  This will cascade delete all related resources.
  """
  @spec delete(org_id()) :: {:ok, Organization.t()} | {:error, term()}
  def delete(org_id), do: repo().delete(org_id)
end
