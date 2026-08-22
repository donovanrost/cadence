defmodule Cadence.Application.Missions.MissionQueries do
  @moduledoc """
  Use case module for querying missions.

  Provides read-only operations for finding and listing missions.

  ## Usage

      # Find by ID
      {:ok, mission} = MissionQueries.find(mission_id)

      # Find by ID scoped to organization
      {:ok, mission} = MissionQueries.find_by_org(mission_id, org_id)

      # List all missions for an organization
      missions = MissionQueries.list(org_id)

      # Get a user's membership in a mission
      {:ok, membership} = MissionQueries.get_membership(user_id, mission_id)
  """

  alias Cadence.Domain.Missions.Entities.Mission
  alias Cadence.Domain.Missions.Entities.MissionMembership
  alias Cadence.Ports.Repository.Missions.MissionsRepository

  @type mission_id :: String.t()
  @type org_id :: String.t()
  @type user_id :: String.t()
  @type opts :: keyword()

  # Get configured repository
  defp repo do
    MissionsRepository.impl()
  end

  @doc """
  Finds a mission by ID (unscoped).

  Returns `{:ok, mission}` if found, `{:error, :not_found}` otherwise.
  """
  @spec find(mission_id()) :: {:ok, Mission.t()} | {:error, :not_found}
  def find(id), do: repo().find(id)

  @doc """
  Finds a mission by ID, raising if not found.
  """
  @spec find!(mission_id()) :: Mission.t()
  def find!(id) do
    case find(id) do
      {:ok, mission} -> mission
      {:error, :not_found} -> raise "Mission not found: #{id}"
    end
  end

  @doc """
  Finds a mission by ID scoped to an organization.

  Returns `{:ok, mission}` if found and belongs to the organization,
  `{:error, :not_found}` otherwise.
  """
  @spec find_by_org(mission_id(), org_id()) :: {:ok, Mission.t()} | {:error, :not_found}
  def find_by_org(id, org_id), do: repo().find_by_org(id, org_id)

  @doc """
  Lists all missions for an organization with optional filtering.

  ## Options

  - `:status` - Filter by status (:inactive, :active, :suspended)
  - `:phase` - Filter by phase (:planning, :testing, :operational, :decommissioned)
  - `:limit` - Maximum number of results
  - `:order` - Sort order (default: inserted_at DESC)

  ## Examples

      # All missions for an organization
      MissionQueries.list(org_id)

      # Active missions only
      MissionQueries.list(org_id, status: :active)

      # Operational missions
      MissionQueries.list(org_id, phase: :operational)
  """
  @spec list(org_id(), opts()) :: [Mission.t()]
  def list(org_id, opts \\ []), do: repo().list(org_id, opts)

  @doc """
  Finds a user's membership in a mission.

  Returns `{:ok, membership}` if found, `{:error, :not_found}` otherwise.
  """
  @spec get_membership(user_id(), mission_id()) ::
          {:ok, MissionMembership.t()} | {:error, :not_found}
  def get_membership(user_id, mission_id) do
    case repo().find_user_role(user_id, mission_id) do
      {:ok, role} ->
        MissionMembership.new(%{
          user_id: user_id,
          mission_id: mission_id,
          role: role
        })

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Finds a user's role in a mission.

  Returns `{:ok, role}` if the user is a member, `{:error, :not_found}` otherwise.
  """
  @spec get_user_role(user_id(), mission_id()) :: {:ok, atom()} | {:error, :not_found}
  def get_user_role(user_id, mission_id), do: repo().find_user_role(user_id, mission_id)

  @doc """
  Lists all memberships for a mission.

  ## Options

  - `:preload` - Associations to preload (default: [:user])
  """
  @spec list_memberships(mission_id(), opts()) :: [MissionMembership.t()]
  def list_memberships(mission_id, opts \\ []), do: repo().list_memberships(mission_id, opts)

  @doc """
  Checks if a user is a member of a mission.
  """
  @spec member?(user_id(), mission_id()) :: boolean()
  def member?(user_id, mission_id) do
    case get_user_role(user_id, mission_id) do
      {:ok, _role} -> true
      {:error, :not_found} -> false
    end
  end

  @doc """
  Checks if a user can send commands in a mission.
  """
  @spec can_command?(user_id(), mission_id()) :: boolean()
  def can_command?(user_id, mission_id) do
    case get_membership(user_id, mission_id) do
      {:ok, membership} -> MissionMembership.can_command?(membership)
      {:error, :not_found} -> false
    end
  end

  @doc """
  Checks if a mission is running.
  """
  @spec running?(mission_id()) :: boolean()
  def running?(mission_id) do
    case find(mission_id) do
      {:ok, mission} -> Mission.running?(mission)
      {:error, :not_found} -> false
    end
  end
end
