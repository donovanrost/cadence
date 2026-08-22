defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesMissionEventMarkers do
  @moduledoc """
  Projects generic mission event frames into chart markers.
  """

  alias Cadence.Dashboards.{DataLink, Frame}

  import CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkerSupport

  @spec event_markers(Frame.t()) :: [map()]
  def event_markers(%Frame{source: :events, shape: :events, fields: fields} = frame) do
    occurred_at = field_values(fields, "occurred_at")
    categories = field_values(fields, "category")
    kinds = field_values(fields, "kind")
    severities = field_values(fields, "severity")
    titles = field_values(fields, "title")
    source_record_ids = field_values(fields, "source_record_id")
    links = event_links(frame, :mission_event)

    occurred_at
    |> Enum.with_index()
    |> Enum.map(fn {time, index} ->
      event_marker(%{
        time: time,
        category: Enum.at(categories, index),
        kind: Enum.at(kinds, index),
        severity: Enum.at(severities, index),
        title: Enum.at(titles, index),
        source_record_id: Enum.at(source_record_ids, index),
        link: Enum.at(links, index)
      })
    end)
    |> Enum.reject(&is_nil/1)
  end

  def event_markers(_frame), do: []

  defp event_marker(
         %{
           time: %DateTime{} = time,
           link: %DataLink{} = link
         } = attrs
       ) do
    %{
      marker_type: "mission_event",
      timestamp_ms: DateTime.to_unix(time, :millisecond),
      link_id: link.link_id,
      target: "mission_event",
      target_id: link.target_id,
      mission_event_id: link.target_id,
      category: marker_value_text(Map.get(attrs, :category)),
      event_kind: marker_value_text(Map.get(attrs, :kind)),
      severity: marker_value_text(Map.get(attrs, :severity)),
      title: Map.get(attrs, :title) || link.label,
      source_record_id: Map.get(attrs, :source_record_id)
    }
    |> drop_nil_values()
  end

  defp event_marker(_attrs), do: nil
end
