defmodule Cadence.Reads.ContactStations do
  @moduledoc """
  Ground-station codes for contact interval rows (dashboards' chart overlays): a contact's
  station comes from its transport (`metadata.transport_id` → the transport's ground station),
  as `Cadence.Reads.EventContacts` resolves it. One transport read and one station index per
  frame. `nil` when the contact names no transport or its station has no code.
  """

  alias Cadence.Comms.{StationRefs, TransportStore}

  @doc "The station column for `intervals`, in their order."
  @spec column(binary(), binary(), [map()]) :: [binary() | nil]
  def column(organization_id, mission_id, intervals) do
    codes = codes(organization_id, mission_id, intervals)
    Enum.map(intervals, &Map.get(codes, &1.contact_id))
  end

  @spec codes(binary(), binary(), [map()]) :: %{optional(binary()) => binary()}
  def codes(_organization_id, _mission_id, []), do: %{}

  def codes(organization_id, mission_id, intervals) do
    transport_of =
      for interval <- intervals,
          id = transport_id(interval.source),
          is_binary(id),
          into: %{},
          do: {interval.contact_id, id}

    stations_by_transport =
      case TransportStore.fetch_transports(
             organization_id,
             mission_id,
             Enum.uniq(Map.values(transport_of))
           ) do
        {:ok, transports} ->
          Map.new(transports, fn {id, transport} -> {id, transport.ground_station_id} end)

        _none ->
          %{}
      end

    index =
      if stations_by_transport == %{},
        do: %{},
        else: StationRefs.index(organization_id, mission_id)

    for {contact_id, transport_id} <- transport_of,
        code = StationRefs.resolve(Map.get(stations_by_transport, transport_id), index).code,
        is_binary(code),
        into: %{},
        do: {contact_id, code}
  end

  defp transport_id(%{metadata: %{"transport_id" => id}}) when is_binary(id), do: id
  defp transport_id(%{"metadata" => %{"transport_id" => id}}) when is_binary(id), do: id
  defp transport_id(_source), do: nil
end
