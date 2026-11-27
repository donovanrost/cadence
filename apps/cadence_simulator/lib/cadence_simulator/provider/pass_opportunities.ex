defmodule CadenceSimulator.Provider.PassOpportunities do
  @moduledoc """
  Real passes for `orbit_readiness.source_kind: "uploaded"` (#893): the element set Cadence
  uploaded for a spacecraft (`Ephemeris`), propagated with `packages/sgp4` over the scenario's
  located stations (each with its `elevation_mask_deg`, 5° by default). A station without a
  location has no passes; a spacecraft without an upload has none.

  Passes are computed per UTC day: one `Sgp4.Passes.search/5` over all located stations (one
  propagation serves them all), keeping the passes whose AOS falls in that day, cached by run,
  spacecraft, upload content hash and day (`PassCache`). A pass therefore comes from exactly one
  computation whatever window is searched, so its whole-second AOS and LOS are the same in every
  search and when an offer is restored from its id. A pass the search couldn't bracket is skipped.
  """

  alias CadenceSimulator.Provider.{Ephemeris, PassCache}

  @day 86_400
  @default_mask_deg 5.0

  @type pass :: %{
          station_number: non_neg_integer(),
          aos_unix: integer(),
          los_unix: integer(),
          tca: DateTime.t(),
          max_elevation_deg: float()
        }

  @doc "Whether the run's scenario takes its orbits from Cadence's uploads."
  @spec uploaded?(map()) :: boolean()
  def uploaded?(run),
    do: get_in(run, ["scenario_snapshot", "orbit_readiness", "source_kind"]) == "uploaded"

  @doc """
  The spacecraft's passes over the given station numbers whose AOS is in `[starts_at, ends_at)`,
  ordered by AOS.
  """
  @spec passes(map(), binary(), [non_neg_integer()], DateTime.t(), DateTime.t()) :: [pass()]
  def passes(run, spacecraft_id, station_numbers, starts_at, ends_at) do
    from = DateTime.to_unix(starts_at)
    to = DateTime.to_unix(ends_at)
    wanted = MapSet.new(station_numbers)

    case Ephemeris.fetch(run, spacecraft_id) do
      {:ok, upload} ->
        from
        |> days(to)
        |> Enum.flat_map(&day_passes(run, spacecraft_id, upload, &1))
        |> Enum.filter(
          &(&1.aos_unix >= from and &1.aos_unix < to and MapSet.member?(wanted, &1.station_number))
        )
        |> Enum.sort_by(&{&1.aos_unix, &1.station_number})

      {:error, :not_found} ->
        []
    end
  end

  @doc "The spacecraft's pass over station `station_number` whose AOS is exactly `aos_unix`."
  @spec pass_at(map(), binary(), non_neg_integer(), integer()) :: pass() | nil
  def pass_at(run, spacecraft_id, station_number, aos_unix) do
    case Ephemeris.fetch(run, spacecraft_id) do
      {:ok, upload} ->
        run
        |> day_passes(spacecraft_id, upload, aos_unix - Integer.mod(aos_unix, @day))
        |> Enum.find(&(&1.station_number == station_number and &1.aos_unix == aos_unix))

      {:error, :not_found} ->
        nil
    end
  end

  defp days(from, to) do
    first = from - Integer.mod(from, @day)
    first |> Stream.iterate(&(&1 + @day)) |> Enum.take_while(&(&1 < to))
  end

  # The key includes a fingerprint of the run's station geometry: a run id is reused when a run is
  # recreated (Store.clear, the Earendil seed's fixed id), possibly with other stations.
  defp day_passes(run, spacecraft_id, upload, day) do
    stations = stations(run)
    key = {run["id"], spacecraft_id, upload["content_sha256"], fingerprint(stations), day}
    PassCache.fetch(key, fn -> compute(stations, upload, day) end)
  end

  defp fingerprint(stations) do
    stations
    |> Enum.map(&{&1.id, &1.latitude_deg, &1.longitude_deg, &1.height_m, &1.mask_deg})
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp compute(stations, upload, day) do
    with {:ok, sat} <- satellite(upload),
         [_ | _] <- stations,
         {:ok, %{passes: passes}} <-
           Sgp4.Passes.search(
             sat,
             stations,
             DateTime.from_unix!(day),
             DateTime.from_unix!(day + @day)
           ) do
      for pass <- passes,
          aos = DateTime.to_unix(pass.aos),
          los = DateTime.to_unix(pass.los),
          aos >= day and aos < day + @day and los > aos do
        %{
          station_number: pass.station_id,
          aos_unix: aos,
          los_unix: los,
          tca: DateTime.truncate(pass.tca, :second),
          max_elevation_deg: Float.round(pass.max_elevation_deg, 2)
        }
      end
    else
      _no_passes -> []
    end
  end

  # The uploaded OMM is validated on upload (`Ephemeris.put/3`); B* is optional.
  defp satellite(%{"omm" => omm, "epoch" => epoch}) do
    {:ok, epoch, _offset} = DateTime.from_iso8601(epoch)

    Sgp4.init(%{
      epoch: epoch,
      mean_motion: omm["MEAN_MOTION"],
      eccentricity: omm["ECCENTRICITY"],
      inclination_deg: omm["INCLINATION"],
      raan_deg: omm["RA_OF_ASC_NODE"],
      arg_perigee_deg: omm["ARG_OF_PERICENTER"],
      mean_anomaly_deg: omm["MEAN_ANOMALY"],
      bstar: if(is_number(omm["BSTAR"]), do: omm["BSTAR"], else: 0.0)
    })
  end

  # The scenario's located stations, each identified by its position in the scenario.
  defp stations(run) do
    for {%{"location" => location} = station, number} <-
          Enum.with_index(run["scenario_snapshot"]["ground_stations"]),
        {:ok, sgp4} <- [
          Sgp4.Station.new(
            number,
            location["latitude_deg"],
            location["longitude_deg"],
            Map.get(location, "height_m", 0.0),
            mask(station)
          )
        ],
        do: sgp4
  end

  defp mask(%{"elevation_mask_deg" => mask}) when is_number(mask), do: mask
  defp mask(_station), do: @default_mask_deg
end
