defmodule Cadence.Comms.GroundStationRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Comms.GroundStation
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  schema "comms_ground_stations" do
    field(:ground_station_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:lifecycle_state, :string)
    field(:display_name, :string)
    field(:code, :string)
    field(:provider, :string)
    field(:region, :string)
    field(:metadata, :map, default: %{})
    field(:latitude_deg, :float)
    field(:longitude_deg, :float)
    field(:height_m, :float)
    field(:elevation_mask_deg, :float, default: 5.0)
    field(:provider_latitude_deg, :float)
    field(:provider_longitude_deg, :float)
    field(:provider_height_m, :float)
    field(:provider_location_provider_id, :string)
    field(:provider_location_reported_at, :utc_datetime_usec)

    timestamps()
  end

  @required_fields [
    :ground_station_id,
    :mission_id,
    :lifecycle_state,
    :display_name,
    :metadata
  ]

  @spec changeset(GroundStation.t()) :: Ecto.Changeset.t()
  def changeset(%GroundStation{} = ground_station) do
    %__MODULE__{}
    |> cast(domain_attrs(ground_station), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_format(:ground_station_id, ~r/^[A-Za-z0-9][A-Za-z0-9_.:-]*$/)
    |> validate_length(:ground_station_id, min: 1, max: 120)
    |> validate_length(:display_name, min: 1, max: 200)
    |> validate_format(:code, ~r/^[A-Z0-9]{2,8}$/)
    |> unique_constraint([:mission_id, :ground_station_id],
      name: :comms_ground_stations_scope_idx
    )
    |> check_constraint(:latitude_deg, name: :comms_ground_stations_location_range)
    |> check_constraint(:latitude_deg, name: :comms_ground_stations_location_complete)
    |> check_constraint(:elevation_mask_deg, name: :comms_ground_stations_elevation_mask_range)
  end

  @spec to_domain(struct()) :: GroundStation.t()
  def to_domain(%__MODULE__{} = row) do
    GroundStation.new(%{
      ground_station_id: row.ground_station_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      lifecycle_state: row.lifecycle_state,
      display_name: row.display_name,
      code: row.code,
      provider: row.provider,
      region: row.region,
      metadata: JsonDocument.unwrap_value(row.metadata),
      location: location(row.latitude_deg, row.longitude_deg, row.height_m),
      elevation_mask_deg: row.elevation_mask_deg,
      provider_location: provider_location(row)
    })
  end

  defp location(lat, lon, height) when is_float(lat) and is_float(lon) and is_float(height),
    do: %{latitude_deg: lat, longitude_deg: lon, height_m: height}

  defp location(_lat, _lon, _height), do: nil

  defp provider_location(row) do
    case location(row.provider_latitude_deg, row.provider_longitude_deg, row.provider_height_m) do
      nil ->
        nil

      location ->
        Map.merge(location, %{
          provider_id: row.provider_location_provider_id,
          reported_at: row.provider_location_reported_at
        })
    end
  end

  @doc "The mission-owned geometry columns of `station`, as a changeset or update sets them."
  @spec geometry_columns(GroundStation.t()) :: keyword()
  def geometry_columns(%GroundStation{location: location, elevation_mask_deg: mask}) do
    location = location || %{}

    [
      latitude_deg: Map.get(location, :latitude_deg),
      longitude_deg: Map.get(location, :longitude_deg),
      height_m: Map.get(location, :height_m),
      elevation_mask_deg: mask
    ]
  end

  defp domain_attrs(%GroundStation{} = ground_station) do
    %{
      ground_station_id: ground_station.ground_station_id,
      organization_id: ground_station.organization_id,
      mission_id: ground_station.mission_id,
      lifecycle_state: Atom.to_string(ground_station.lifecycle_state),
      display_name: ground_station.display_name,
      code: ground_station.code,
      provider: ground_station.provider,
      region: ground_station.region,
      metadata: JsonDocument.wrap_value(ground_station.metadata)
    }
    |> Map.merge(Map.new(geometry_columns(ground_station)))
  end

  defp all_fields do
    [
      :ground_station_id,
      :organization_id,
      :mission_id,
      :lifecycle_state,
      :display_name,
      :code,
      :provider,
      :region,
      :metadata,
      :latitude_deg,
      :longitude_deg,
      :height_m,
      :elevation_mask_deg
    ]
  end
end
