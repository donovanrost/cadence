defmodule Cadence.Control.SpacecraftTraffic do
  @moduledoc """
  Which spacecraft have had traffic (#49/#50): any provider reservation, or any command request
  on one of their source endpoints. A change set that archives such a spacecraft raises a HOLD
  (`spacecraft_has_traffic`). `archive_blockers/3` is what is still ahead of one (L22): requests
  waiting to release and passes still booked. Configured as `:spacecraft_traffic` so the
  spacecraft kind needs no compile-time edge to contacts or commanding.

  Endpoints are read once per call, scoped to the organization and mission.
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

    endpoints = endpoints(organization_id, mission_id, spacecraft_ids)

    commanded =
      RequestActivity.endpoints_with_requests(
        organization_id,
        mission_id,
        endpoints |> Map.values() |> List.flatten()
      )

    spacecraft_ids
    |> Enum.filter(fn id ->
      MapSet.member?(booked, id) or
        Enum.any?(Map.get(endpoints, id, []), &MapSet.member?(commanded, &1))
    end)
    |> MapSet.new()
  end

  @doc """
  What archiving these spacecraft would leave behind: `%{id => %{waiting_requests,
  booked_passes, earliest_pass_at}}`, only for spacecraft with any.
  """
  @spec archive_blockers(binary(), binary(), [binary()]) :: %{binary() => map()}
  def archive_blockers(_organization_id, _mission_id, []), do: %{}

  def archive_blockers(organization_id, mission_id, spacecraft_ids) do
    booked =
      ReservationActivity.upcoming(
        organization_id,
        mission_id,
        spacecraft_ids,
        DateTime.utc_now()
      )

    endpoints = endpoints(organization_id, mission_id, spacecraft_ids)

    waiting =
      RequestActivity.waiting_counts(
        organization_id,
        mission_id,
        endpoints |> Map.values() |> List.flatten()
      )

    spacecraft_ids
    |> Enum.map(fn id ->
      passes = Map.get(booked, id, %{count: 0, earliest: nil})

      {id,
       %{
         waiting_requests:
           endpoints |> Map.get(id, []) |> Enum.map(&Map.get(waiting, &1, 0)) |> Enum.sum(),
         booked_passes: passes.count,
         earliest_pass_at: passes.earliest
       }}
    end)
    |> Enum.reject(fn {_id, b} -> b.waiting_requests == 0 and b.booked_passes == 0 end)
    |> Map.new()
  end

  # `%{spacecraft_id => [source_endpoint_id]}` in one read.
  defp endpoints(organization_id, mission_id, spacecraft_ids) do
    wanted = MapSet.new(spacecraft_ids)

    organization_id
    |> SourceEndpoints.list_source_endpoints(mission_id)
    |> Enum.filter(&MapSet.member?(wanted, &1.spacecraft_id))
    |> Enum.group_by(& &1.spacecraft_id, & &1.source_endpoint_id)
  end
end
