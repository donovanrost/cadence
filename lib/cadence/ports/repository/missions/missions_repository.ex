defmodule Cadence.Ports.Repository.Missions.MissionsRepository do
  @moduledoc """
  Port (behavior) defining the contract for mission persistence operations.

  This behavior abstracts mission storage from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Missions.EctoMissionsRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemoryMissionsRepository` - In-memory for tests

  ## Note on Lifecycle Operations

  Mission lifecycle operations (start, stop, activate, deactivate) are orchestration
  concerns and remain in the Missions context. This repository only handles persistence.
  """

  alias Cadence.Domain.Missions.Entities.Mission
  alias Cadence.Domain.Missions.Entities.MissionMembership

  @type id :: String.t()
  @type organization_id :: String.t()
  @type user_id :: String.t()
  @type role :: String.t()
  @type opts :: keyword()
  @type error :: :not_found | {:validation, map()} | term()

  # ===========================================================================
  # Mission Operations
  # ===========================================================================

  @doc """
  Finds a mission by ID (unscoped).

  Returns `{:ok, mission}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find(id()) :: {:ok, Mission.t()} | {:error, :not_found}

  @doc """
  Finds a mission by ID scoped to an organization.

  Returns `{:ok, mission}` if found and belongs to the organization,
  `{:error, :not_found}` otherwise.
  """
  @callback find_by_org(id(), organization_id()) :: {:ok, Mission.t()} | {:error, :not_found}

  @doc """
  Lists all missions for an organization.

  ## Options

  - `:status` - Filter by status (e.g., "active", "inactive")
  - `:order` - Sort order (default: inserted_at DESC)
  - `:limit` - Maximum number of results
  """
  @callback list(organization_id(), opts()) :: [Mission.t()]

  @doc """
  Persists a mission (insert or update).

  Returns `{:ok, mission}` with the persisted entity, or `{:error, reason}` on failure.
  """
  @callback save(Mission.t()) :: {:ok, Mission.t()} | {:error, error()}

  @doc """
  Deletes a mission by ID.

  Returns `{:ok, mission}` if deleted, `{:error, :not_found}` if not found.
  """
  @callback delete(id()) :: {:ok, Mission.t()} | {:error, :not_found}

  # ===========================================================================
  # Mission Membership Operations
  # ===========================================================================

  @doc """
  Finds a mission membership by ID.

  Returns `{:ok, membership}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find_membership(id()) :: {:ok, MissionMembership.t()} | {:error, :not_found}

  @doc """
  Lists all memberships for a mission.

  ## Options

  - `:preload` - Associations to preload (default: [:user])
  """
  @callback list_memberships(id(), opts()) :: [MissionMembership.t()]

  @doc """
  Persists a mission membership (insert or update).

  Returns `{:ok, membership}` with the persisted entity, or `{:error, reason}` on failure.
  """
  @callback save_membership(MissionMembership.t()) :: {:ok, MissionMembership.t()} | {:error, error()}

  @doc """
  Deletes a mission membership by ID.

  Returns `{:ok, membership}` if deleted, `{:error, :not_found}` if not found.
  """
  @callback delete_membership(id()) :: {:ok, MissionMembership.t()} | {:error, :not_found}

  @doc """
  Finds a user's role in a mission.

  Returns `{:ok, role}` if the user is a member, `{:error, :not_found}` otherwise.
  """
  @callback find_user_role(user_id(), id()) :: {:ok, role()} | {:error, :not_found}

  @doc """
  Returns the configured missions repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :missions_repository,
      Cadence.Adapters.Persistence.Ecto.Missions.EctoMissionsRepository
    )
  end
end
