defmodule Cadence.Comms.StationRefs do
  @moduledoc """
  A provider's station ref (`ground_station_ref`) resolved to the Cadence ground
  station it names, for console reads: `%{ref, id, code, name}`. A station
  matches by its id, its `code` (the model field; legacy `metadata.code`) or
  `metadata.provider_station_ref`; `id`, `code` and `name` are nil when
  nothing matches. `code` is the same one Setup › Ground stations shows.
  """

  alias Cadence.Comms.{GroundStation, GroundStationStore}

  @type station :: %{
          ref: binary() | nil,
          id: binary() | nil,
          code: binary() | nil,
          name: binary() | nil
        }
  @type index :: %{optional(binary()) => map()}

  @spec index(binary(), binary()) :: index()
  def index(organization_id, mission_id),
    do: organization_id |> GroundStationStore.list_ground_stations(mission_id) |> build()

  @doc "Pure: the lookup over a station list."
  @spec build([GroundStation.t()]) :: index()
  def build(stations) do
    Enum.reduce(stations, %{}, fn %GroundStation{} = station, acc ->
      code = station.code || text(station.metadata, "code")

      [station.ground_station_id, code, text(station.metadata, "provider_station_ref")]
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(
        acc,
        &Map.put_new(&2, &1, %{
          id: station.ground_station_id,
          code: code,
          name: station.display_name
        })
      )
    end)
  end

  @spec resolve(binary() | nil, index()) :: station()
  def resolve(nil, _index), do: %{ref: nil, id: nil, code: nil, name: nil}

  def resolve(ref, index),
    do: Map.merge(%{ref: ref, id: nil, code: nil, name: nil}, Map.get(index, ref, %{}))

  @doc "The stored station refs a filter matches by ref, resolved ID or code."
  def matching_refs(_index, nil), do: nil

  def matching_refs(index, station) do
    aliases = for {ref, resolved} <- index, station in [resolved.id, resolved.code], do: ref
    Enum.uniq([station | aliases])
  end

  @doc "The station of a contact opportunity snapshot."
  @spec of_snapshot(map(), index()) :: station()
  def of_snapshot(snapshot, index),
    do: resolve(text(snapshot.normalized_opportunity_document, "ground_station_ref"), index)

  defp text(%{} = map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp text(_map, _key), do: nil
end
