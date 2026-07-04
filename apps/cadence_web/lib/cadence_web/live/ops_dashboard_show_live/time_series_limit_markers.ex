defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesLimitMarkers do
  @moduledoc false

  alias Cadence.Dashboards.{DataLink, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.WidgetLinks

  import CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkerSupport

  @spec limit_markers(PlacementFrames.t() | nil) :: [map()]
  def limit_markers(%PlacementFrames{overlays: %{limits: limit_frames}})
      when is_list(limit_frames) do
    limit_frames
    |> Enum.flat_map(&limit_frame_markers/1)
    |> Enum.uniq_by(&limit_marker_identity/1)
  end

  def limit_markers(_placement_frames), do: []

  defp limit_frame_markers(%Frame{source: :limits, shape: :events, fields: fields} = frame) do
    times = field_values(fields, "time")
    sample_ids = field_values(fields, "sample_id")
    normalized_states = field_values(fields, "normalized_state")
    limit_states = field_values(fields, "limit_state")
    violations = field_values(fields, "violation")
    limit_event_ids = field_values(fields, "limit_event_id")
    bucket_ends = field_values(fields, "bucket_end")
    event_counts = field_values(fields, "event_count")
    bucket_limit_event_ids = field_values(fields, "limit_event_ids")
    bucket_sample_ids = field_values(fields, "sample_ids")
    divergence_counts = field_values(fields, "limit_divergence_count")
    definition_ids = field_values(fields, "limit_definition_id")
    definition_versions = field_values(fields, "limit_definition_version")
    limit_set_names = field_values(fields, "limit_set_name")
    observed_event_ids = field_values(fields, "observed_limit_event_id")
    observed_normalized_states = field_values(fields, "observed_normalized_state")
    diverged = field_values(fields, "limit_state_diverged")
    links = limit_event_links(frame)
    limit_event_links_by_id = limit_event_links_by_target_id(frame)
    telemetry_links_by_sample_id = telemetry_sample_links_by_sample_id(frame)

    times
    |> Enum.with_index()
    |> Enum.map(fn {time, index} ->
      sample_id = Enum.at(sample_ids, index)
      limit_event_id = Enum.at(limit_event_ids, index)

      limit_marker(%{
        time: time,
        sample_id: sample_id,
        normalized_state: Enum.at(normalized_states, index),
        limit_state: Enum.at(limit_states, index),
        violation: Enum.at(violations, index),
        limit_event_id: limit_event_id,
        bucket_end: Enum.at(bucket_ends, index),
        event_count: Enum.at(event_counts, index),
        limit_event_ids: Enum.at(bucket_limit_event_ids, index),
        sample_ids: Enum.at(bucket_sample_ids, index),
        limit_divergence_count: Enum.at(divergence_counts, index),
        limit_definition_id: Enum.at(definition_ids, index),
        limit_definition_version: Enum.at(definition_versions, index),
        limit_set_name: Enum.at(limit_set_names, index),
        link:
          Map.get(limit_event_links_by_id, limit_event_id) ||
            Enum.at(links, index) || Map.get(telemetry_links_by_sample_id, sample_id),
        semantics_mode: Map.get(frame.meta || %{}, :semantics_mode),
        analysis_basis: Map.get(frame.meta || %{}, :analysis_basis),
        selected_limit_clock: Map.get(frame.meta || %{}, :selected_limit_clock),
        selected_limit_definition_intervals:
          Map.get(frame.meta || %{}, :selected_limit_definition_intervals),
        synthetic_limit_analysis?: Map.get(frame.meta || %{}, :synthetic_limit_analysis?),
        observed_limit_event_id: Enum.at(observed_event_ids, index),
        observed_normalized_state: Enum.at(observed_normalized_states, index),
        limit_state_diverged: Enum.at(diverged, index)
      })
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp limit_frame_markers(%Frame{source: :limits, shape: :scalar, fields: fields} = frame) do
    with [%DateTime{} = time | _rest] <- field_values(fields, "time"),
         [normalized_state | _rest] <- field_values(fields, "normalized_state"),
         %DataLink{} = link <- List.first(limit_event_links(frame)) do
      [
        limit_marker(%{
          time: time,
          sample_id: Map.get(frame.meta, :sample_id),
          normalized_state: normalized_state,
          limit_state: field_values(fields, "limit_state") |> List.first(),
          violation: field_values(fields, "violation") |> List.first(),
          link: link
        })
      ]
      |> Enum.reject(&is_nil/1)
    else
      _missing -> []
    end
  end

  defp limit_frame_markers(%Frame{source: :limits, shape: :intervals, fields: fields} = frame) do
    active_from = field_values(fields, "active_from")
    active_to = field_values(fields, "active_to")
    definition_ids = field_values(fields, "limit_definition_id")
    definition_versions = field_values(fields, "limit_definition_version")
    limit_set_names = field_values(fields, "limit_set_name")
    red_lows = field_values(fields, "red_low")
    yellow_lows = field_values(fields, "yellow_low")
    yellow_highs = field_values(fields, "yellow_high")
    red_highs = field_values(fields, "red_high")
    links = limit_definition_links(frame)

    active_from
    |> Enum.with_index()
    |> Enum.map(fn {start_time, index} ->
      limit_definition_interval_marker(%{
        start_time: start_time,
        end_time: Enum.at(active_to, index),
        definition_id: Enum.at(definition_ids, index),
        definition_version: Enum.at(definition_versions, index),
        limit_set_name: Enum.at(limit_set_names, index),
        red_low: Enum.at(red_lows, index),
        yellow_low: Enum.at(yellow_lows, index),
        yellow_high: Enum.at(yellow_highs, index),
        red_high: Enum.at(red_highs, index),
        link: Enum.at(links, index)
      })
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp limit_frame_markers(_frame), do: []

  defp limit_marker(%{time: %DateTime{} = time, normalized_state: normalized_state} = attrs) do
    if visible_limit_marker?(normalized_state) do
      link = Map.get(attrs, :link)

      %{
        marker_id: limit_analysis_marker_id(attrs, time),
        marker_type: limit_marker_type(attrs),
        timestamp_ms: DateTime.to_unix(time, :millisecond),
        link_id: data_link_id(link),
        limit_event_id: limit_event_id(attrs, link),
        observed_limit_event_id: Map.get(attrs, :observed_limit_event_id),
        normalized_state: context_text(normalized_state),
        observed_normalized_state: marker_value_text(Map.get(attrs, :observed_normalized_state)),
        limit_state: marker_value_text(Map.get(attrs, :limit_state)),
        violation: Map.get(attrs, :violation),
        sample_id: Map.get(attrs, :sample_id),
        sample_ids: Map.get(attrs, :sample_ids),
        event_count: Map.get(attrs, :event_count),
        starts_at_ms: bucket_start_ms(attrs, time),
        ends_at_ms: timestamp_ms(Map.get(attrs, :bucket_end)),
        bucket_end_ms: timestamp_ms(Map.get(attrs, :bucket_end)),
        limit_event_ids: Map.get(attrs, :limit_event_ids),
        limit_definition_id: Map.get(attrs, :limit_definition_id),
        limit_definition_version: Map.get(attrs, :limit_definition_version),
        limit_set_name: marker_value_text(Map.get(attrs, :limit_set_name)),
        limit_divergence_count: Map.get(attrs, :limit_divergence_count),
        semantics_mode: marker_value_text(Map.get(attrs, :semantics_mode)),
        analysis_basis: marker_value_text(Map.get(attrs, :analysis_basis)),
        selected_limit_clock: Map.get(attrs, :selected_limit_clock),
        selected_limit_definition_intervals: Map.get(attrs, :selected_limit_definition_intervals),
        synthetic_limit_analysis: Map.get(attrs, :synthetic_limit_analysis?),
        limit_state_diverged: Map.get(attrs, :limit_state_diverged)
      }
      |> drop_nil_values()
    end
  end

  defp limit_marker(_attrs), do: nil

  defp bucket_start_ms(%{bucket_end: %DateTime{}}, %DateTime{} = time),
    do: DateTime.to_unix(time, :millisecond)

  defp bucket_start_ms(_attrs, %DateTime{}), do: nil

  defp limit_definition_interval_marker(
         %{
           start_time: %DateTime{} = start_time,
           link: %DataLink{target: :limit_definition} = link
         } = attrs
       ) do
    %{
      marker_type: "limit_definition_interval",
      starts_at_ms: DateTime.to_unix(start_time, :millisecond),
      ends_at_ms: timestamp_ms(Map.get(attrs, :end_time)),
      link_id: link.link_id,
      target: "limit_definition",
      target_id: link.target_id,
      limit_definition_id: Map.get(attrs, :definition_id) || link.target_id,
      limit_definition_version: Map.get(attrs, :definition_version),
      limit_set_name: marker_value_text(Map.get(attrs, :limit_set_name)),
      red_low: Map.get(attrs, :red_low),
      yellow_low: Map.get(attrs, :yellow_low),
      yellow_high: Map.get(attrs, :yellow_high),
      red_high: Map.get(attrs, :red_high)
    }
    |> drop_nil_values()
  end

  defp limit_definition_interval_marker(_attrs), do: nil

  defp visible_limit_marker?(state) when state in [:yellow, :red, "yellow", "red"], do: true
  defp visible_limit_marker?(_state), do: false

  defp limit_analysis_marker_id(
         %{bucket_end: %DateTime{} = bucket_end} = attrs,
         %DateTime{} = time
       ) do
    [
      "limit-analysis-bucket",
      marker_value_text(Map.get(attrs, :semantics_mode)),
      DateTime.to_unix(time, :millisecond),
      DateTime.to_unix(bucket_end, :millisecond)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp limit_analysis_marker_id(
         %{synthetic_limit_analysis?: true, semantics_mode: semantics_mode, sample_id: sample_id},
         %DateTime{} = time
       ) do
    [
      "limit-analysis",
      marker_value_text(semantics_mode),
      sample_id,
      DateTime.to_unix(time, :millisecond)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp limit_analysis_marker_id(_attrs, %DateTime{}), do: nil

  defp limit_marker_type(%{bucket_end: %DateTime{}}), do: "limit_analysis_bucket"
  defp limit_marker_type(%{synthetic_limit_analysis?: true}), do: "limit_analysis"
  defp limit_marker_type(_attrs), do: nil

  defp limit_event_id(%{limit_event_id: limit_event_id}, _link)
       when is_binary(limit_event_id) and limit_event_id != "",
       do: limit_event_id

  defp limit_event_id(%{observed_limit_event_id: observed_limit_event_id}, _link)
       when is_binary(observed_limit_event_id) and observed_limit_event_id != "",
       do: observed_limit_event_id

  defp limit_event_id(_attrs, %DataLink{target: :limit_event} = link), do: link.target_id
  defp limit_event_id(_attrs, _link), do: nil

  defp limit_marker_identity(%{marker_type: "limit_definition_interval"} = marker) do
    Map.get(marker, :link_id) ||
      {
        Map.get(marker, :limit_definition_id),
        Map.get(marker, :starts_at_ms),
        Map.get(marker, :ends_at_ms)
      }
  end

  defp limit_marker_identity(%{marker_id: marker_id}) when not is_nil(marker_id), do: marker_id

  defp limit_marker_identity(marker) do
    Map.get(marker, :link_id) ||
      {Map.get(marker, :limit_event_id), Map.get(marker, :timestamp_ms)}
  end

  defp limit_event_links(%Frame{} = frame) do
    frame
    |> WidgetLinks.data_links()
    |> Enum.filter(&(&1.target == :limit_event))
  end

  defp limit_event_links_by_target_id(%Frame{} = frame) do
    frame
    |> limit_event_links()
    |> Map.new(&{&1.target_id, &1})
  end

  defp telemetry_sample_links_by_sample_id(%Frame{} = frame) do
    frame
    |> WidgetLinks.data_links()
    |> Enum.filter(&(&1.target == :telemetry_sample))
    |> Map.new(&{&1.target_id, &1})
  end

  defp limit_definition_links(%Frame{} = frame) do
    frame
    |> WidgetLinks.data_links()
    |> Enum.filter(&(&1.target == :limit_definition))
  end
end
