defmodule Cadence.Comms.GroundStationStore do
  @moduledoc """
  Persistence boundary for mission-owned ground stations.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Comms.GroundStation
  alias Cadence.Missions
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.Schemas.CommsGroundStationRow
  alias Cadence.Repo

  @spec persist_ground_station(binary(), GroundStation.t()) ::
          {:ok, GroundStation.t()} | {:error, term()}
  def persist_ground_station(organization_id, %GroundStation{} = ground_station)
      when is_binary(organization_id) do
    with {:ok, scoped_ground_station} <- put_organization_scope(ground_station, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(
             scoped_ground_station.organization_id,
             scoped_ground_station.mission_id
           ),
         {:ok, _row} <-
           Repo.insert(CommsGroundStationRow.changeset(scoped_ground_station),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :ground_station_id]
           ) do
      fetch_ground_station(
        scoped_ground_station.organization_id,
        scoped_ground_station.mission_id,
        scoped_ground_station.ground_station_id
      )
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_ground_station(binary(), binary(), binary()) ::
          {:ok, GroundStation.t()} | {:error, term()}
  def fetch_ground_station(organization_id, mission_id, ground_station_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(ground_station_id) do
    case Repo.get_by(CommsGroundStationRow,
           organization_id: organization_id,
           mission_id: mission_id,
           ground_station_id: ground_station_id
         ) do
      nil ->
        {:error, :ground_station_not_found}

      %CommsGroundStationRow{lifecycle_state: "archived"} ->
        {:error, :ground_station_not_found}

      %CommsGroundStationRow{} = row ->
        {:ok, CommsGroundStationRow.to_domain(row)}
    end
  end

  @spec list_ground_stations(binary(), binary()) :: [GroundStation.t()]
  def list_ground_stations(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    CommsGroundStationRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.lifecycle_state == "active"
    )
    |> order_by([row], asc: row.display_name, asc: row.ground_station_id)
    |> Repo.all()
    |> Enum.map(&CommsGroundStationRow.to_domain/1)
  end

  @spec update_ground_station(binary(), binary(), binary(), map()) ::
          {:ok, GroundStation.t()} | {:error, term()}
  def update_ground_station(organization_id, mission_id, ground_station_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(ground_station_id) and is_map(attrs) do
    with {:ok, %GroundStation{} = current_ground_station} <-
           fetch_ground_station(organization_id, mission_id, ground_station_id) do
      updated = %GroundStation{
        current_ground_station
        | display_name: Map.get(attrs, :display_name, current_ground_station.display_name),
          provider: Map.get(attrs, :provider, current_ground_station.provider),
          region: Map.get(attrs, :region, current_ground_station.region),
          metadata: Map.get(attrs, :metadata, current_ground_station.metadata)
      }

      update_ground_station_row(updated)
    end
  end

  @spec archive_ground_station(binary(), binary(), binary(), map()) ::
          {:ok, GroundStation.t()} | {:error, term()}
  def archive_ground_station(
        organization_id,
        mission_id,
        ground_station_id,
        metadata_patch \\ %{}
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(ground_station_id) and is_map(metadata_patch) do
    with {:ok, %GroundStation{} = ground_station} <-
           fetch_ground_station(organization_id, mission_id, ground_station_id) do
      archived = %GroundStation{
        ground_station
        | lifecycle_state: :archived,
          metadata:
            ground_station.metadata
            |> Map.merge(metadata_patch)
            |> Map.put("archived_at", DateTime.utc_now())
      }

      update_ground_station_row(archived)
    end
  end

  defp update_ground_station_row(%GroundStation{} = ground_station) do
    changeset = CommsGroundStationRow.changeset(ground_station)

    if changeset.valid? do
      {count, _rows} =
        CommsGroundStationRow
        |> where(
          [row],
          row.organization_id == ^ground_station.organization_id and
            row.mission_id == ^ground_station.mission_id and
            row.ground_station_id == ^ground_station.ground_station_id
        )
        |> Repo.update_all(
          set: [
            lifecycle_state: Atom.to_string(ground_station.lifecycle_state),
            display_name: ground_station.display_name,
            provider: ground_station.provider,
            region: ground_station.region,
            metadata: JsonDocument.wrap_value(ground_station.metadata),
            updated_at: DateTime.utc_now()
          ]
        )

      case count do
        1 -> {:ok, ground_station}
        _other -> {:error, :ground_station_not_found}
      end
    else
      {:error, changeset}
    end
  end

  defp put_organization_scope(%GroundStation{} = ground_station, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case ground_station.organization_id do
      nil ->
        {:ok, %GroundStation{ground_station | organization_id: organization_id}}

      ^organization_id ->
        {:ok, ground_station}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          ground_station.mission_id}}
    end
  end
end
