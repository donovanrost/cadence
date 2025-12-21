defmodule Cadence.Adapters.Persistence.Ecto.Missions.EctoMissionsRepository do
  @moduledoc """
  Ecto-based implementation of the MissionsRepository port.

  This adapter provides persistence for missions and mission memberships
  using PostgreSQL via Ecto.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :missions_repository, Cadence.Adapters.Persistence.Ecto.Missions.EctoMissionsRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Missions.MissionsRepository.impl()
      {:ok, mission} = repo.find(mission_id)
  """

  @behaviour Cadence.Ports.Repository.Missions.MissionsRepository

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Missions.{Mission, MissionMembership}

  # ===========================================================================
  # Mission Operations
  # ===========================================================================

  @impl true
  def find(id) do
    case Repo.get(Mission, id) do
      nil -> {:error, :not_found}
      mission -> {:ok, mission}
    end
  end

  @impl true
  def find_by_org(id, organization_id) do
    query =
      from m in Mission,
        where: m.id == ^id and m.organization_id == ^organization_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      mission -> {:ok, mission}
    end
  end

  @impl true
  def list(organization_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit)

    query =
      from m in Mission,
        where: m.organization_id == ^organization_id,
        order_by: [desc: m.inserted_at]

    query = apply_mission_filters(query, status: status, limit: limit)

    Repo.all(query)
  end

  @impl true
  def save(%Mission{id: nil} = mission) do
    # Insert new mission
    mission
    |> Mission.changeset(%{})
    |> Repo.insert()
  end

  def save(%Mission{} = mission) do
    # For updates, we need to use a changeset with current attributes
    # This handles missions that have been modified in memory
    attrs = Map.from_struct(mission) |> Map.drop([:__meta__, :organization, :targets, :mission_memberships])

    case Repo.get(Mission, mission.id) do
      nil ->
        {:error, :not_found}

      existing ->
        existing
        |> Mission.update_changeset(attrs)
        |> Repo.update()
    end
  end

  @impl true
  def delete(id) do
    case Repo.get(Mission, id) do
      nil ->
        {:error, :not_found}

      mission ->
        case Repo.delete(mission) do
          {:ok, deleted} -> {:ok, deleted}
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  # ===========================================================================
  # Mission Membership Operations
  # ===========================================================================

  @impl true
  def find_membership(id) do
    case Repo.get(MissionMembership, id) do
      nil -> {:error, :not_found}
      membership -> {:ok, membership}
    end
  end

  @impl true
  def list_memberships(mission_id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [:user])

    query =
      from mm in MissionMembership,
        where: mm.mission_id == ^mission_id

    query
    |> preload(^preloads)
    |> Repo.all()
  end

  @impl true
  def save_membership(%MissionMembership{id: nil} = membership) do
    # Insert new membership
    attrs = Map.from_struct(membership) |> Map.drop([:__meta__, :user, :mission])

    %MissionMembership{}
    |> MissionMembership.changeset(attrs)
    |> Repo.insert()
  end

  def save_membership(%MissionMembership{} = membership) do
    # Update existing membership
    attrs = Map.from_struct(membership) |> Map.drop([:__meta__, :user, :mission])

    case Repo.get(MissionMembership, membership.id) do
      nil ->
        {:error, :not_found}

      existing ->
        existing
        |> MissionMembership.changeset(attrs)
        |> Repo.update()
    end
  end

  @impl true
  def delete_membership(id) do
    case Repo.get(MissionMembership, id) do
      nil ->
        {:error, :not_found}

      membership ->
        case Repo.delete(membership) do
          {:ok, deleted} -> {:ok, deleted}
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  @impl true
  def find_user_role(user_id, mission_id) do
    query =
      from mm in MissionMembership,
        where: mm.user_id == ^user_id and mm.mission_id == ^mission_id,
        select: mm.role

    case Repo.one(query) do
      nil -> {:error, :not_found}
      role -> {:ok, role}
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp apply_mission_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:status, nil}, q -> q
      {:status, status}, q -> from(m in q, where: m.status == ^status)
      {:limit, nil}, q -> q
      {:limit, limit}, q -> from(m in q, limit: ^limit)
    end)
  end
end
