defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesSourceBindingMarkers do
  @moduledoc false

  alias Cadence.Dashboards.{Frame, PlacementFrames}

  import CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkerSupport

  def interval_markers(%PlacementFrames{primary: frames}) when is_list(frames) do
    frames
    |> Enum.flat_map(&frame_source_binding_interval_markers/1)
    |> Enum.uniq_by(& &1.marker_id)
  end

  def interval_markers(_placement_frames), do: []

  defp frame_source_binding_interval_markers(%Frame{meta: meta}) when is_map(meta) do
    source_context = source_marker_context(meta)

    meta
    |> source_binding_intervals()
    |> Enum.map(&source_binding_interval_marker(&1, source_context))
    |> Enum.reject(&is_nil/1)
  end

  defp frame_source_binding_interval_markers(%Frame{}), do: []

  defp source_binding_intervals(meta) do
    cond do
      is_list(Map.get(meta, :source_binding_segments)) ->
        Enum.map(meta.source_binding_segments, &source_binding_segment_interval/1)

      is_map(Map.get(meta, :source_binding_segment)) ->
        [source_binding_segment_interval(meta.source_binding_segment)]

      is_map(Map.get(meta, :source_binding_interval)) ->
        [Map.get(meta, :source_binding_interval)]

      true ->
        []
    end
    |> Enum.reject(&is_nil/1)
  end

  defp source_binding_segment_interval(segment) when is_map(segment) do
    interval = Map.get(segment, :interval, %{})

    %{
      source_binding_id: Map.get(segment, :binding_id),
      source_binding_version: Map.get(segment, :binding_version),
      data_binding_event_id: Map.get(segment, :data_binding_event_id),
      data_source_id: Map.get(segment, :data_source_id),
      dataset: Map.get(segment, :dataset),
      realm: Map.get(segment, :realm),
      started_at: Map.get(segment, :from),
      ended_at: Map.get(segment, :to),
      interval_started_at: Map.get(interval, :started_at),
      interval_ended_at: Map.get(interval, :ended_at),
      event_type: Map.get(interval, :event_type),
      status: Map.get(interval, :status),
      logical_source: Map.get(interval, :logical_source)
    }
  end

  defp source_binding_segment_interval(_segment), do: nil

  defp source_binding_interval_marker(interval, source_context) when is_map(interval) do
    with %DateTime{} = started_at <- Map.get(interval, :started_at),
         source_binding_id when is_binary(source_binding_id) <-
           Map.get(interval, :source_binding_id) || Map.get(interval, :binding_id) ||
             Map.get(source_context, :source_binding_id) do
      data_source_id =
        Map.get(interval, :data_source_id) || Map.get(source_context, :data_source_id)

      realm = Map.get(interval, :realm) || Map.get(source_context, :realm)

      logical_source =
        Map.get(interval, :logical_source) || Map.get(source_context, :logical_source)

      %{
        marker_type: "source_binding_interval",
        marker_id:
          source_binding_marker_id(
            source_binding_id,
            Map.get(interval, :data_binding_event_id),
            started_at
          ),
        starts_at_ms: DateTime.to_unix(started_at, :millisecond),
        ends_at_ms: timestamp_ms(Map.get(interval, :ended_at)),
        target: "source_binding",
        target_id: source_binding_id,
        source_request_id: Map.get(source_context, :source_request_id),
        logical_source: marker_value_text(logical_source),
        source_binding_id: source_binding_id,
        source_binding_version:
          Map.get(interval, :source_binding_version) || Map.get(interval, :binding_version),
        data_binding_event_id: Map.get(interval, :data_binding_event_id),
        data_source_id: data_source_id,
        dataset: Map.get(interval, :dataset) || Map.get(source_context, :dataset),
        realm: marker_value_text(realm),
        time_mode: marker_value_text(Map.get(source_context, :time_mode)),
        time_axis: marker_value_text(Map.get(source_context, :time_axis)),
        replay_run_id: Map.get(source_context, :replay_run_id),
        requested_realm: marker_value_text(Map.get(source_context, :requested_realm)),
        requested_data_view: marker_value_text(Map.get(source_context, :requested_data_view)),
        requested_data_source_id: Map.get(source_context, :requested_data_source_id),
        requested_source_binding_id: Map.get(source_context, :requested_source_binding_id),
        requested_dataset: Map.get(source_context, :requested_dataset),
        requested_validity_state:
          marker_value_text(Map.get(source_context, :requested_validity_state)),
        event_type: marker_value_text(Map.get(interval, :event_type)),
        status: marker_value_text(Map.get(interval, :status)),
        label: source_binding_marker_label(source_binding_id, data_source_id)
      }
      |> drop_nil_values()
    end
  end

  defp source_binding_interval_marker(_interval, _source_context), do: nil

  defp source_binding_marker_id(
         source_binding_id,
         data_binding_event_id,
         %DateTime{} = started_at
       ) do
    [
      "source-binding",
      source_binding_id,
      data_binding_event_id,
      DateTime.to_unix(started_at, :millisecond)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp source_binding_marker_label(source_binding_id, nil), do: source_binding_id

  defp source_binding_marker_label(source_binding_id, data_source_id),
    do: "#{source_binding_id} / #{data_source_id}"
end
