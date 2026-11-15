defmodule Cadence.Reads.PassTelemetryStored do
  @moduledoc """
  A pass detail's `telemetry_stored` (ux U60, fe-ops): did this pass's data reach the store, and
  how close to LOS? From the latest `source_watermark_settled` operational event whose subject is
  the pass's realized contact (domain storage-growth.md part 2): `%{through, los, settled_at,
  text}`, or nil when the pass has no realized contact or nothing has settled yet.
  """

  alias Cadence.OperationalEvents
  alias Cadence.Reads.WatermarkEvents

  @spec read(binary(), binary(), binary() | nil, binary()) :: map() | nil
  def read(_org, _mission, nil, _craft), do: nil

  def read(org, mission, realized_contact_id, craft) do
    org
    |> OperationalEvents.list_events(mission,
      subject_kind: "contact",
      subject_id: realized_contact_id,
      kind: "source_watermark_settled",
      order: :desc,
      limit: 1
    )
    |> List.first()
    |> stored(craft)
  end

  defp stored(nil, _craft), do: nil

  defp stored(event, craft) do
    current = stringify(event.current)
    payload = stringify(event.payload)

    %{
      through: parse(current["complete_through"]),
      los: parse(payload["ends_at"]),
      settled_at: event.occurred_at,
      text: WatermarkEvents.settled(craft, current, payload, event.occurred_at)
    }
  end

  defp stringify(nil), do: %{}
  defp stringify(map) when is_map(map), do: map |> Jason.encode!() |> Jason.decode!()

  defp parse(%DateTime{} = at), do: at

  defp parse(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> at
      _invalid -> nil
    end
  end

  defp parse(_other), do: nil
end
