defmodule Cadence.SpacecraftStore do
  @moduledoc """
  Persistence boundary for mission-owned spacecraft.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Cadence.Missions
  alias Cadence.Persistence.Schemas.SpacecraftRow
  alias Cadence.Repo
  alias Cadence.Spacecraft

  @spec persist_spacecraft(binary(), Spacecraft.t()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def persist_spacecraft(organization_id, %Spacecraft{} = spacecraft)
      when is_binary(organization_id) do
    with {:ok, scoped_spacecraft} <- put_organization_scope(spacecraft, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(scoped_spacecraft.organization_id, scoped_spacecraft.mission_id),
         {:ok, _row} <-
           Repo.insert(SpacecraftRow.changeset(scoped_spacecraft),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :spacecraft_id]
           ) do
      {:ok, scoped_spacecraft}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec persist_spacecraft(Spacecraft.t()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def persist_spacecraft(%Spacecraft{} = spacecraft) do
    case Repo.insert(SpacecraftRow.changeset(spacecraft),
           on_conflict: :nothing,
           conflict_target: [:mission_id, :spacecraft_id]
         ) do
      {:ok, %SpacecraftRow{} = row} ->
        {:ok, SpacecraftRow.to_domain(row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec fetch_spacecraft(binary(), binary()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def fetch_spacecraft(mission_id, spacecraft_id)
      when is_binary(mission_id) and is_binary(spacecraft_id) do
    case Repo.get_by(SpacecraftRow, mission_id: mission_id, spacecraft_id: spacecraft_id) do
      nil -> {:error, :spacecraft_not_found}
      %SpacecraftRow{} = row -> {:ok, SpacecraftRow.to_domain(row)}
    end
  end

  @spec fetch_spacecraft(binary(), binary(), binary()) ::
          {:ok, Spacecraft.t()} | {:error, term()}
  def fetch_spacecraft(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    case Repo.get_by(
           SpacecraftRow,
           organization_id: organization_id,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         ) do
      nil -> {:error, :spacecraft_not_found}
      %SpacecraftRow{} = row -> {:ok, SpacecraftRow.to_domain(row)}
    end
  end

  @spec list_spacecraft(binary()) :: [Spacecraft.t()]
  def list_spacecraft(mission_id) when is_binary(mission_id) do
    SpacecraftRow
    |> where([row], row.mission_id == ^mission_id)
    |> order_by([row], asc: row.spacecraft_id)
    |> Repo.all()
    |> Enum.map(&SpacecraftRow.to_domain/1)
  end

  @spec list_spacecraft(binary(), binary()) :: [Spacecraft.t()]
  def list_spacecraft(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    SpacecraftRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], asc: row.spacecraft_id)
    |> Repo.all()
    |> Enum.map(&SpacecraftRow.to_domain/1)
  end

  defp put_organization_scope(%Spacecraft{} = spacecraft, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case spacecraft.organization_id do
      nil ->
        {:ok, %Spacecraft{spacecraft | organization_id: organization_id}}

      ^organization_id ->
        {:ok, spacecraft}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          spacecraft.mission_id}}
    end
  end
end
