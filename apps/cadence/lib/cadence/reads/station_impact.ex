defmodule Cadence.Reads.StationImpact do
  @moduledoc """
  Which booked passes a station problem hits (S7 → S8/K2): live provider reservations at a
  station that overlap `[from, to]`. A reservation's station lives in its provider snapshots
  (confirmed, else requested) or its metadata; reservations that never named a station can't be
  attributed and aren't counted.
  """

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.PassWindows

  @live ~w(requesting pending confirmed active unknown canceling)
  @lost ~w(canceled rejected failed)
  @limit 2_000

  @spec impact(Scope.t(), String.t(), String.t(), DateTime.t(), DateTime.t()) ::
          {:ok, map()} | {:error, term()}
  def impact(%Scope{} = scope, mission_id, station_id, from, to) do
    with :ok <- authorize(scope, mission_id) do
      {counts, reservations, truncated?} =
        PassWindows.station_impact(
          scope.organization_id,
          mission_id,
          station_id,
          from,
          to,
          @live,
          @lost,
          @limit
        )

      {hit, lost} = Enum.split_with(reservations, &(&1.lifecycle_state in @live))

      {:ok,
       %{
         ground_station_id: station_id,
         from: from,
         to: to,
         passes_hit: counts.hit,
         spacecraft_count: counts.spacecraft_count,
         reservation_ids: Enum.map(hit, & &1.provider_reservation_id),
         spacecraft_ids:
           hit |> Enum.map(& &1.spacecraft_id) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
         # The contact plan revisions that booked them, so K2 can start a repair (S8) directly.
         plans: plans(hit),
         # Bookings at the station in the window that already ended without a pass (canceled,
         # rejected or failed): what the problem has already cost, to re-plan in K2.
         lost: %{
           count: counts.lost,
           reservation_ids: Enum.map(lost, & &1.provider_reservation_id),
           spacecraft_ids:
             lost |> Enum.map(& &1.spacecraft_id) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
           plans: plans(lost)
         },
         truncated: truncated?
       }}
    end
  end

  defp plans(reservations) do
    reservations
    |> Enum.reject(&is_nil(&1.contact_plan_id))
    |> Enum.map(&%{id: &1.contact_plan_id, version: &1.contact_plan_version})
    |> Enum.uniq()
  end

  defp authorize(scope, mission_id) do
    case Policy.authorize(scope, :operate_mission, %{
           organization_id: scope.organization_id,
           mission_id: mission_id
         }) do
      :ok -> :ok
      {:error, _reason} -> {:error, :forbidden}
    end
  end
end
