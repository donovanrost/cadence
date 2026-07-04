defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesSourceHealthMarkers do
  @moduledoc """
  Projects source-health event frames into chart markers.
  """

  alias Cadence.Dashboards.{DataLink, Frame}

  import CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkerSupport

  @spec event_frame?(Frame.t()) :: boolean()
  def event_frame?(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :family, Map.get(meta, "family")) in [:source_health, "source_health"]
  end

  def event_frame?(%Frame{}), do: false

  @spec event_markers(Frame.t()) :: [map()]
  def event_markers(%Frame{fields: fields} = frame) do
    source_context = source_marker_context(frame.meta)
    occurred_at = field_values(fields, "occurred_at")
    kinds = field_values(fields, "kind")
    severities = field_values(fields, "severity")
    titles = field_values(fields, "title")
    source_record_ids = field_values(fields, "source_record_id")
    source_health = field_values(fields, "source_health")
    previous_source_health = field_values(fields, "previous_source_health")
    reasons = field_values(fields, "reason")
    logical_sources = field_values(fields, "logical_source")
    data_source_ids = field_values(fields, "data_source_id")
    source_binding_ids = field_values(fields, "source_binding_id")
    links = event_links(frame, :source_health_event)

    occurred_at
    |> Enum.with_index()
    |> Enum.map(fn {time, index} ->
      event_marker(%{
        time: time,
        kind: Enum.at(kinds, index),
        severity: Enum.at(severities, index),
        title: Enum.at(titles, index),
        source_record_id: Enum.at(source_record_ids, index),
        source_health: Enum.at(source_health, index),
        previous_source_health: Enum.at(previous_source_health, index),
        reason: Enum.at(reasons, index),
        logical_source: Enum.at(logical_sources, index),
        data_source_id: Enum.at(data_source_ids, index),
        source_binding_id: Enum.at(source_binding_ids, index),
        source_context: source_context,
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
    source_context = Map.get(attrs, :source_context, %{})

    %{
      marker_type: "source_health_transition",
      timestamp_ms: DateTime.to_unix(time, :millisecond),
      link_id: link.link_id,
      target: "source_health_event",
      target_id: link.target_id,
      source_health_event_id: link.target_id,
      event_kind: marker_value_text(Map.get(attrs, :kind)),
      severity: marker_value_text(Map.get(attrs, :severity)),
      title: Map.get(attrs, :title) || link.label,
      source_record_id: Map.get(attrs, :source_record_id),
      source_health: marker_value_text(Map.get(attrs, :source_health)),
      previous_source_health: marker_value_text(Map.get(attrs, :previous_source_health)),
      reason: marker_value_text(Map.get(attrs, :reason)),
      source_request_id: Map.get(source_context, :source_request_id),
      logical_source:
        marker_value_text(
          Map.get(attrs, :logical_source) || Map.get(source_context, :logical_source)
        ),
      source_binding_id:
        Map.get(attrs, :source_binding_id) || Map.get(source_context, :source_binding_id),
      data_source_id: Map.get(attrs, :data_source_id) || Map.get(source_context, :data_source_id),
      dataset: Map.get(source_context, :dataset),
      realm: marker_value_text(Map.get(source_context, :realm)),
      time_mode: marker_value_text(Map.get(source_context, :time_mode)),
      time_axis: marker_value_text(Map.get(source_context, :time_axis)),
      replay_run_id: Map.get(source_context, :replay_run_id),
      requested_realm: marker_value_text(Map.get(source_context, :requested_realm)),
      requested_data_view: marker_value_text(Map.get(source_context, :requested_data_view)),
      requested_data_source_id: Map.get(source_context, :requested_data_source_id),
      requested_source_binding_id: Map.get(source_context, :requested_source_binding_id),
      requested_dataset: Map.get(source_context, :requested_dataset),
      requested_validity_state:
        marker_value_text(Map.get(source_context, :requested_validity_state))
    }
    |> drop_nil_values()
  end

  defp event_marker(_attrs), do: nil
end
