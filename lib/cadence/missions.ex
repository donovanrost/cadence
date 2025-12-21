defmodule Cadence.Missions do
  @moduledoc """
  The Missions context - boundary for mission-related operations.

  This context handles:
  - Mission CRUD operations
  - Mission lifecycle (starting/stopping runtime supervision trees)
  - Mission membership management
  - Mission-scoped queries
  """

  import Ecto.Query, warn: false
  alias Cadence.Repo

  alias Cadence.Missions.{Mission, MissionMembership, MissionSupervisor}
  alias Cadence.Organizations.Organization

  ## Mission CRUD

  @doc """
  Returns the list of missions for an organization.
  """
  def list_missions(%Organization{id: org_id}) do
    Mission
    |> where([m], m.organization_id == ^org_id)
    |> order_by([m], desc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single mission.

  Raises `Ecto.NoResultsError` if the Mission does not exist.
  """
  def get_mission!(id), do: Repo.get!(Mission, id)

  @doc """
  Gets a single mission.

  Returns `nil` if the Mission does not exist.
  """
  def get_mission(id), do: Repo.get(Mission, id)

  @doc """
  Gets a single mission with authorization check.

  Returns `{:ok, mission}` if authorized, `{:error, :unauthorized}` otherwise.
  """
  def get_mission_authorized(id, scope) do
    mission = get_mission!(id)

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
    mission = get_mission!(mission_id)
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
    MissionMembership
    |> where([mm], mm.mission_id == ^mission_id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Gets a single mission membership.
  """
  def get_mission_membership!(id), do: Repo.get!(MissionMembership, id)

  @doc """
  Creates a mission membership.
  """
  def create_mission_membership(attrs \\ %{}) do
    %MissionMembership{}
    |> MissionMembership.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a mission membership (typically to change role).
  """
  def update_mission_membership(%MissionMembership{} = membership, attrs) do
    membership
    |> MissionMembership.update_role_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a mission membership.
  """
  def delete_mission_membership(%MissionMembership{} = membership) do
    Repo.delete(membership)
  end

  @doc """
  Gets a user's role in a mission.

  Returns the role string or nil if the user is not a member.
  """
  def get_user_mission_role(user_id, mission_id) do
    MissionMembership
    |> where([mm], mm.user_id == ^user_id and mm.mission_id == ^mission_id)
    |> select([mm], mm.role)
    |> Repo.one()
  end
end
