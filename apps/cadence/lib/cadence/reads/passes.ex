defmodule Cadence.Reads.Passes do
  @moduledoc """
  Passes in a time window for the console (ops M7 = scheduling S1): one row per
  provider reservation whose window overlaps `[from, to)`.

  Station and antenna come from the reservation's newest snapshot (Cadence
  accepted, then provider confirmed, then requested). The station is matched to
  a Cadence ground station by id or code when possible. Nothing is derived:
  elevation, cost and uplink capability are `nil` unless the provider supplied
  them, because there is no orbit propagation (DECISIONS #4).

  Provider opportunities (windows not yet booked) are not listed here; they
  need a live provider search per spacecraft.
  """

  alias Cadence.Comms.{GroundStation, GroundStationStore}
  alias Cadence.Contacts.ProviderReservation
  alias Cadence.Control.Contacts

  @default_limit 500
  @snapshots [
    :cadence_accepted_snapshot_document,
    :provider_confirmed_snapshot_document,
    :requested_snapshot_document
  ]

  @type filters :: %{
          optional(:spacecraft_id) => binary() | nil,
          optional(:station) => binary() | nil,
          optional(:states) => [binary()] | nil,
          optional(:limit) => pos_integer()
        }

  @spec load(binary(), binary(), DateTime.t(), DateTime.t(), filters()) :: map()
  def load(organization_id, mission_id, from, to, filters \\ %{}) do
    {reservations, truncated?} =
      Contacts.list_provider_reservations_in_window(organization_id, mission_id, from, to,
        spacecraft_id: Map.get(filters, :spacecraft_id),
        limit: Map.get(filters, :limit, @default_limit)
      )

    build(%{
      from: from,
      to: to,
      reservations: reservations,
      truncated: truncated?,
      stations: GroundStationStore.list_ground_stations(organization_id, mission_id),
      filters: filters
    })
  end

  @doc "Pure builder; see `load/5`."
  @spec build(map()) :: map()
  def build(%{reservations: reservations, stations: stations, filters: filters} = input) do
    index = station_index(stations)
    states = filters |> Map.get(:states) |> List.wrap() |> MapSet.new()
    station = Map.get(filters, :station)

    passes =
      reservations
      |> Enum.map(&row(&1, index))
      |> Enum.filter(&(state_match?(&1, states) and station_match?(&1, station)))

    %{from: input.from, to: input.to, truncated: input.truncated, passes: passes}
  end

  defp state_match?(pass, states), do: MapSet.size(states) == 0 or pass.state in states

  defp station_match?(_pass, nil), do: true

  defp station_match?(pass, station),
    do: station in [pass.station.ref, pass.station.id, pass.station.code]

  defp row(%ProviderReservation{} = reservation, index) do
    snapshot = snapshot(reservation)

    station_ref =
      text(snapshot, "ground_station_ref") || text(reservation.metadata, "ground_station_ref")

    antenna_ref =
      text(snapshot, "antenna_or_service_pool_ref") ||
        text(reservation.metadata, "antenna_or_service_pool_ref")

    extensions = (is_map(snapshot["extensions"]) && snapshot["extensions"]) || %{}

    %{
      id: reservation.provider_reservation_id,
      kind: "contact",
      state: atom_text(reservation.lifecycle_state),
      pass_phase: atom_text(reservation.pass_phase),
      delivery_state: atom_text(reservation.delivery_state),
      spacecraft_id: reservation.spacecraft_id,
      station: station(station_ref, index),
      antenna: antenna_ref && %{id: antenna_ref, label: nil},
      starts_at: reservation.starts_at,
      ends_at: reservation.ends_at,
      uplink_capable: boolean_or_nil(extensions["uplink_capable"]),
      source: %{
        provider: reservation.provider_id,
        provider_name: text(reservation.metadata, "provider_display_name"),
        synthetic: boolean_or_nil(Map.get(snapshot, "synthetic", extensions["synthetic"]))
      },
      max_elevation_deg: number_or_nil(extensions["max_elevation_deg"]),
      cost: cost(extensions["cost"]),
      plan:
        reservation.contact_plan_id &&
          %{id: reservation.contact_plan_id, version: reservation.contact_plan_version},
      reservation_id: reservation.provider_reservation_id,
      scheduled_contact_id: reservation.scheduled_contact_id
    }
  end

  defp snapshot(reservation) do
    Enum.find_value(@snapshots, %{}, fn key ->
      case Map.get(reservation, key) do
        %{} = doc when map_size(doc) > 0 -> doc
        _empty -> nil
      end
    end)
  end

  defp station_index(stations) do
    Enum.reduce(stations, %{}, fn %GroundStation{} = station, acc ->
      code = text(station.metadata, "code")

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

  defp station(nil, _index), do: %{ref: nil, id: nil, code: nil, name: nil}

  defp station(ref, index) do
    Map.merge(%{ref: ref, id: nil, code: nil, name: nil}, Map.get(index, ref, %{}))
  end

  defp cost(%{"amount" => amount, "currency" => currency})
       when is_number(amount) and is_binary(currency),
       do: %{amount: amount, currency: currency}

  defp cost(_cost), do: nil

  defp text(%{} = map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp text(_map, _key), do: nil

  defp atom_text(nil), do: nil
  defp atom_text(value), do: to_string(value)

  defp boolean_or_nil(value) when is_boolean(value), do: value
  defp boolean_or_nil(_value), do: nil

  defp number_or_nil(value) when is_number(value), do: value
  defp number_or_nil(_value), do: nil
end
