defmodule Cadence.Comms.StationAvailability.ProviderReports do
  @moduledoc """
  Station availability from a provider's inventory sync (S7). Each sync carries the provider's
  full report: every listed window is upserted by `"<provider_id>:<window id>"`, and this
  provider's windows it no longer lists are cleared. Stations are matched by id, the same
  convention opportunities use for `ground_station_ref`; unknown stations are skipped.
  """

  import Ecto.Query

  alias Cadence.Comms.{GroundStationStore, StationAvailability}
  alias Cadence.Comms.StationAvailability.WindowRow
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  # The inventory is the provider's own data: a malformed station or window is skipped (and so
  # cleared like any window it stopped reporting), never raised on; an inventory that isn't a list
  # is refused and clears nothing.
  @spec sync(String.t(), String.t(), String.t(), [map()]) ::
          {:ok, %{recorded: non_neg_integer(), cleared: non_neg_integer()}}
          | {:error, :invalid_provider_inventory}
  def sync(_organization_id, _mission_id, _provider_id, stations) when not is_list(stations),
    do: {:error, :invalid_provider_inventory}

  def sync(organization_id, mission_id, provider_id, stations) do
    known =
      organization_id
      |> GroundStationStore.list_ground_stations(mission_id)
      |> MapSet.new(& &1.ground_station_id)

    recorded =
      for %{"id" => station_id} = station <- stations,
          MapSet.member?(known, station_id),
          %{"id" => window_id, "kind" => kind} = window
          when is_binary(window_id) and is_binary(kind) <- windows(station),
          report = report(provider_id, station_id, window),
          match?(
            {:ok, _view},
            StationAvailability.record_provider_report(organization_id, mission_id, report)
          ),
          do: report.provider_ref

    {:ok,
     %{
       recorded: length(recorded),
       cleared: clear_unreported(organization_id, mission_id, provider_id, recorded)
     }}
  end

  defp report(provider_id, station_id, window) do
    %{
      provider_ref: "#{provider_id}:#{window["id"]}",
      provider: provider_id,
      ground_station_id: station_id,
      kind: window["kind"],
      starts_at: timestamp(window["starts_at"]),
      ends_at: timestamp(window["ends_at"]),
      reason: if(is_binary(window["reason"]), do: window["reason"])
    }
  end

  defp windows(%{"availability_windows" => windows}) when is_list(windows), do: windows
  defp windows(_station), do: []

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp timestamp(_value), do: nil

  defp clear_unreported(organization_id, mission_id, provider_id, recorded) do
    {count, _rows} =
      WindowRow
      |> where(
        [w],
        w.organization_id == ^organization_id and w.mission_id == ^mission_id and
          w.source == "provider" and is_nil(w.cleared_at) and
          fragment("?->>'id'", w.reported_by) == ^provider_id and
          w.provider_ref not in ^recorded
      )
      |> Repo.update_all(
        set: [
          cleared_at: DateTime.utc_now(),
          cleared_by: %{
            "kind" => "provider",
            "id" => provider_id,
            "reason" => "no longer reported"
          }
        ]
      )

    if count > 0 do
      ScopedReadUpdates.publish(:stations_changed, organization_id, mission_id)
      ScopedReadUpdates.publish(:contacts_changed, organization_id, mission_id)
    end

    count
  end
end
