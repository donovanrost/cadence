defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesContactIntervalMarkers do
  @moduledoc """
  Projects contact interval event frames into chart markers.
  """

  alias Cadence.Dashboards.{DataLink, Frame}

  import CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkerSupport

  @spec event_frame?(Frame.t()) :: boolean()
  def event_frame?(%Frame{source: :events, shape: :intervals}), do: true
  def event_frame?(%Frame{}), do: false

  @spec interval_markers(Frame.t()) :: [map()]
  def interval_markers(%Frame{source: :events, shape: :intervals, fields: fields} = frame) do
    starts_at = field_values(fields, "starts_at")
    ends_at = field_values(fields, "ends_at")
    kinds = field_values(fields, "kind")
    statuses = field_values(fields, "status")
    labels = field_values(fields, "label")
    contact_ids = field_values(fields, "contact_id")
    links = event_links(frame, :contact)

    starts_at
    |> Enum.with_index()
    |> Enum.map(fn {start_time, index} ->
      interval_marker(%{
        start_time: start_time,
        end_time: Enum.at(ends_at, index),
        kind: Enum.at(kinds, index),
        status: Enum.at(statuses, index),
        label: Enum.at(labels, index),
        contact_id: Enum.at(contact_ids, index),
        link: Enum.at(links, index)
      })
    end)
    |> Enum.reject(&is_nil/1)
  end

  def interval_markers(_frame), do: []

  defp interval_marker(%{
         start_time: %DateTime{} = start_time,
         end_time: end_time,
         kind: kind,
         status: status,
         label: label,
         contact_id: contact_id,
         link: %DataLink{} = link
       }) do
    %{
      marker_type: "contact_interval",
      starts_at_ms: DateTime.to_unix(start_time, :millisecond),
      ends_at_ms: timestamp_ms(end_time),
      link_id: link.link_id,
      target: "contact",
      target_id: link.target_id,
      contact_id: contact_id || link.target_id,
      contact_kind: marker_value_text(kind),
      status: marker_value_text(status),
      label: label || link.label
    }
    |> drop_nil_values()
  end

  defp interval_marker(_attrs), do: nil
end
