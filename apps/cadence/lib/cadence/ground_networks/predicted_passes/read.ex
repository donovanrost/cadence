defmodule Cadence.GroundNetworks.PredictedPasses.Read do
  @moduledoc """
  Pages of predicted passes by mission and window (#891, contract docs/apogee/api/predicted-passes.md).

  A page holds the passes that overlap `[from, to)` (`los > from` and `aos < to`, so a pass
  already in view is included), optionally for one station or one spacecraft, in AOS-then-id
  order. The cursor carries the last row's `{aos, id}`. No pass lasts a day (the search bounds
  one by the synodic period, under 270 minutes for a near-earth orbit), so `aos > from − 1 day`
  lets the AOS indexes bound the scan.

  A page costs a fixed number of queries whatever the fleet size: the page, its spacecraft and
  stations by id, its element-set epochs, and the coverage aggregates.
  """

  import Ecto.Query

  alias Cadence.Comms.{GroundStation, GroundStationStore}
  alias Cadence.GroundNetworks.ElementSets
  alias Cadence.GroundNetworks.PredictedPasses.{PredictedPassRow, Store}
  alias Cadence.Repo
  alias Cadence.SpacecraftStore

  @lookback_s 86_400

  @type filters :: %{
          from: DateTime.t(),
          to: DateTime.t(),
          station_id: binary() | nil,
          spacecraft_id: binary() | nil,
          cursor: {DateTime.t(), binary()} | nil,
          limit: pos_integer()
        }

  @spec page(binary(), binary(), filters()) :: map()
  def page(org, mission, filters) do
    rows =
      org
      |> window(mission, filters)
      |> limit(^(filters.limit + 1))
      |> Repo.all()

    {page, rest} = Enum.split(rows, filters.limit)
    stations = stations(org, mission)

    %{
      passes: Enum.map(page, &PredictedPassRow.to_domain/1),
      next_cursor: if(rest == [], do: nil, else: encode(List.last(page))),
      spacecraft: spacecraft(org, mission, page),
      stations: stations,
      element_set_epochs:
        ElementSets.epochs(org, mission, page |> Enum.map(& &1.element_set_id) |> Enum.uniq()),
      coverage: coverage(org, mission, filters, Map.values(stations))
    }
  end

  defp window(org, mission, filters) do
    from(row in PredictedPassRow,
      where:
        row.organization_id == ^org and row.mission_id == ^mission and
          row.aos > ^DateTime.add(filters.from, -@lookback_s) and row.aos < ^filters.to and
          row.los > ^filters.from,
      order_by: [asc: row.aos, asc: row.predicted_pass_id]
    )
    |> filter(:ground_station_id, filters.station_id)
    |> filter(:spacecraft_id, filters.spacecraft_id)
    |> after_cursor(filters.cursor)
  end

  defp filter(query, _field, nil), do: query
  defp filter(query, field, id), do: where(query, [row], field(row, ^field) == ^id)

  defp after_cursor(query, nil), do: query

  defp after_cursor(query, {aos, id}),
    do: where(query, [row], row.aos > ^aos or (row.aos == ^aos and row.predicted_pass_id > ^id))

  defp spacecraft(_org, _mission, []), do: %{}

  defp spacecraft(org, mission, page) do
    ids = page |> Enum.map(& &1.spacecraft_id) |> Enum.uniq()

    case SpacecraftStore.fetch_spacecrafts_in_batches(org, mission, ids) do
      {:ok, found} -> found
      {:error, _reason} -> %{}
    end
  end

  # Archived stations included: a page may still show passes over one until its job runs.
  defp stations(org, mission) do
    org
    |> GroundStationStore.list_ground_stations(mission, include_archived: true)
    |> Map.new(&{&1.ground_station_id, &1})
  end

  @doc """
  What could not be predicted, scoped like the page: `spacecraft_id` narrows the spacecraft
  counts and `station_id` the station count; `passes_not_bracketed` follows both.
  """
  @spec coverage(binary(), binary(), filters(), [GroundStation.t()]) :: map()
  def coverage(org, mission, filters, stations) do
    state = Store.state(org, mission)

    spacecraft_ids =
      case filters.spacecraft_id do
        nil -> org |> SpacecraftStore.active_identities(mission) |> Enum.map(& &1.id)
        id -> [id]
      end

    %{
      horizon_end: state && state.horizon_end,
      computed_at: state && state.computed_at,
      unpredicted: %{
        spacecraft_without_element_set: without_set(org, mission, spacecraft_ids),
        spacecraft_deep_space: deep_space(state, filters.spacecraft_id),
        stations_without_location: without_location(stations, filters.station_id),
        passes_not_bracketed: not_bracketed(state, filters)
      }
    }
  end

  defp without_set(_org, _mission, []), do: 0

  defp without_set(org, mission, ids),
    do: length(ids) - ElementSets.count_with_sets(org, mission, ids)

  defp deep_space(nil, _spacecraft_id), do: 0

  defp deep_space(state, spacecraft_id) do
    Enum.count(state.unpropagated, fn {id, reason} ->
      reason == "deep_space_not_supported" and (spacecraft_id == nil or id == spacecraft_id)
    end)
  end

  defp without_location(stations, station_id) do
    Enum.count(stations, fn station ->
      station.lifecycle_state == :active and
        (station_id == nil or station.ground_station_id == station_id) and
        GroundStation.effective_location(station) == nil
    end)
  end

  defp not_bracketed(nil, _filters), do: 0

  defp not_bracketed(state, filters) do
    state.not_bracketed
    |> Enum.filter(fn {key, _count} ->
      [spacecraft, station] = String.split(key, "|", parts: 2)

      (filters.spacecraft_id == nil or spacecraft == filters.spacecraft_id) and
        (filters.station_id == nil or station == filters.station_id)
    end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.sum()
  end

  @spec encode(%{aos: DateTime.t(), predicted_pass_id: binary()}) :: binary()
  def encode(%{aos: aos, predicted_pass_id: id}),
    do: [DateTime.to_iso8601(aos), id] |> Jason.encode!() |> Base.url_encode64(padding: false)

  @spec decode(binary() | nil) :: {:ok, {DateTime.t(), binary()} | nil} | :error
  def decode(nil), do: {:ok, nil}

  def decode(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, [iso, id]} when is_binary(iso) and is_binary(id) <- Jason.decode(json),
         {:ok, aos, 0} <- DateTime.from_iso8601(iso) do
      {:ok, {aos, id}}
    else
      _invalid -> :error
    end
  end

  def decode(_cursor), do: :error
end
