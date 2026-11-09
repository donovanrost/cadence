defmodule Cadence.ContactPlanning.StationConflicts do
  @moduledoc """
  Plan passes against station availability (ux U26). A selected pass inside
  an active outage or maintenance window on its station is a **conflict**
  (`station_unavailable`, blocks submit); one inside a degraded window is
  **at risk** (`station_degraded`, a warning only). Grouped per station
  window: `%{code, ground_station_id, window_id, kind, snapshot_ids}`.

  Booked passes are K2's (repairs); this is for plans being drafted and
  submitted.
  """

  alias Cadence.Comms.{StationAvailability, StationRefs}

  @type item :: %{
          code: binary(),
          ground_station_id: binary(),
          window_id: binary(),
          kind: atom(),
          snapshot_ids: [binary()]
        }

  @spec check(binary(), binary(), [map()]) :: %{conflicts: [item()], at_risk: [item()]}
  def check(_organization_id, _mission_id, []), do: %{conflicts: [], at_risk: []}

  def check(organization_id, mission_id, snapshots) do
    from = snapshots |> Enum.map(& &1.starts_at) |> Enum.min(DateTime)
    until = snapshots |> Enum.map(& &1.ends_at) |> Enum.max(DateTime)

    evaluate(
      snapshots,
      StationRefs.index(organization_id, mission_id),
      StationAvailability.planning_windows(organization_id, mission_id, from, until)
    )
  end

  @doc "Pure: `windows` by station id (`StationAvailability.planning_windows/4`)."
  @spec evaluate([map()], StationRefs.index(), map()) :: %{
          conflicts: [item()],
          at_risk: [item()]
        }
  def evaluate(snapshots, index, windows) do
    hits =
      for snapshot <- snapshots,
          %{id: station_id} when is_binary(station_id) <- [
            StationRefs.of_snapshot(snapshot, index)
          ],
          window <- Map.get(windows, station_id, []),
          overlaps?(window, snapshot),
          do: {station_id, window, snapshot.contact_opportunity_snapshot_id}

    items =
      hits
      |> Enum.group_by(fn {station_id, window, _id} -> {station_id, window} end, &elem(&1, 2))
      |> Enum.map(fn {{station_id, window}, ids} ->
        %{
          code: if(window.kind == :degraded, do: "station_degraded", else: "station_unavailable"),
          ground_station_id: station_id,
          window_id: window.window_id,
          kind: window.kind,
          snapshot_ids: Enum.uniq(ids)
        }
      end)
      |> Enum.sort_by(&{&1.ground_station_id, &1.window_id})

    {at_risk, conflicts} = Enum.split_with(items, &(&1.kind == :degraded))
    %{conflicts: conflicts, at_risk: at_risk}
  end

  defp overlaps?(window, snapshot),
    do: StationAvailability.overlaps?([window], snapshot.starts_at, snapshot.ends_at) != nil
end
