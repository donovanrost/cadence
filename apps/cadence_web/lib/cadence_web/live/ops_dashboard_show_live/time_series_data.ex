defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesData do
  @moduledoc false

  alias Cadence.Dashboards.{DataLink, Frame, PlacementFrames, ScopeContext}

  alias CadenceWeb.OpsDashboardShowLive.{
    DataManagementPresentation,
    TimeSeriesLimitMarkers,
    WidgetLifecyclePresentation,
    WidgetLinks
  }

  @spec data(PlacementFrames.t()) :: map() | nil
  def data(%PlacementFrames{} = placement_frames) do
    case latest_point_data(placement_frames) do
      %{} = data ->
        data

      _missing ->
        state = if backfill(placement_frames), do: :ready, else: :no_data

        %{
          kind: :point,
          spacecraft_id: nil,
          sample: nil,
          limit_event: nil,
          links: [],
          data_management: DataManagementPresentation.placement(placement_frames),
          stale?: false,
          unresolved?: false,
          engine_backed?: true
        }
        |> WidgetLifecyclePresentation.put(
          placement_frames,
          placement_frames.primary,
          state,
          false
        )
    end
  end

  @spec backfill(PlacementFrames.t()) :: map() | nil
  def backfill(%PlacementFrames{primary: frames} = placement_frames) when is_list(frames) do
    series = Enum.flat_map(frames, &telemetry_chart_series(&1, placement_frames))

    if series == [] do
      nil
    else
      %{
        version: 1,
        data_management: DataManagementPresentation.placement(%PlacementFrames{primary: frames}),
        series: series
      }
      |> drop_nil_values()
    end
  end

  def backfill(%PlacementFrames{}), do: nil

  @spec append(PlacementFrames.t() | nil, map() | nil) :: map() | nil
  def append(%PlacementFrames{primary: frames}, previous_data) when is_list(frames) do
    series = Enum.flat_map(frames, &telemetry_append_series(&1, previous_data))

    if series == [] do
      nil
    else
      %{
        version: 1,
        series: series
      }
    end
  end

  def append(_placement_frames, _previous_data), do: nil

  @spec scalar_data(Frame.t()) :: map() | nil
  def scalar_data(%Frame{source: :telemetry, shape: :scalar, fields: fields}) do
    with %{values: [time | _]} <- field_by_name(fields, "time"),
         value_field when not is_nil(value_field) <- value_field(fields),
         [value | _] <- value_field.values do
      sample_id =
        value_field.metadata
        |> metadata_values(:sample_ids)
        |> List.first()

      %{
        time: time,
        value: value,
        sample_id: sample_id,
        sample_link_id: sample_link_id(value_field.metadata, sample_id),
        quality_state:
          value_field.metadata
          |> metadata_values(:quality_states)
          |> List.first()
      }
    else
      _missing -> nil
    end
  end

  def scalar_data(%Frame{}), do: nil

  defp latest_point_data(
         %PlacementFrames{
           primary: [%Frame{source: :telemetry, shape: :scalar} = telemetry_frame | _]
         } = placement_frames
       ) do
    with %{time: time, value: value, sample_id: sample_id, quality_state: quality_state} <-
           scalar_data(telemetry_frame) do
      %{
        kind: :point,
        spacecraft_id: spacecraft_id(telemetry_frame.scope),
        sample: %{
          sample_id: sample_id,
          raw_value: value,
          engineering_value: value,
          receipt_time: time,
          generation_time: time,
          quality_state: quality_state || :good
        },
        limit_event: nil,
        links: WidgetLinks.widget_data_links(telemetry_frame, nil),
        data_management: DataManagementPresentation.frame(telemetry_frame),
        stale?: watermark_unknown?(telemetry_frame),
        unresolved?: false,
        engine_backed?: true
      }
      |> Map.merge(frame_query_scope_context(telemetry_frame))
      |> WidgetLifecyclePresentation.put(
        placement_frames,
        telemetry_frame,
        :ready,
        watermark_unknown?(telemetry_frame)
      )
    end
  end

  defp latest_point_data(
         %PlacementFrames{
           primary: [%Frame{shape: :wide} = series_frame | _]
         } = placement_frames
       ) do
    case latest_series_sample_data(series_frame) do
      %{} = data ->
        WidgetLifecyclePresentation.put(
          data,
          placement_frames,
          series_frame,
          :ready,
          watermark_unknown?(series_frame)
        )

      _missing ->
        nil
    end
  end

  defp latest_point_data(%PlacementFrames{}), do: nil

  defp telemetry_append_series(
         %Frame{source: :telemetry, shape: :scalar, fields: fields} = frame,
         previous_data
       ) do
    with %{
           time: %DateTime{} = time,
           value: value,
           sample_id: sample_id,
           sample_link_id: sample_link_id
         } <-
           scalar_data(frame),
         true <- is_number(value),
         true <- new_sample?(previous_data, sample_id),
         value_field when not is_nil(value_field) <- value_field(fields) do
      points = [chart_datum(time, value, %{sample_id: sample_id, link_id: sample_link_id})]

      [chart_series(frame, value_field, points)]
    else
      _skip -> []
    end
  end

  defp telemetry_append_series(%Frame{}, _previous_data), do: []

  defp new_sample?(%{sample: %{sample_id: sample_id}}, sample_id)
       when not is_nil(sample_id),
       do: false

  defp new_sample?(_previous_data, _sample_id), do: true

  defp telemetry_chart_series(%Frame{shape: :wide, fields: fields} = frame, placement_frames) do
    with %{values: times} <- time_series_time_field(fields),
         value_field when not is_nil(value_field) <- value_field(fields) do
      values = value_field.values
      sample_ids = metadata_values(value_field.metadata, :sample_ids)

      points =
        times
        |> Enum.with_index()
        |> Enum.flat_map(&series_chart_point(&1, values, sample_ids, value_field.metadata))

      if points == [] do
        []
      else
        [chart_series(frame, value_field, points, placement_frames)]
      end
    else
      _missing -> []
    end
  end

  defp telemetry_chart_series(%Frame{}, _placement_frames), do: []

  defp chart_series(%Frame{} = frame, value_field, points, placement_frames \\ nil) do
    observable_id = observable_id(frame) || metadata_value(value_field.metadata, :observable_id)

    %{
      id: observable_id || value_field.name || frame.frame_id,
      label: metadata_value(value_field.metadata, :label) || observable_id || value_field.name,
      observable_id: observable_id,
      unit: metadata_value(value_field.metadata, :unit) || metadata_value(frame.meta, :unit),
      source: frame.source,
      frame_id: frame.frame_id,
      field: value_field.name,
      time_axis: frame.time_axis,
      sampling: metadata_value(frame.meta, :sampling),
      decimation: metadata_value(frame.meta, :decimation),
      data_source_id: metadata_value(frame.meta, :data_source_id),
      source_binding_id: metadata_value(frame.meta, :source_binding_id),
      data_management: DataManagementPresentation.frame(frame),
      links: chart_links(frame),
      envelope: chart_envelope(frame, observable_id, placement_frames),
      points: points
    }
    |> drop_nil_values()
  end

  defp chart_envelope(%Frame{fields: fields}, observable_id, placement_frames)
       when is_binary(observable_id) do
    with %{values: times} <- time_series_time_field(fields),
         %{values: min_values} = min_field <- field_by_name(fields, "#{observable_id}_min"),
         %{values: max_values} = max_field <- field_by_name(fields, "#{observable_id}_max") do
      sample_counts = field_values(fields, "#{observable_id}_sample_count")
      bucket_ends = field_values(fields, "bucket_end")
      limit_rollups = limit_bucket_rollups(placement_frames, times, bucket_ends)

      points =
        times
        |> Enum.with_index()
        |> Enum.flat_map(
          &envelope_chart_point(&1, min_values, max_values, sample_counts, limit_rollups)
        )

      if points == [] do
        nil
      else
        %{
          kind: :min_max,
          lower_field: min_field.name,
          upper_field: max_field.name,
          sample_count_field: "#{observable_id}_sample_count",
          points: points
        }
      end
    else
      _missing -> nil
    end
  end

  defp chart_envelope(%Frame{}, _observable_id, _placement_frames), do: nil

  defp chart_links(%Frame{} = frame) do
    case WidgetLinks.widget_data_links(frame, nil) do
      [] -> nil
      links -> links
    end
  end

  defp envelope_chart_point(
         {%DateTime{} = time, index},
         min_values,
         max_values,
         sample_counts,
         limit_rollups
       ) do
    min_value = Enum.at(min_values, index)
    max_value = Enum.at(max_values, index)

    if is_number(min_value) and is_number(max_value) do
      metadata =
        %{sample_count: Enum.at(sample_counts, index)}
        |> Map.merge(Map.get(limit_rollups, index, %{}))
        |> chart_point_metadata()

      point = [DateTime.to_unix(time, :millisecond), min_value, max_value]

      if metadata == %{}, do: [point], else: [point ++ [metadata]]
    else
      []
    end
  end

  defp envelope_chart_point(_point, _min_values, _max_values, _sample_counts, _limit_rollups),
    do: []

  defp series_chart_point({%DateTime{} = time, index}, values, sample_ids, metadata) do
    case Enum.at(values, index) do
      value when is_number(value) ->
        sample_id = Enum.at(sample_ids, index)

        [
          chart_datum(
            time,
            value,
            %{sample_id: sample_id}
            |> Map.merge(point_link_metadata(metadata, sample_id))
          )
        ]

      _other ->
        []
    end
  end

  defp series_chart_point(_point, _values, _sample_ids, _metadata), do: []

  defp chart_datum(%DateTime{} = time, value, metadata) do
    metadata = chart_point_metadata(metadata)
    datum = [DateTime.to_unix(time, :millisecond), value]

    if metadata == %{}, do: datum, else: datum ++ [metadata]
  end

  defp chart_point_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.take([
      :sample_id,
      :link_id,
      :target,
      :target_id,
      :sample_count,
      :worst_limit_normalized_state,
      :worst_limit_state,
      :limit_divergence_count,
      :limit_marker_ids,
      :limit_event_ids,
      :limit_sample_ids,
      :limit_semantics_modes,
      :limit_analysis_bases,
      :limit_selected_clocks,
      :limit_selected_definition_intervals
    ])
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp chart_point_metadata(_metadata), do: %{}

  defp latest_series_sample_data(%Frame{shape: :wide, fields: fields} = frame) do
    with %{values: times} <- time_series_time_field(fields),
         value_field when not is_nil(value_field) <- value_field(fields),
         %DateTime{} = time <- List.last(times),
         value when not is_nil(value) <- List.last(value_field.values) do
      %{
        kind: :point,
        spacecraft_id: spacecraft_id(frame.scope),
        sample: %{
          sample_id:
            value_field.metadata
            |> metadata_values(:sample_ids)
            |> List.last(),
          raw_value: value,
          engineering_value: value,
          receipt_time: time,
          generation_time: time,
          quality_state:
            value_field.metadata
            |> metadata_values(:quality_states)
            |> List.last()
        },
        limit_event: nil,
        links: WidgetLinks.widget_data_links(frame, nil),
        data_management: DataManagementPresentation.frame(frame),
        source_request_id: metadata_value(frame.meta, :source_request_id),
        logical_source: frame.source,
        realm: metadata_value(frame.meta, :realm),
        data_source_id: metadata_value(frame.meta, :data_source_id),
        source_binding_id: metadata_value(frame.meta, :source_binding_id),
        replay_run_id: metadata_value(frame.meta, :replay_run_id),
        dataset: metadata_value(frame.meta, :dataset),
        stale?: watermark_unknown?(frame),
        unresolved?: false,
        engine_backed?: true
      }
      |> Map.merge(frame_query_scope_context(frame))
    else
      _missing -> nil
    end
  end

  defp latest_series_sample_data(%Frame{}), do: nil

  defp limit_bucket_rollups(%PlacementFrames{} = placement_frames, bucket_starts, bucket_ends) do
    markers = TimeSeriesLimitMarkers.limit_markers(placement_frames)

    bucket_starts
    |> Enum.with_index()
    |> Map.new(fn {bucket_start, index} ->
      bucket_end = Enum.at(bucket_ends, index) || Enum.at(bucket_starts, index + 1)

      {index, limit_bucket_rollup(markers, bucket_start, bucket_end)}
    end)
    |> Enum.reject(fn {_index, rollup} -> rollup == %{} end)
    |> Map.new()
  end

  defp limit_bucket_rollups(_placement_frames, _bucket_starts, _bucket_ends), do: %{}

  defp limit_bucket_rollup(markers, %DateTime{} = bucket_start, bucket_end) do
    bucket_markers =
      Enum.filter(markers, &marker_in_bucket?(&1, bucket_start, bucket_end))

    case bucket_markers do
      [] ->
        %{}

      _markers ->
        worst_marker = Enum.max_by(bucket_markers, &limit_marker_severity/1)

        %{
          worst_limit_normalized_state: Map.get(worst_marker, :normalized_state),
          worst_limit_state: Map.get(worst_marker, :limit_state),
          limit_divergence_count: limit_divergence_count(bucket_markers),
          limit_marker_ids: bucket_marker_values(bucket_markers, :marker_id),
          limit_event_ids: bucket_marker_values(bucket_markers, :limit_event_id),
          limit_sample_ids: bucket_marker_values(bucket_markers, :sample_id),
          limit_semantics_modes: bucket_marker_values(bucket_markers, :semantics_mode),
          limit_analysis_bases: bucket_marker_values(bucket_markers, :analysis_basis),
          limit_selected_clocks: bucket_marker_values(bucket_markers, :selected_limit_clock),
          limit_selected_definition_intervals:
            bucket_marker_values(bucket_markers, :selected_limit_definition_intervals)
        }
        |> Map.reject(fn {_key, value} -> value in [nil, "", []] end)
    end
  end

  defp limit_bucket_rollup(_markers, _bucket_start, _bucket_end), do: %{}

  defp marker_in_bucket?(%{timestamp_ms: timestamp_ms}, %DateTime{} = bucket_start, bucket_end)
       when is_integer(timestamp_ms) do
    starts_at_ms = DateTime.to_unix(bucket_start, :millisecond)
    ends_at_ms = datetime_to_ms(bucket_end)

    timestamp_ms >= starts_at_ms and (is_nil(ends_at_ms) or timestamp_ms < ends_at_ms)
  end

  defp marker_in_bucket?(_marker, _bucket_start, _bucket_end), do: false

  defp datetime_to_ms(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :millisecond)
  defp datetime_to_ms(_datetime), do: nil

  defp limit_marker_severity(%{normalized_state: "red"}), do: 2
  defp limit_marker_severity(%{normalized_state: :red}), do: 2
  defp limit_marker_severity(%{normalized_state: "yellow"}), do: 1
  defp limit_marker_severity(%{normalized_state: :yellow}), do: 1
  defp limit_marker_severity(_marker), do: 0

  defp limit_divergence_count(markers) do
    markers
    |> Enum.map(&marker_divergence_count/1)
    |> Enum.sum()
  end

  defp marker_divergence_count(%{limit_divergence_count: value}) when is_integer(value),
    do: value

  defp marker_divergence_count(%{limit_state_diverged: true}), do: 1
  defp marker_divergence_count(_marker), do: 0

  defp bucket_marker_values(markers, key) do
    markers
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp value_field(fields) do
    Enum.find(fields, &representative_value_field?/1) ||
      Enum.find(fields, fn field -> field.name not in ["time", "bucket_start", "bucket_end"] end)
  end

  defp representative_value_field?(%{name: name}) when is_binary(name),
    do: String.ends_with?(name, "_value")

  defp representative_value_field?(_field), do: false

  defp time_series_time_field(fields) do
    field_by_name(fields, "time") || field_by_name(fields, "bucket_start")
  end

  defp metadata_values(metadata, key) when is_map(metadata) and is_atom(key) do
    metadata
    |> Map.get(key, Map.get(metadata, Atom.to_string(key), []))
    |> List.wrap()
  end

  defp metadata_values(_metadata, _key), do: []

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key),
    do: Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))

  defp metadata_value(_metadata, _key), do: nil

  defp sample_link_id(metadata, sample_id) when is_binary(sample_id) and sample_id != "" do
    metadata
    |> WidgetLinks.data_links()
    |> Enum.find_value(fn
      %DataLink{target: :telemetry_sample, target_id: ^sample_id, link_id: link_id} -> link_id
      _link -> nil
    end)
  end

  defp sample_link_id(_metadata, _sample_id), do: nil

  defp point_link_metadata(metadata, sample_id) do
    case sample_link_id(metadata, sample_id) do
      link_id when is_binary(link_id) and link_id != "" ->
        %{link_id: link_id}

      _missing_sample_link ->
        resource_link_metadata(metadata)
    end
  end

  defp resource_link_metadata(metadata) do
    resource_link_id = metadata_value(metadata, :resource_link_id)

    metadata
    |> WidgetLinks.data_links()
    |> Enum.find(&(&1.link_id == resource_link_id))
    |> case do
      %DataLink{} = link ->
        %{link_id: link.link_id, target: data_ref_text(link.target), target_id: link.target_id}

      _missing ->
        %{link_id: resource_link_id}
    end
  end

  defp field_values(fields, field_name) do
    case field_by_name(fields, field_name) do
      %{values: values} when is_list(values) -> values
      _missing -> []
    end
  end

  defp field_by_name(fields, name), do: Enum.find(fields, &(&1.name == name))

  defp watermark_unknown?(%Frame{meta: meta}) when is_map(meta) do
    :watermark_unknown in List.wrap(
      Map.get(meta, :warning_codes, Map.get(meta, "warning_codes", []))
    )
  end

  defp watermark_unknown?(%Frame{}), do: false

  defp observable_id(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :observable_id, Map.get(meta, "observable_id"))
  end

  defp data_ref_text(nil), do: nil
  defp data_ref_text(value) when is_atom(value), do: Atom.to_string(value)
  defp data_ref_text(value) when is_binary(value), do: value
  defp data_ref_text(value), do: to_string(value)

  defp frame_query_scope_context(%Frame{scope: scope}) when is_map(scope) do
    scope_kind = ScopeContext.primary_kind(scope)
    scope_ids = ScopeContext.primary_ids(scope)

    %{
      query_scope_kind: scope_kind && to_string(scope_kind),
      query_scope_id: List.first(scope_ids),
      query_scope_ids: scope_ids
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Map.new()
  end

  defp frame_query_scope_context(%Frame{}), do: %{}

  defp spacecraft_id(scope) do
    ScopeContext.scope_id(scope, :spacecraft) || legacy_spacecraft_id(scope)
  end

  defp legacy_spacecraft_id(scope) do
    if is_nil(ScopeContext.primary_kind(scope)) do
      scope
      |> ScopeContext.primary_ids()
      |> List.first()
    end
  end

  defp drop_nil_values(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
