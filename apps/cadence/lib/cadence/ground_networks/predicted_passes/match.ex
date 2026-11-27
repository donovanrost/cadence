defmodule Cadence.GroundNetworks.PredictedPasses.Match do
  @moduledoc """
  Matches booking, contact and opportunity windows to predicted passes (#892, slice 4 of #732).

  A window matches the predicted pass of the same spacecraft and station whose window overlaps it
  (`los > starts_at and aos < ends_at`). When more than one overlaps, the longest overlap wins,
  then the earliest AOS, then the lowest id. `match/3` answers a whole page in ONE query (a
  lateral join over the page's windows), never one per row.

  `predictable/3` says, per window, whether prediction covers it, so a missing match means
  something: the spacecraft has a current element set that was propagated (not deep space or
  decayed) and was stored before the mission's last prediction run, the station is active and
  located, and the window lies inside what has been predicted (it ends by the horizon end). A
  window outside that is neither matched nor "no predicted pass": prediction can't say.
  """

  alias Cadence.Comms.{GroundStation, GroundStationStore}
  alias Cadence.GroundNetworks.ElementSets
  alias Cadence.GroundNetworks.PredictedPasses.Store
  alias Cadence.Repo

  @type window :: %{
          required(:key) => term(),
          required(:spacecraft_id) => binary() | nil,
          required(:ground_station_id) => binary() | nil,
          required(:starts_at) => DateTime.t() | nil,
          required(:ends_at) => DateTime.t() | nil
        }

  @type match :: %{
          predicted_pass_id: binary(),
          max_elevation_deg: float(),
          tca: DateTime.t()
        }

  @sql """
  SELECT w.k, p.predicted_pass_id, p.max_elevation_deg, p.tca
  FROM unnest($3::int[], $4::text[], $5::text[], $6::timestamp[], $7::timestamp[])
    AS w(k, spacecraft_id, ground_station_id, starts_at, ends_at)
  CROSS JOIN LATERAL (
    SELECT pp.predicted_pass_id, pp.max_elevation_deg, pp.tca
    FROM predicted_passes pp
    WHERE pp.organization_id = $1 AND pp.mission_id = $2
      AND pp.spacecraft_id = w.spacecraft_id AND pp.ground_station_id = w.ground_station_id
      AND pp.los > w.starts_at AND pp.aos < w.ends_at
    ORDER BY LEAST(pp.los, w.ends_at) - GREATEST(pp.aos, w.starts_at) DESC,
      pp.aos, pp.predicted_pass_id
    LIMIT 1
  ) p
  """

  @doc "The predicted pass each window matches, by key (one query; unmatched keys are absent)."
  @spec match(binary(), binary(), [window()]) :: %{optional(term()) => match()}
  def match(organization_id, mission_id, windows) do
    indexed = windows |> Enum.filter(&complete?/1) |> Enum.with_index()

    case indexed do
      [] -> %{}
      _windows -> query(organization_id, mission_id, indexed)
    end
  end

  @doc """
  The keys of the windows prediction covers (see the moduledoc): only for those does a missing
  match mean the provider offers a window no predicted pass backs.
  """
  @spec predictable(binary(), binary(), [window()]) :: MapSet.t()
  def predictable(organization_id, mission_id, windows) do
    windows = Enum.filter(windows, &complete?/1)

    with [_ | _] <- windows,
         %{horizon_end: %DateTime{} = horizon_end, computed_at: %DateTime{} = computed_at} =
           state <- Store.state(organization_id, mission_id) do
      spacecraft = propagated(organization_id, mission_id, windows, state, computed_at)
      stations = located(organization_id, mission_id)

      for window <- windows,
          MapSet.member?(spacecraft, window.spacecraft_id),
          MapSet.member?(stations, window.ground_station_id),
          DateTime.compare(window.ends_at, horizon_end) != :gt,
          into: MapSet.new(),
          do: window.key
    else
      _uncovered -> MapSet.new()
    end
  end

  defp query(organization_id, mission_id, indexed) do
    {keys, spacecraft, stations, starts, ends} =
      Enum.reduce(Enum.reverse(indexed), {[], [], [], [], []}, fn {window, i},
                                                                  {k, sc, st, a, b} ->
        {[i | k], [window.spacecraft_id | sc], [window.ground_station_id | st],
         [naive(window.starts_at) | a], [naive(window.ends_at) | b]}
      end)

    by_index = Map.new(indexed, fn {window, i} -> {i, window.key} end)

    %{rows: rows} =
      Repo.query!(@sql, [organization_id, mission_id, keys, spacecraft, stations, starts, ends])

    Map.new(rows, fn [i, id, elevation, tca] ->
      {Map.fetch!(by_index, i),
       %{predicted_pass_id: id, max_elevation_deg: elevation, tca: utc(tca)}}
    end)
  end

  # Spacecraft whose current element set the last run could propagate: stored before that run,
  # and not recorded as unpropagated (deep space, decayed).
  defp propagated(organization_id, mission_id, windows, state, computed_at) do
    ids = windows |> Enum.map(& &1.spacecraft_id) |> Enum.uniq()

    for set <- ElementSets.current_for(organization_id, mission_id, ids),
        DateTime.compare(set.received_at, computed_at) != :gt,
        not Map.has_key?(state.unpropagated || %{}, set.spacecraft_id),
        into: MapSet.new(),
        do: set.spacecraft_id
  end

  defp located(organization_id, mission_id) do
    for station <- GroundStationStore.list_ground_stations(organization_id, mission_id),
        station.lifecycle_state == :active,
        GroundStation.effective_location(station) != nil,
        into: MapSet.new(),
        do: station.ground_station_id
  end

  defp complete?(window) do
    is_binary(window.spacecraft_id) and is_binary(window.ground_station_id) and
      match?(%DateTime{}, window.starts_at) and match?(%DateTime{}, window.ends_at) and
      DateTime.before?(window.starts_at, window.ends_at)
  end

  defp naive(%DateTime{} = at), do: at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_naive()

  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp utc(%DateTime{} = at), do: at
end
