defmodule Cadence.Control.SpacecraftTraffic do
  @moduledoc """
  Which spacecraft have had traffic (#49/#50): any provider reservation, or any command request
  on one of their source endpoints. A change set that archives such a spacecraft raises a HOLD
  (`spacecraft_has_traffic`). Configured as `:spacecraft_traffic` so the spacecraft kind needs
  no compile-time edge to contacts or commanding.
  """

  alias Cadence.Commanding.RequestActivity
  alias Cadence.Contacts.ReservationActivity
  alias Cadence.SourceEndpoints

  @spec with_traffic(binary(), binary(), [binary()]) :: MapSet.t()
  def with_traffic(_organization_id, _mission_id, []), do: MapSet.new()

  def with_traffic(organization_id, mission_id, spacecraft_ids) do
    booked =
      ReservationActivity.spacecraft_with_reservations(
        organization_id,
        mission_id,
        spacecraft_ids
      )

    endpoints =
      Map.new(spacecraft_ids, fn id ->
        {id,
         mission_id
         |> SourceEndpoints.list_source_endpoints(spacecraft_id: id)
         |> Enum.map(& &1.source_endpoint_id)}
      end)

    commanded =
      RequestActivity.endpoints_with_requests(
        organization_id,
        mission_id,
        endpoints |> Map.values() |> List.flatten()
      )

    spacecraft_ids
    |> Enum.filter(fn id ->
      MapSet.member?(booked, id) or Enum.any?(endpoints[id], &MapSet.member?(commanded, &1))
    end)
    |> MapSet.new()
  end
end
