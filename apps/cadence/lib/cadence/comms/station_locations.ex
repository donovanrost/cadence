defmodule Cadence.Comms.StationLocations do
  @moduledoc """
  Station locations from a provider's inventory sync (#890). A listed station may carry
  `"location" => %{"latitude_deg", "longitude_deg", "height_m"}` (WGS84 geodetic, degrees and
  metres; height defaults to 0). Stations are matched by id, as `ProviderReports` matches them.

  The report is stored in the station's `provider_*` columns only. The mission's own location
  (set through the `ground_station` change-set kind) is never written here, and when it is set
  it is the one pass prediction uses (`GroundStation.effective_location/1`).

  A sync is the provider's whole inventory, so it is authoritative for that provider's reports:

    * a listed station with a valid location gets it, with `provider_location_reported_at` set to
      the sync time (a repeated identical report refreshes the time);
    * a station whose report came from this provider and that is now listed without a location,
      with a malformed one, or not listed at all has its report cleared. Stale geometry would
      otherwise keep driving pass prediction with no sign that the provider stopped reporting it.

  A report from another provider is left alone. A malformed location is never raised on: the
  inventory is the provider's data.
  """

  import Ecto.Query

  alias Cadence.Comms.{GroundStation, GroundStationRow, GroundStationStore}
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  @spec record_provider_reports(String.t(), String.t(), String.t(), [map()], DateTime.t()) ::
          {:ok, %{recorded: non_neg_integer(), cleared: non_neg_integer()}}
          | {:error, :invalid_provider_inventory}
  def record_provider_reports(_organization_id, _mission_id, _provider_id, stations, _synced_at)
      when not is_list(stations),
      do: {:error, :invalid_provider_inventory}

  def record_provider_reports(organization_id, mission_id, provider_id, stations, synced_at) do
    current =
      organization_id
      |> GroundStationStore.list_ground_stations(mission_id)
      |> Map.new(&{&1.ground_station_id, &1})

    reported =
      for %{"id" => station_id} = station <- stations,
          Map.has_key?(current, station_id),
          {:ok, location} <- [location(station["location"])],
          into: %{},
          do: {station_id, location}

    changed =
      Enum.count(reported, fn {station_id, location} ->
        record(organization_id, mission_id, station_id, location, provider_id, synced_at)
        changed?(Map.fetch!(current, station_id), location, provider_id)
      end)

    stale =
      for {station_id, %GroundStation{provider_location: %{provider_id: ^provider_id}}} <- current,
          not Map.has_key?(reported, station_id),
          do: station_id

    cleared = clear(organization_id, mission_id, stale)

    if changed + cleared > 0,
      do: ScopedReadUpdates.publish(:stations_changed, organization_id, mission_id)

    {:ok, %{recorded: changed, cleared: cleared}}
  end

  @doc "A reported location, validated: `{:ok, %{latitude_deg, longitude_deg, height_m}}`."
  @spec location(term()) :: {:ok, GroundStation.location()} | :error
  def location(%{"latitude_deg" => lat, "longitude_deg" => lon} = location)
      when is_number(lat) and is_number(lon) do
    height = Map.get(location, "height_m", 0)

    if is_number(height) and lat >= -90 and lat <= 90 and lon >= -180 and lon <= 180 and
         height >= -1000 and height <= 10_000,
       do: {:ok, %{latitude_deg: lat * 1.0, longitude_deg: lon * 1.0, height_m: height * 1.0}},
       else: :error
  end

  def location(_location), do: :error

  defp changed?(%GroundStation{provider_location: nil}, _location, _provider_id), do: true

  defp changed?(%GroundStation{provider_location: previous}, location, provider_id) do
    Map.take(previous, [:latitude_deg, :longitude_deg, :height_m]) != location or
      previous.provider_id != provider_id
  end

  defp record(organization_id, mission_id, station_id, location, provider_id, synced_at) do
    organization_id
    |> station_query(mission_id, [station_id])
    |> Repo.update_all(
      set: [
        provider_latitude_deg: location.latitude_deg,
        provider_longitude_deg: location.longitude_deg,
        provider_height_m: location.height_m,
        provider_location_provider_id: provider_id,
        provider_location_reported_at: synced_at
      ]
    )
  end

  defp clear(_organization_id, _mission_id, []), do: 0

  defp clear(organization_id, mission_id, station_ids) do
    {count, _rows} =
      organization_id
      |> station_query(mission_id, station_ids)
      |> Repo.update_all(
        set: [
          provider_latitude_deg: nil,
          provider_longitude_deg: nil,
          provider_height_m: nil,
          provider_location_provider_id: nil,
          provider_location_reported_at: nil
        ]
      )

    count
  end

  defp station_query(organization_id, mission_id, station_ids) do
    where(
      GroundStationRow,
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.ground_station_id in ^station_ids
    )
  end
end
