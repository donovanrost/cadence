defmodule Cadence.Missions do
  @moduledoc """
  Persistence boundary for organization-owned missions.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Missions.{Mission, MissionRow}
  alias Cadence.Organizations
  alias Cadence.Repo

  @spec persist_mission(Mission.t()) :: {:ok, Mission.t()} | {:error, term()}
  def persist_mission(%Mission{} = mission) do
    with {:ok, _organization} <- Organizations.fetch_organization(mission.organization_id) do
      case Repo.insert(MissionRow.changeset(mission),
             on_conflict: :nothing,
             conflict_target: [:mission_id]
           ) do
        {:ok, %MissionRow{} = row} ->
          {:ok, MissionRow.to_domain(row)}

        {:error, %Changeset{} = changeset} ->
          {:error, changeset}
      end
    end
  end

  @spec fetch_mission(binary(), binary()) :: {:ok, Mission.t()} | {:error, term()}
  def fetch_mission(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    mission_row =
      MissionRow
      |> where(
        [mission_row],
        mission_row.organization_id == ^organization_id and mission_row.mission_id == ^mission_id
      )
      |> Repo.one()

    case mission_row do
      %MissionRow{} = row -> {:ok, MissionRow.to_domain(row)}
      nil -> {:error, :mission_not_found}
    end
  end

  @doc """
  The organization a mission belongs to, or nil when there is no such mission.

  A mission never changes organization, so a found answer is memoized in the calling process
  (#687): the ingest path's long-lived processes (archive writers, the persistence projector,
  storage) ask this for every batch and every mission-owned row, and now pay one query per mission
  for their lifetime instead of one per call. A miss is not memoized, so a mission created later
  is found. The memo lives and dies with the process: nothing is shared across processes or
  nodes, so there is nothing to invalidate.
  """
  @spec organization_id_for_mission(binary()) :: binary() | nil
  def organization_id_for_mission(mission_id) when is_binary(mission_id) do
    key = {__MODULE__, :organization_id, mission_id}

    case Process.get(key) do
      nil ->
        organization_id =
          MissionRow
          |> where([mission_row], mission_row.mission_id == ^mission_id)
          |> select([mission_row], mission_row.organization_id)
          |> Repo.one()

        if organization_id, do: Process.put(key, organization_id)
        organization_id

      organization_id ->
        organization_id
    end
  end

  @doc """
  Every mission on the platform as `{organization_id, mission_id}` (a platform-wide binding's
  blast radius, DECISIONS #90).
  """
  @spec list_all_mission_keys() :: [{binary(), binary()}]
  def list_all_mission_keys do
    MissionRow
    |> select([row], {row.organization_id, row.mission_id})
    |> Repo.all()
  end

  @spec list_missions(binary()) :: [Mission.t()]
  def list_missions(organization_id) when is_binary(organization_id) do
    MissionRow
    |> where([mission_row], mission_row.organization_id == ^organization_id)
    |> order_by([mission_row], asc: mission_row.slug)
    |> Repo.all()
    |> Enum.map(&MissionRow.to_domain/1)
  end

  @doc "Counts an organization's missions and reads its three most recently created records."
  def organization_summary(organization_id) when is_binary(organization_id) do
    query = where(MissionRow, [row], row.organization_id == ^organization_id)

    recent =
      query
      |> order_by([row], desc: row.inserted_at, asc: row.mission_id)
      |> limit(3)
      |> select([row], %{
        mission_id: row.mission_id,
        display_name: row.display_name,
        slug: row.slug,
        created_at: row.inserted_at
      })
      |> Repo.all()

    %{total_count: Repo.aggregate(query, :count, :mission_id), recent: recent}
  end

  @doc "Bounded mission identities for reviewing organization setting impact."
  def settings_overview(organization_id) when is_binary(organization_id) do
    query = where(MissionRow, [row], row.organization_id == ^organization_id)

    items =
      query
      |> order_by([row], asc: row.slug, asc: row.mission_id)
      |> limit(100)
      |> select([row], %{id: row.mission_id, name: row.display_name})
      |> Repo.all()

    %{total: Repo.aggregate(query, :count, :mission_id), items: items}
  end
end
