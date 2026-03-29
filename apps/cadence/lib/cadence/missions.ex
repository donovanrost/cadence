defmodule Cadence.Missions do
  @moduledoc """
  Persistence boundary for organization-owned missions.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Cadence.Missions.Mission
  alias Cadence.Organizations
  alias Cadence.Persistence.Schemas.MissionRow
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

  @spec list_missions(binary()) :: [Mission.t()]
  def list_missions(organization_id) when is_binary(organization_id) do
    MissionRow
    |> where([mission_row], mission_row.organization_id == ^organization_id)
    |> order_by([mission_row], asc: mission_row.slug)
    |> Repo.all()
    |> Enum.map(&MissionRow.to_domain/1)
  end
end
