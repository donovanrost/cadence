defmodule Cadence.Application.Missions.MissionOperations do
  @moduledoc """
  Use case module for mission write operations.

  Provides operations for creating, updating, and managing missions.
  Handles bucket creation/deletion for recording context integration.

  ## Usage

      # Create a mission (also creates its bucket)
      {:ok, mission} = MissionOperations.create(org_id, %{name: "ISS Ops", slug: "iss-ops"})

      # Request mission runtime start (desired state)
      {:ok, mission} = MissionOperations.request_start(mission_id, org_id)

      # Request mission runtime stop (desired state)
      {:ok, mission} = MissionOperations.request_stop(mission_id, org_id)

      # Advance mission phase
      {:ok, mission} = MissionOperations.advance_phase(mission_id, org_id, :operational)

      # Delete a mission (also deletes its bucket)
      :ok = MissionOperations.delete(mission_id, org_id)
  """

  import Ecto.Query, only: [from: 2]

  alias Cadence.Application.Missions.MissionQueries
  alias Cadence.Buckets
  alias Cadence.Domain.Missions.Entities.Mission
  alias Cadence.Domain.Missions.Entities.MissionMembership
  alias Cadence.Missions.Mission, as: MissionSchema
  alias Cadence.Ports.Repository.Missions.MissionsRepository
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
    # Atomize string keys from form params
    mission_attrs =
      attrs
      |> atomize_keys()
      |> Map.put(:organization_id, org_id)

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

  # Atomize string keys for domain entity compatibility
  # Only converts known mission attribute keys to atoms
  @known_keys ~w(name slug description status phase config metadata start_date end_date creator_user_id organization_id)

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) and key in @known_keys ->
        {String.to_atom(key), value}

      {key, value} when is_atom(key) ->
        {key, value}

      {key, value} ->
        {key, value}
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
    # Atomize string keys from form params
    atomized_attrs = atomize_keys(attrs)

    with {:ok, mission} <- MissionQueries.find_by_org(mission_id, org_id),
         {:ok, updated} <- Mission.update(mission, atomized_attrs) do
      repo().save(updated)
    end
  end

  @doc """
  Requests mission runtime start (sets status to :active).

  This updates the mission status to :active in the database.
  The OrgReconciler will detect this change and start the MissionSupervisor tree.

  ## Declarative Model

  This function only updates the desired state (database). The reconciler
  handles the actual runtime start, providing self-healing if events are missed.
  """
  @spec request_start(mission_id(), org_id()) :: {:ok, Mission.t()} | {:error, term()}
  def request_start(mission_id, org_id) do
    with {:ok, mission} <- MissionQueries.find_by_org(mission_id, org_id),
         {:ok, started} <- Mission.start(mission) do
      # Reconciler will detect the status change and start the runtime
      repo().save(started)
    end
  end

  @doc """
  Requests mission runtime stop (sets status to :inactive).

  This updates the mission status to :inactive in the database.
  The OrgReconciler will detect this change and stop the MissionSupervisor tree.

  ## Declarative Model

  This function only updates the desired state (database). The reconciler
  handles the actual runtime stop, providing self-healing if events are missed.
  """
  @spec request_stop(mission_id(), org_id()) :: {:ok, Mission.t()} | {:error, term()}
  def request_stop(mission_id, org_id) do
    with {:ok, mission} <- MissionQueries.find_by_org(mission_id, org_id),
         {:ok, stopped} <- Mission.stop(mission) do
      # Reconciler will detect the status change and stop the runtime
      repo().save(stopped)
    end
  end

  @doc """
  Requests mission runtime suspension (sets status to :suspended).

  The mission can be resumed later with `resume/2`.
  """
  @spec suspend(mission_id(), org_id()) :: {:ok, Mission.t()} | {:error, term()}
  def suspend(mission_id, org_id) do
    with {:ok, mission} <- MissionQueries.find_by_org(mission_id, org_id),
         {:ok, suspended} <- Mission.suspend(mission) do
      repo().save(suspended)
    end
  end

  @doc """
  Resumes a suspended mission.
  """
  @spec resume(mission_id(), org_id()) :: {:ok, Mission.t()} | {:error, term()}
  def resume(mission_id, org_id) do
    with {:ok, mission} <- MissionQueries.find_by_org(mission_id, org_id),
         {:ok, resumed} <- Mission.resume(mission) do
      repo().save(resumed)
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
         {:ok, advanced} <- Mission.advance_phase(mission, new_phase) do
      repo().save(advanced)
    end
  end

  @doc """
  Bumps the mission config_generation to trigger runtime reconciliation.

  Returns the new config_generation.
  """
  @spec bump_config_generation!(mission_id()) :: non_neg_integer()
  def bump_config_generation!(mission_id) do
    query = from(m in MissionSchema, where: m.id == ^mission_id)

    case Repo.update_all(query, inc: [config_generation: 1]) do
      {1, _} ->
        Repo.get!(MissionSchema, mission_id).config_generation

      {0, _} ->
        raise "mission not found for config generation bump"

      _ ->
        raise "unexpected result while bumping config generation"
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
