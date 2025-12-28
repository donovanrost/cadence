defmodule Cadence.Missions do
  @moduledoc """
  The Missions context - facade for mission-related operations.

  This module delegates to hexagonal architecture application services:

  - `Cadence.Application.Missions.MissionQueries` - Mission read operations
  - `Cadence.Application.Missions.MissionOperations` - Mission write operations
  - `Cadence.Application.Missions.MembershipOperations` - Membership management

  ## Domain Entities

  All functions return domain entities from `Cadence.Domain.Missions.Entities.*`,
  not Ecto schemas.

  ## Usage

      # Find a mission (scoped)
      {:ok, mission} = Missions.get_mission(id, org_id)

      # Find a mission (unscoped - for internal use)
      {:ok, mission} = Missions.get_mission(id)

      # Create a mission
      {:ok, mission} = Missions.create_mission(org_id, attrs)

      # Start mission runtime
      {:ok, mission} = Missions.start_mission(mission_id, org_id)

  ## Form Helpers

  Some functions return Ecto changesets for Phoenix form compatibility.
  These are clearly marked in the documentation.
  """

  # Application services
  alias Cadence.Application.Missions.MembershipOperations
  alias Cadence.Application.Missions.MissionOperations
  alias Cadence.Application.Missions.MissionQueries
  alias Cadence.Domain.Missions.Entities.Mission, as: MissionEntity
  alias Cadence.Domain.Missions.Entities.MissionMembership, as: MembershipEntity
  alias Cadence.Missions.Mission, as: MissionSchema

  # ============================================================================
  # Mission Queries
  # ============================================================================

  @doc """
  Lists all missions for an organization.
  """
  @spec list_missions(String.t(), keyword()) :: [MissionEntity.t()]
  def list_missions(organization_id, opts \\ []) when is_binary(organization_id) do
    MissionQueries.list(organization_id, opts)
  end

  @doc """
  Gets a mission by ID (unscoped).

  WARNING: This bypasses multi-tenancy. Use for internal operations where
  organization context is verified elsewhere (e.g., authorization checks).
  """
  @spec get_mission(String.t()) :: {:ok, MissionEntity.t()} | {:error, :not_found}
  def get_mission(id), do: MissionQueries.find(id)

  @doc """
  Gets a mission by ID, raising if not found (unscoped).

  WARNING: This bypasses multi-tenancy.
  """
  @spec get_mission!(String.t()) :: MissionEntity.t()
  def get_mission!(id), do: MissionQueries.find!(id)

  @doc """
  Gets a mission by ID scoped to an organization.
  """
  @spec get_mission(String.t(), String.t()) :: {:ok, MissionEntity.t()} | {:error, :not_found}
  def get_mission(id, organization_id), do: MissionQueries.find_by_org(id, organization_id)

  @doc """
  Checks if a mission runtime is running.
  """
  @spec running?(String.t()) :: boolean()
  def running?(mission_id), do: MissionQueries.running?(mission_id)

  @doc """
  Checks if a user can send commands in a mission.
  """
  @spec can_command?(String.t(), String.t()) :: boolean()
  def can_command?(user_id, mission_id), do: MissionQueries.can_command?(user_id, mission_id)

  @doc """
  Gets a user's role in a mission.
  """
  @spec get_user_role(String.t(), String.t()) :: {:ok, atom()} | {:error, :not_found}
  def get_user_role(user_id, mission_id), do: MissionQueries.get_user_role(user_id, mission_id)

  # ============================================================================
  # Mission Operations
  # ============================================================================

  @doc """
  Creates a new mission with its associated bucket.

  ## Attributes

  Required:
  - `:name` - Mission display name
  - `:slug` - URL-safe identifier

  Optional:
  - `:description` - Mission description
  - `:creator_user_id` - User ID of creator (will be added as admin member)
  """
  @spec create_mission(String.t(), map()) :: {:ok, MissionEntity.t()} | {:error, term()}
  def create_mission(organization_id, attrs) do
    MissionOperations.create(organization_id, attrs)
  end

  @doc """
  Updates an existing mission.
  """
  @spec update_mission(String.t(), String.t(), map()) ::
          {:ok, MissionEntity.t()} | {:error, term()}
  def update_mission(mission_id, organization_id, attrs) do
    MissionOperations.update(mission_id, organization_id, attrs)
  end

  @doc """
  Deletes a mission and its associated bucket.
  """
  @spec delete_mission(String.t(), String.t()) :: :ok | {:error, term()}
  def delete_mission(mission_id, organization_id) do
    MissionOperations.delete(mission_id, organization_id)
  end

  # ============================================================================
  # Mission Lifecycle
  # ============================================================================

  @doc """
  Starts a mission's runtime (sets status to active and starts supervision tree).
  """
  @spec start_mission(String.t(), String.t()) :: {:ok, MissionEntity.t()} | {:error, term()}
  def start_mission(mission_id, organization_id) do
    MissionOperations.start(mission_id, organization_id)
  end

  @doc """
  Stops a mission's runtime (stops supervision tree and sets status to inactive).
  """
  @spec stop_mission(String.t(), String.t()) :: {:ok, MissionEntity.t()} | {:error, term()}
  def stop_mission(mission_id, organization_id) do
    MissionOperations.stop(mission_id, organization_id)
  end

  @doc """
  Suspends a mission's runtime.
  """
  @spec suspend_mission(String.t(), String.t()) :: {:ok, MissionEntity.t()} | {:error, term()}
  def suspend_mission(mission_id, organization_id) do
    MissionOperations.suspend(mission_id, organization_id)
  end

  @doc """
  Resumes a suspended mission.
  """
  @spec resume_mission(String.t(), String.t()) :: {:ok, MissionEntity.t()} | {:error, term()}
  def resume_mission(mission_id, organization_id) do
    MissionOperations.resume(mission_id, organization_id)
  end

  @doc """
  Advances a mission to a new lifecycle phase.
  """
  @spec advance_phase(String.t(), String.t(), atom()) ::
          {:ok, MissionEntity.t()} | {:error, term()}
  def advance_phase(mission_id, organization_id, new_phase) do
    MissionOperations.advance_phase(mission_id, organization_id, new_phase)
  end

  # ============================================================================
  # Mission Memberships
  # ============================================================================

  @doc """
  Adds a member to a mission.
  """
  @spec add_member(String.t(), String.t(), atom() | nil) ::
          {:ok, MembershipEntity.t()} | {:error, term()}
  def add_member(mission_id, user_id, role \\ nil) do
    MembershipOperations.add_member(mission_id, user_id, role)
  end

  @doc """
  Changes a member's role.
  """
  @spec change_member_role(String.t(), atom()) ::
          {:ok, MembershipEntity.t()} | {:error, term()}
  def change_member_role(membership_id, new_role) do
    MembershipOperations.change_role(membership_id, new_role)
  end

  @doc """
  Removes a member from a mission.
  """
  @spec remove_member(String.t()) :: :ok | {:error, term()}
  def remove_member(membership_id) do
    MembershipOperations.remove_member(membership_id)
  end

  @doc """
  Lists all members of a mission.
  """
  @spec list_members(String.t(), keyword()) :: [MembershipEntity.t()]
  def list_members(mission_id, opts \\ []) do
    MembershipOperations.list_members(mission_id, opts)
  end

  @doc """
  Gets a membership by ID.
  """
  @spec get_membership(String.t()) :: {:ok, MembershipEntity.t()} | {:error, :not_found}
  def get_membership(membership_id) do
    MembershipOperations.find(membership_id)
  end

  @doc """
  Checks if a user is a member of a mission.
  """
  @spec member?(String.t(), String.t()) :: boolean()
  def member?(user_id, mission_id) do
    MembershipOperations.member?(user_id, mission_id)
  end

  # ============================================================================
  # Form Helpers (Ecto Schema Layer)
  # ============================================================================

  @doc """
  Returns an `%Ecto.Changeset{}` for changing mission attributes.

  This is a form helper that works with Ecto schemas.
  """
  def change_mission(mission \\ %MissionSchema{}, attrs \\ %{}) do
    MissionSchema.changeset(mission, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for updating mission attributes.

  This is a form helper that works with Ecto schemas.
  """
  def change_mission_for_update(mission, attrs \\ %{}) do
    MissionSchema.update_changeset(mission, attrs)
  end
end
