defmodule CadenceSimulator.Provider.OpportunityGenerator do
  @moduledoc """
  The run's raw opportunities, by the scenario's `orbit_readiness.source_kind`:

    * `"uploaded"` (#893): real passes. Each spacecraft's opportunities are the passes of the
      element set Cadence uploaded (`Ephemeris`) over the scenario's located stations, computed
      with `packages/sgp4` (`PassOpportunities`). The window is the pass, AOS to LOS, clipped to
      the search's end, and carries the pass's maximum elevation and TCA when the window reaches
      the TCA (a window clipped before it carries neither).
    * `"synthetic"` (the default, kept for tests and fault injection): the deterministic hash
      model `deterministic_pass_v1`, a pass every `cadence_seconds` per spacecraft at a hashed
      offset and station.

  Offer ids are stable per run, spacecraft, station and window start (#855) in both models, and
  `restore/5` rebuilds an offer from exactly those, refusing a window the model never offered.
  """

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Ids, PassOpportunities}

  @doc """
  Opportunities for `spacecraft` (inventory maps) over `stations` (`{station, number}`) starting
  in `[starts_at, ends_at)`, ordered by start. `station_numbers?` adds each offer's station number.
  """
  @spec generate(
          map(),
          [map()],
          [{map(), non_neg_integer()}],
          DateTime.t(),
          DateTime.t(),
          boolean()
        ) ::
          [map()]
  def generate(run, spacecraft, stations, starts_at, ends_at, station_numbers?) do
    if PassOpportunities.uploaded?(run),
      do: from_passes(run, spacecraft, stations, starts_at, ends_at, station_numbers?),
      else: synthetic(run, spacecraft, stations, starts_at, ends_at, station_numbers?)
  end

  @doc "Rebuilds an offer from its spacecraft number, station number and window."
  @spec restore(map(), integer(), integer(), integer(), integer()) ::
          {:ok, map()} | {:error, :not_found}
  def restore(run, spacecraft_number, station_number, start_unix, end_unix) do
    scenario = run["scenario_snapshot"]

    with true <- spacecraft_number in 1..scenario["spacecraft_count"],
         %{} = station <- Enum.at(scenario["ground_stations"], station_number),
         true <- end_unix > start_unix,
         spacecraft_id = Provider.configured_spacecraft_id(scenario, spacecraft_number),
         {:ok, extra} <-
           restorable(run, spacecraft_id, station_number, start_unix, end_unix),
         {:ok, starts_at} <- DateTime.from_unix(start_unix),
         {:ok, ends_at} <- DateTime.from_unix(end_unix) do
      {:ok,
       run
       |> opportunity(spacecraft_id, station, start_unix, starts_at, ends_at)
       |> Map.merge(extra)}
    else
      _invalid -> {:error, :not_found}
    end
  end

  # A pass-backed offer exists only if a pass for that station starts exactly then and the
  # window ends by its LOS; a synthetic one only on the spacecraft's cadence grid.
  defp restorable(run, spacecraft_id, station_number, start_unix, end_unix) do
    if PassOpportunities.uploaded?(run) do
      case PassOpportunities.pass_at(run, spacecraft_id, station_number, start_unix) do
        %{los_unix: los} = pass when end_unix <= los -> {:ok, pass_fields(pass, end_unix)}
        _none -> :error
      end
    else
      {cadence, duration, jitter} = pass_parameters(run)
      offset = pass_offset(run, spacecraft_id, cadence, jitter)

      if end_unix - start_unix <= duration and rem(start_unix - offset, cadence) == 0,
        do: {:ok, %{}},
        else: :error
    end
  end

  defp from_passes(run, spacecraft, stations, starts_at, ends_at, station_numbers?) do
    end_unix = DateTime.to_unix(ends_at)
    by_number = Map.new(stations, fn {station, number} -> {number, station} end)

    for craft <- spacecraft,
        stations != [],
        pass <-
          PassOpportunities.passes(run, craft["id"], Map.keys(by_number), starts_at, ends_at) do
      station = Map.fetch!(by_number, pass.station_number)
      window_end = min(pass.los_unix, end_unix)

      offer =
        run
        |> opportunity(
          craft["id"],
          station,
          pass.aos_unix,
          DateTime.from_unix!(pass.aos_unix),
          DateTime.from_unix!(window_end)
        )
        |> Map.merge(pass_fields(pass, window_end))

      if station_numbers?, do: Map.put(offer, "station_number", pass.station_number), else: offer
    end
    |> Enum.sort_by(&{&1["starts_at"], &1["spacecraft_id"], &1["ground_station_id"]})
  end

  # The geometry describes the offered window: an offer clipped before the pass's TCA never
  # reaches its peak, so it carries no TCA or maximum elevation rather than the full pass's.
  defp pass_fields(pass, window_end) do
    if DateTime.to_unix(pass.tca) <= window_end do
      %{
        "model" => "sgp4_pass_v1",
        "max_elevation_deg" => pass.max_elevation_deg,
        "tca" => DateTime.to_iso8601(pass.tca)
      }
    else
      %{"model" => "sgp4_pass_v1", "max_elevation_deg" => nil, "tca" => nil}
    end
  end

  defp synthetic(run, spacecraft, stations, starts_at, ends_at, station_numbers?) do
    {cadence, duration, jitter} = pass_parameters(run)
    start_unix = DateTime.to_unix(starts_at)
    end_unix = DateTime.to_unix(ends_at)

    for craft <- spacecraft,
        stations != [],
        window_start <- opportunity_starts(run, craft, start_unix, end_unix, cadence, jitter),
        {station, number} =
          Enum.at(stations, rem(:erlang.phash2({craft["id"], window_start}), length(stations))),
        window_end = min(window_start + duration, end_unix) do
      offer =
        opportunity(
          run,
          craft["id"],
          station,
          window_start,
          DateTime.from_unix!(window_start),
          DateTime.from_unix!(window_end)
        )

      if station_numbers?, do: Map.put(offer, "station_number", number), else: offer
    end
    |> Enum.sort_by(& &1["starts_at"])
  end

  defp opportunity(run, spacecraft_id, station, start_unix, starts_at, ends_at) do
    antenna_index = rem(:erlang.phash2({start_unix, spacecraft_id}), station["antenna_count"])

    %{
      "id" =>
        Ids.stable("opportunity", [
          run["id"],
          spacecraft_id,
          station["id"],
          Integer.to_string(start_unix)
        ]),
      "run_id" => run["id"],
      "spacecraft_id" => spacecraft_id,
      "ground_station_id" => station["id"],
      "antenna_id" => "#{station["id"]}-antenna-#{antenna_index + 1}",
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => DateTime.to_iso8601(ends_at),
      "synthetic" => true,
      "model" => "deterministic_pass_v1"
    }
  end

  defp pass_parameters(run) do
    pass_model = run["scenario_snapshot"]["pass_model"]
    speed = run["speed"]

    {max(10, round(pass_model["cadence_seconds"] / speed)),
     max(5, round(pass_model["duration_seconds"] / speed)),
     max(0, round(pass_model["jitter_seconds"] / speed))}
  end

  defp opportunity_starts(run, craft, start_unix, end_unix, cadence, jitter) do
    offset = pass_offset(run, craft["id"], cadence, jitter)
    first = start_unix + rem(cadence - rem(start_unix - offset, cadence), cadence)

    Stream.iterate(first, &(&1 + cadence))
    |> Enum.take_while(&(&1 < end_unix))
  end

  defp pass_offset(run, spacecraft_id, cadence, jitter) do
    base = rem(:erlang.phash2({run["seed"], spacecraft_id}), cadence)
    variation = rem(:erlang.phash2({spacecraft_id, run["seed"], :jitter}), jitter * 2 + 1)
    max(0, base + variation - jitter)
  end
end
