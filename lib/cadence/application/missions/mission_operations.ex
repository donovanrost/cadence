defmodule Cadence.Application.Missions.MissionOperations do
  @moduledoc """
  Use case module for mission write operations.

  Provides operations for creating, updating, and managing missions.
  Handles bucket creation/deletion for recording context integration.

  ## Usage

      # Create a mission (also creates its bucket)
      {:ok, mission} = MissionOperations.create(org_id, %{name: "ISS Ops", slug: "iss-ops"})

      # Start the mission runtime
      {:ok, mission} = MissionOperations.start(mission_id, org_id)

      # Advance mission phase
      {:ok, mission} = MissionOperations.advance_phase(mission_id, org_id, :operational)

      # Delete a mission (also deletes its bucket)
      :ok = MissionOperations.delete(mission_id, org_id)
  """

  alias Cadence.Application.Missions.MissionQueries
  alias Cadence.Domain.Missions.Entities.Mission
  alias Cadence.Domain.Missions.Entities.MissionMembership
  alias Cadence.Ports.Repository.Missions.MissionsRepository
  alias Cadence.Runtime.Missions.MissionSupervisor
  alias Cadence.Buckets
  alias Cadence.Repo

  @type mission_id :: String.t()
  @type org_id :: String.t()
  @type attrs :: map()

  # Get configured repository
  defp repo do
    MissionsRepository.impl()
  end

  @doc """
  Creates a new mission and its associated bucket.

  The bucket is created atomically with the mission to ensure recording
  context is always available for mission events.

  ## Attributes

  Required:
  - `:name` - Mission display name
  - `:slug` - URL-safe identifier (lowercase alphanumeric with hyphens)

  Optional:
  - `:description` - Mission description
  - `:phase` - Initial phase (default: :planning)
  - `:config` - Mission configuration map
  - `:metadata` - Additional metadata
  - `:start_date` - Planned start date
  - `:end_date` - Planned end date
  - `:creator_user_id` - User ID of creator (will be added as admin member)

  ## Examples

      {:ok, mission} = MissionOperations.create(org_id, %{
        name: "ISS Operations",
        slug: "iss-ops",
        creator_user_id: user_id
      })
  """
  @spec create(org_id(), attrs()) :: {:ok, Mission.t()} | {:error, term()}
  def create(org_id, attrs) do
    mission_attrs = Map.put(attrs, :organization_id, org_id)
    creator_user_id = attrs[:creator_user_id] || attrs["creator_user_id"]

    Repo.transaction(fn ->
      with {:ok, mission} <- Mission.new(mission_attrs),
           {:ok, saved} <- repo().save(mission),
           {:ok, _bucket} <- Buckets.create_bucket_for(saved, organization_id: org_id),
           :ok <- maybe_create_creator_membership(saved.id, creator_user_id) do
        saved
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp maybe_create_creator_membership(_mission_id, nil), do: :ok

  defp maybe_create_creator_membership(mission_id, user_id) do
    with {:ok, membership} <-
           MissionMembership.new(%{
             mission_id: mission_id,
             user_id: user_id,
             role: :admin
           }),
         {:ok, _saved} <- repo().save_membership(membership) do
      :ok
    end
  end

  @doc """
  Updates an existing mission.

  ## Examples

      {:ok, mission} = MissionOperations.update(mission_id, org_id, %{name: "New Name"})
  """
  @spec update(mission_id(), org_id(), attrs()) :: {:ok, Mission.t()} | {:error, term()}
  def update(mission_id, org_id, attrs) do
    with {:ok, mission} <- MissionQueries.find_by_org(mission_id, org_id),
         {:ok, updated} <- Mission.update(mission, attrs),
         {:ok, saved} <- repo().save(updated) do
      {:ok, saved}
    end
  end

  @doc """
  Starts the mission runtime.

  This activates the mission's supervision tree, CVT, and telemetry processing.
  Updates the mission status to :active and starts the MissionSupervisor tree.
  """
  @spec start(mission_id(), org_id()) :: {:ok, Mission.t()} | {:error, term()}
  def start(mission_id, org_id) do
    with {:ok, mission} <- MissionQueries.find_by_org(mission_id, org_id),
         {:ok, started} <- Mission.start(mission),
         {:ok, saved} <- repo().save(started),
         {:ok, _pid} <- MissionSupervisor.start_mission(saved) do
      {:ok, saved}
    end
  end

  @doc """
  Stops the mission runtime.

  This gracefully shuts down the mission's supervision tree and updates
  the mission status to :inactive.
  """
  @spec stop(mission_id(), org_id()) :: {:ok, Mission.t()} | {:error, term()}
  def stop(mission_id, org_id) do
    with {:ok, mission} <- MissionQueries.find_by_org(mission_id, org_id),
         :ok <- stop_runtime(mission_id),
         {:ok, stopped} <- Mission.stop(mission),
         {:ok, saved} <- repo().save(stopped) do
      {:ok, saved}
    end
  end

  defp stop_runtime(mission_id) do
    case MissionSupervisor.stop_mission(mission_id) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      error -> error
    end
  end

  @doc """
  Suspends the mission runtime.

  The mission can be resumed later with `resume/2`.
  """
  @spec suspend(mission_id(), org_id()) :: {:ok, Mission.t()} | {:error, term()}
  def suspend(mission_id, org_id) do
    with {:ok, mission} <- MissionQueries.find_by_org(mission_id, org_id),
         {:ok, suspended} <- Mission.suspend(mission),
         {:ok, saved} <- repo().save(suspended) do
      {:ok, saved}
    end
  end

  @doc """
  Resumes a suspended mission.
  """
  @spec resume(mission_id(), org_id()) :: {:ok, Mission.t()} | {:error, term()}
  def resume(mission_id, org_id) do
    with {:ok, mission} <- MissionQueries.find_by_org(mission_id, org_id),
         {:ok, resumed} <- Mission.resume(mission),
         {:ok, saved} <- repo().save(resumed) do
      {:ok, saved}
    end
  end

  @doc """
  Advances the mission to a new lifecycle phase.

  Valid transitions:
  - :planning -> :testing, :decommissioned
  - :testing -> :operational, :planning, :decommissioned
  - :operational -> :decommissioned
  """
  @spec advance_phase(mission_id(), org_id(), atom()) :: {:ok, Mission.t()} | {:error, term()}
  def advance_phase(mission_id, org_id, new_phase) do
    with {:ok, mission} <- MissionQueries.find_by_org(mission_id, org_id),
         {:ok, advanced} <- Mission.advance_phase(mission, new_phase),
         {:ok, saved} <- repo().save(advanced) do
      {:ok, saved}
    end
  end

  @doc """
  Deletes a mission and its associated bucket.

  This also cascades to delete all related resources (targets, procedures, etc.).
  """
  @spec delete(mission_id(), org_id()) :: :ok | {:error, term()}
  def delete(mission_id, org_id) do
    Repo.transaction(fn ->
      with {:ok, _mission} <- MissionQueries.find_by_org(mission_id, org_id),
           :ok <- delete_mission_bucket(mission_id),
           {:ok, _} <- repo().delete(mission_id) do
        :ok
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Deletes the mission's bucket if it exists
  defp delete_mission_bucket(mission_id) do
    case Buckets.get_bucket_by_bucketable("Mission", mission_id) do
      nil -> :ok
      bucket -> Buckets.delete_bucket(bucket.id)
    end
  end
end
