defmodule Cadence.Missions do
  @moduledoc """
  The Missions context - boundary for mission-related operations.

  This context handles:
  - Mission CRUD operations
  - Mission lifecycle (starting/stopping runtime supervision trees)
  - Mission membership management
  - Mission-scoped queries

  Persistence is delegated to the MissionsRepository port, allowing for
  different storage implementations (Ecto, in-memory for tests, etc.).

  ## Hexagonal Architecture

  This facade delegates to the application layer services:
  - `Cadence.Application.Missions.MissionQueries` - Read operations
  - `Cadence.Application.Missions.MissionOperations` - Write operations
  - `Cadence.Application.Missions.MembershipOperations` - Membership management

  Domain entities are returned for new code, while Ecto schemas are still
  supported for backward compatibility with LiveView forms and existing code.
  """

  import Ecto.Query, warn: false
  alias Cadence.Repo

  alias Cadence.Missions.{Mission, MissionMembership}
  alias Cadence.Runtime.Missions.MissionSupervisor
  alias Cadence.Organizations.Organization
  alias Cadence.Ports.Repository.Missions.MissionsRepository

  # Application layer services
  alias Cadence.Application.Missions.MissionQueries
  alias Cadence.Application.Missions.MissionOperations
  alias Cadence.Application.Missions.MembershipOperations

  # Domain entities
  alias Cadence.Domain.Missions.Entities.Mission, as: MissionEntity
  alias Cadence.Domain.Missions.Entities.MissionMembership, as: MembershipEntity

  # Repository accessor
  defp repo, do: MissionsRepository.impl()

  ## Mission CRUD

  @doc """
  Returns the list of missions for an organization.
  """
  def list_missions(%Organization{id: org_id}) do
    repo().list(org_id, [])
  end

  @doc """
  Gets a single mission scoped to an organization.

  Raises `Ecto.NoResultsError` if the Mission does not exist or doesn't belong to the organization.
  """
  def get_mission!(id, organization_id) do
    case repo().find_by_org(id, organization_id) do
      {:ok, mission} -> mission
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: Mission
    end
  end

  @doc """
  Gets a single mission scoped to an organization.

  Returns `nil` if the Mission does not exist or doesn't belong to the organization.
  """
  def get_mission(id, organization_id) do
    case repo().find_by_org(id, organization_id) do
      {:ok, mission} -> mission
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Gets a single mission by ID without organization scoping.

  WARNING: This bypasses multi-tenancy. Only use for internal operations
  where organization context is verified elsewhere (e.g., mission supervisors).
  """
  def get_mission_unscoped(id) do
    case repo().find(id) do
      {:ok, mission} -> mission
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Gets a single mission by ID without organization scoping, raises if not found.

  WARNING: This bypasses multi-tenancy. Only use for internal operations
  where organization context is verified elsewhere (e.g., mission supervisors).
  """
  def get_mission_unscoped!(id) do
    case repo().find(id) do
      {:ok, mission} -> mission
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: Mission
    end
  end

  @doc """
  Gets a single mission with authorization check.

  Returns `{:ok, mission}` if authorized, `{:error, :unauthorized}` otherwise.
  """
  def get_mission_authorized(id, scope) do
    # Use unscoped since we're checking authorization via Bodyguard
    mission = get_mission_unscoped!(id)

    case Bodyguard.permit(Cadence.Missions.Policy, :view, scope, mission) do
      :ok -> {:ok, mission}
      {:error, _} -> {:error, :unauthorized}
    end
  end

  @doc """
  Gets a single mission by ID and organization.

  Returns nil if not found or doesn't belong to the organization.
  """
  def get_mission_by_org(id, %Organization{id: org_id}) do
    Mission
    |> where([m], m.id == ^id and m.organization_id == ^org_id)
    |> Repo.one()
  end

  @doc """
  Creates a mission.

  If `creator_user_id` is provided in attrs, automatically creates a mission_membership
  for that user with role "admin".
  """
  def create_mission(attrs \\ %{}) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:mission, Mission.changeset(%Mission{}, attrs))
    |> Ecto.Multi.run(:mission_membership, fn repo, %{mission: mission} ->
      # Create mission membership for the creator if user_id is provided
      case Map.get(attrs, "creator_user_id") || Map.get(attrs, :creator_user_id) do
        nil ->
          {:ok, nil}

        user_id ->
          %MissionMembership{}
          |> MissionMembership.changeset(%{
            user_id: user_id,
            mission_id: mission.id,
            role: "admin"
          })
          |> repo.insert()
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{mission: mission}} -> {:ok, mission}
      {:error, :mission, changeset, _} -> {:error, changeset}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Updates a mission.
  """
  def update_mission(%Mission{} = mission, attrs) do
    mission
    |> Mission.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a mission with authorization check.

  Returns `{:ok, mission}` if authorized and updated, `{:error, :unauthorized}` if not authorized.
  """
  def update_mission_authorized(%Mission{} = mission, attrs, scope) do
    with :ok <- Bodyguard.permit(Cadence.Missions.Policy, :update, scope, mission) do
      update_mission(mission, attrs)
    else
      {:error, _} -> {:error, :unauthorized}
    end
  end

  @doc """
  Deletes a mission.
  """
  def delete_mission(%Mission{} = mission) do
    # Stop the mission runtime if it's running
    stop_mission(mission.id)

    Repo.delete(mission)
  end

  @doc """
  Deletes a mission with authorization check.

  Returns `{:ok, mission}` if authorized and deleted, `{:error, :unauthorized}` if not authorized.
  """
  def delete_mission_authorized(%Mission{} = mission, scope) do
    with :ok <- Bodyguard.permit(Cadence.Missions.Policy, :delete, scope, mission) do
      delete_mission(mission)
    else
      {:error, _} -> {:error, :unauthorized}
    end
  end

  ## Mission Lifecycle

  @doc """
  Starts a mission's supervision tree.

  This activates the mission's runtime processes including CVT, interfaces,
  telemetry pipeline, and command queue.
  """
  def start_mission(mission_id) when is_binary(mission_id) do
    # Internal lifecycle management - use unscoped
    mission = get_mission_unscoped!(mission_id)
    start_mission(mission)
  end

  def start_mission(%Mission{status: "active"} = mission) do
    case MissionSupervisor.start_mission(mission) do
      {:ok, _pid} = result ->
        result

      {:error, reason} = error ->
        {:error, "Failed to start mission: #{inspect(reason)}"}
        error
    end
  end

  def start_mission(%Mission{status: status}) do
    {:error, "Cannot start mission with status: #{status}"}
  end

  @doc """
  Stops a mission's supervision tree.

  This gracefully shuts down all mission processes.
  """
  def stop_mission(mission_id) when is_binary(mission_id) do
    MissionSupervisor.stop_mission(mission_id)
  end

  @doc """
  Activates a mission (sets status to active and starts runtime).
  """
  def activate_mission(%Mission{} = mission) do
    with {:ok, mission} <- update_mission(mission, %{status: "active"}),
         {:ok, _pid} <- start_mission(mission) do
      {:ok, mission}
    end
  end

  @doc """
  Deactivates a mission (stops runtime and sets status to inactive).
  """
  def deactivate_mission(%Mission{} = mission) do
    with :ok <- stop_mission(mission.id),
         {:ok, mission} <- update_mission(mission, %{status: "inactive"}) do
      {:ok, mission}
    end
  end

  @doc """
  Lists all running missions.
  """
  def list_running_missions do
    MissionSupervisor.list_running_missions()
  end

  ## Mission Memberships

  @doc """
  Returns the list of memberships for a mission.
  """
  def list_mission_memberships(%Mission{id: mission_id}) do
    repo().list_memberships(mission_id, preload: [:user])
  end

  @doc """
  Gets a single mission membership.
  """
  def get_mission_membership!(id) do
    case repo().find_membership(id) do
      {:ok, membership} -> membership
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: MissionMembership
    end
  end

  @doc """
  Creates a mission membership.
  """
  def create_mission_membership(attrs \\ %{}) do
    membership = struct(MissionMembership, normalize_attrs(attrs))
    repo().save_membership(membership)
  end

  @doc """
  Updates a mission membership (typically to change role).
  """
  def update_mission_membership(%MissionMembership{} = membership, attrs) do
    # Keep using Repo for changeset-based updates
    membership
    |> MissionMembership.update_role_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a mission membership.
  """
  def delete_mission_membership(%MissionMembership{} = membership) do
    repo().delete_membership(membership.id)
  end

  @doc """
  Gets a user's role in a mission.

  Returns the role string or nil if the user is not a member.
  """
  def get_user_mission_role(user_id, mission_id) do
    case repo().find_user_role(user_id, mission_id) do
      {:ok, role} -> role
      {:error, :not_found} -> nil
    end
  end

  # Private helper to normalize attrs to atom keys
  defp normalize_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {k, v}, acc when is_binary(k) -> Map.put(acc, String.to_existing_atom(k), v)
      {k, v}, acc when is_atom(k) -> Map.put(acc, k, v)
    end)
  end

  # ===========================================================================
  # Hexagonal Architecture API (Domain Entities)
  # ===========================================================================
  # These functions return domain entities and delegate to the application layer.
  # Use these for new code that doesn't need Ecto changesets.

  @doc """
  Gets a mission as a domain entity.

  Returns `{:ok, mission_entity}` or `{:error, :not_found}`.
  """
  @spec get_mission_entity(String.t(), String.t()) ::
          {:ok, MissionEntity.t()} | {:error, :not_found}
  def get_mission_entity(mission_id, organization_id) do
    MissionQueries.find_by_org(mission_id, organization_id)
  end

  @doc """
  Lists missions as domain entities for an organization.
  """
  @spec list_mission_entities(String.t(), keyword()) :: [MissionEntity.t()]
  def list_mission_entities(organization_id, opts \\ []) do
    MissionQueries.list(organization_id, opts)
  end

  @doc """
  Creates a mission with bucket integration.

  This creates both the mission and its associated bucket for recording context.
  Returns `{:ok, mission_entity}` or `{:error, reason}`.
  """
  @spec create_mission_with_bucket(String.t(), map()) ::
          {:ok, MissionEntity.t()} | {:error, term()}
  def create_mission_with_bucket(organization_id, attrs) do
    MissionOperations.create(organization_id, attrs)
  end

  @doc """
  Deletes a mission and its associated bucket.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec delete_mission_with_bucket(String.t(), String.t()) :: :ok | {:error, term()}
  def delete_mission_with_bucket(mission_id, organization_id) do
    MissionOperations.delete(mission_id, organization_id)
  end

  @doc """
  Adds a member to a mission using domain entities.
  """
  @spec add_mission_member(String.t(), String.t(), atom() | nil) ::
          {:ok, MembershipEntity.t()} | {:error, term()}
  def add_mission_member(mission_id, user_id, role \\ nil) do
    MembershipOperations.add_member(mission_id, user_id, role)
  end

  @doc """
  Checks if a user can send commands in a mission.
  """
  @spec user_can_command?(String.t(), String.t()) :: boolean()
  def user_can_command?(user_id, mission_id) do
    MissionQueries.can_command?(user_id, mission_id)
  end

  @doc """
  Checks if a mission runtime is running.
  """
  @spec mission_running?(String.t()) :: boolean()
  def mission_running?(mission_id) do
    MissionQueries.running?(mission_id)
  end
end
