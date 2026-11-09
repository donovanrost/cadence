defmodule CadenceWeb.Console.StationAvailabilityJSON do
  @moduledoc "Wire shapes for station availability (S7). Contract: docs/apogee/api/contacts.md."

  @spec status(map()) :: map()
  def status(status) do
    %{
      ground_station_id: status.ground_station_id,
      state: to_string(status.state),
      since: status.since,
      eta: status.eta,
      source: status.source && to_string(status.source),
      reported_by: status.reported_by,
      reported_at: status.reported_at,
      basis: status.basis,
      windows: Enum.map(status.windows, &window/1)
    }
  end

  @spec window(map()) :: map()
  def window(window) do
    %{
      id: window.id,
      ground_station_id: window.ground_station_id,
      kind: to_string(window.kind),
      from: window.from,
      to: window.to,
      eta: window.eta,
      source: to_string(window.source),
      reported_by: window.reported_by,
      created_by: window.created_by,
      reported_at: window.reported_at,
      reason: window.reason,
      detail: window.detail,
      cleared_at: window.cleared_at
    }
  end
end
