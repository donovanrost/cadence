defmodule Cadence.GroundNetworks.PredictedPasses.Compute do
  @moduledoc """
  The pass search for a recompute run (#891), with no database access: element sets and stations
  in, pass rows and what could not be predicted out. Spacecraft run in parallel, bounded by the
  schedulers; one SGP4 propagation per grid point serves every station given
  (`Sgp4.Passes.search/5`).

  - A station without an effective location (`GroundStation.effective_location/1`) is skipped.
  - An element set SGP4 refuses (deep space, out of range) or one that decays inside the window
    is recorded in `unpropagated` by spacecraft, with the reason, and yields no passes.
  - A pass with no horizon crossing inside the search bound is counted in `not_bracketed` by
    `"spacecraft_id|ground_station_id"`, never stored.
  """

  alias Cadence.Comms.GroundStation
  alias Cadence.GroundNetworks.ElementSet
  alias Cadence.Ids

  @type row :: %{
          predicted_pass_id: binary(),
          spacecraft_id: binary(),
          ground_station_id: binary(),
          element_set_id: binary(),
          aos: DateTime.t(),
          tca: DateTime.t(),
          los: DateTime.t(),
          max_elevation_deg: float(),
          aos_azimuth_deg: float() | nil,
          los_azimuth_deg: float() | nil
        }

  @type result :: %{
          rows: [row()],
          unpropagated: %{optional(binary()) => binary()},
          not_bracketed: %{optional(binary()) => pos_integer()}
        }

  @doc "The SGP4 stations for the ground stations that have an effective location."
  @spec stations([GroundStation.t()]) :: [Sgp4.Station.t()]
  def stations(ground_stations) do
    for %GroundStation{lifecycle_state: :active} = station <- ground_stations,
        %{} = at <- [GroundStation.effective_location(station)],
        {:ok, sgp4} <- [new_station(station, at)],
        do: sgp4
  end

  defp new_station(station, at) do
    Sgp4.Station.new(
      station.ground_station_id,
      at.latitude_deg,
      at.longitude_deg,
      at.height_m,
      station.elevation_mask_deg
    )
  end

  @doc "Every pass of `element_sets` over `stations` overlapping `[from, to)`."
  @spec run([ElementSet.t()], [Sgp4.Station.t()], DateTime.t(), DateTime.t()) :: result()
  def run(element_sets, stations, from, to) do
    empty = %{rows: [], unpropagated: %{}, not_bracketed: %{}}

    if stations == [] do
      empty
    else
      element_sets
      |> Task.async_stream(&one(&1, stations, from, to),
        max_concurrency: System.schedulers_online(),
        timeout: :infinity,
        ordered: false
      )
      |> Enum.reduce(empty, fn {:ok, outcome}, acc -> merge(acc, outcome) end)
    end
  end

  defp one(%ElementSet{} = set, stations, from, to) do
    with {:ok, sat} <- Sgp4.init(Map.from_struct(set)),
         {:ok, %{passes: passes, unbracketed: unbracketed}} <-
           Sgp4.Passes.search(sat, stations, from, to) do
      {:ok, Enum.map(passes, &row(set, &1)), not_bracketed(set.spacecraft_id, unbracketed)}
    else
      {:error, {reason, %DateTime{}}} ->
        {:unpropagated, set.spacecraft_id, Atom.to_string(reason)}

      {:error, reason} ->
        {:unpropagated, set.spacecraft_id, Atom.to_string(reason)}
    end
  end

  defp row(set, %Sgp4.Pass{} = pass) do
    %{
      predicted_pass_id: Ids.new("predicted_pass"),
      spacecraft_id: set.spacecraft_id,
      ground_station_id: pass.station_id,
      element_set_id: set.element_set_id,
      aos: pass.aos,
      tca: pass.tca,
      los: pass.los,
      max_elevation_deg: pass.max_elevation_deg,
      aos_azimuth_deg: pass.aos_azimuth_deg,
      los_azimuth_deg: pass.los_azimuth_deg
    }
  end

  defp not_bracketed(spacecraft_id, unbracketed) do
    Enum.frequencies_by(unbracketed, fn {:error, :pass_not_bracketed, %{station_id: station}} ->
      key(spacecraft_id, station)
    end)
  end

  defp merge(acc, {:ok, rows, not_bracketed}) do
    %{
      acc
      | rows: rows ++ acc.rows,
        not_bracketed: Map.merge(acc.not_bracketed, not_bracketed, fn _key, a, b -> a + b end)
    }
  end

  defp merge(acc, {:unpropagated, spacecraft_id, reason}),
    do: %{acc | unpropagated: Map.put(acc.unpropagated, spacecraft_id, reason)}

  @doc "The `not_bracketed` key for a spacecraft and station."
  @spec key(binary(), binary()) :: binary()
  def key(spacecraft_id, ground_station_id), do: spacecraft_id <> "|" <> ground_station_id
end
