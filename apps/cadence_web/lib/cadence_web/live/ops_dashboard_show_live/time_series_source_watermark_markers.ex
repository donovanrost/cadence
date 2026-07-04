defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesSourceWatermarkMarkers do
  @moduledoc false

  alias Cadence.Dashboards.{DataLink, Frame, PlacementFrames}

  import CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkerSupport

  def event_frame?(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :family, Map.get(meta, "family")) in [:source_watermark, "source_watermark"]
  end

  def event_frame?(%Frame{}), do: false

  def event_markers(%Frame{fields: fields} = frame) do
    source_context = source_marker_context(frame.meta)
    links = event_links(frame, :source_watermark_event)
    occurred_at = field_values(fields, "occurred_at")
    kinds = field_values(fields, "kind")
    severities = field_values(fields, "severity")
    titles = field_values(fields, "title")
    source_record_ids = field_values(fields, "source_record_id")
    logical_sources = field_values(fields, "logical_source")
    data_source_ids = field_values(fields, "data_source_id")
    source_binding_ids = field_values(fields, "source_binding_id")
    realms = field_values(fields, "realm")
    datasets = field_values(fields, "dataset")
    complete_through = field_values(fields, "complete_through")
    previous_complete_through = field_values(fields, "previous_complete_through")
    latest_receipt_time = field_values(fields, "latest_receipt_time")
    previous_latest_receipt_time = field_values(fields, "previous_latest_receipt_time")
    retention_starts_at = field_values(fields, "retention_starts_at")
    confidence = field_values(fields, "confidence")
    reasons = field_values(fields, "reason")

    occurred_at
    |> Enum.with_index()
    |> Enum.map(fn {time, index} ->
      source_watermark_event_marker(%{
        time: time,
        kind: Enum.at(kinds, index),
        severity: Enum.at(severities, index),
        title: Enum.at(titles, index),
        source_record_id: Enum.at(source_record_ids, index),
        logical_source: Enum.at(logical_sources, index),
        data_source_id: Enum.at(data_source_ids, index),
        source_binding_id: Enum.at(source_binding_ids, index),
        realm: Enum.at(realms, index),
        dataset: Enum.at(datasets, index),
        complete_through: Enum.at(complete_through, index),
        previous_complete_through: Enum.at(previous_complete_through, index),
        latest_receipt_time: Enum.at(latest_receipt_time, index),
        previous_latest_receipt_time: Enum.at(previous_latest_receipt_time, index),
        retention_starts_at: Enum.at(retention_starts_at, index),
        confidence: Enum.at(confidence, index),
        reason: Enum.at(reasons, index),
        source_context: source_context,
        link: Enum.at(links, index)
      })
    end)
    |> Enum.reject(&is_nil/1)
  end

  def event_markers(_frame), do: []

  def frame_markers(%PlacementFrames{primary: frames}) when is_list(frames) do
    frames
    |> Enum.flat_map(&frame_source_watermark_markers/1)
    |> Enum.uniq_by(&Map.get(&1, :marker_id))
  end

  def frame_markers(_placement_frames), do: []

  defp source_watermark_event_marker(
         %{
           time: %DateTime{} = time,
           link: %DataLink{} = link
         } = attrs
       ) do
    source_context = Map.get(attrs, :source_context, %{})
    cursor_time = source_watermark_event_cursor_time(attrs) || time
    source_record_id = first_present([Map.get(attrs, :source_record_id), link.target_id])

    data_source_id =
      first_present([Map.get(attrs, :data_source_id), Map.get(source_context, :data_source_id)])

    source_binding_id =
      first_present([
        Map.get(attrs, :source_binding_id),
        Map.get(source_context, :source_binding_id)
      ])

    logical_source =
      first_present([Map.get(attrs, :logical_source), Map.get(source_context, :logical_source)])

    realm = first_present([Map.get(attrs, :realm), Map.get(source_context, :realm)])
    dataset = first_present([Map.get(attrs, :dataset), Map.get(source_context, :dataset)])

    target_id =
      first_present([source_record_id, link.target_id, data_source_id, source_binding_id])

    %{
      marker_type: "source_watermark_event",
      marker_id: source_watermark_event_marker_id(source_record_id, data_source_id, cursor_time),
      timestamp_ms: DateTime.to_unix(cursor_time, :millisecond),
      observed_at_ms: DateTime.to_unix(time, :millisecond),
      link_id: data_link_id(link),
      data_link_target: data_link_target(link),
      data_link_target_id: data_link_target_id(link),
      target: "source_watermark",
      target_id: target_id,
      source_watermark_event_id: link.target_id,
      source_request_id: Map.get(source_context, :source_request_id),
      logical_source: marker_value_text(logical_source),
      source_binding_id: source_binding_id,
      data_source_id: data_source_id,
      dataset: dataset,
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
      event_kind: marker_value_text(Map.get(attrs, :kind)),
      severity: marker_value_text(Map.get(attrs, :severity)),
      title: Map.get(attrs, :title),
      reason: marker_value_text(Map.get(attrs, :reason)),
      confidence: marker_value_text(Map.get(attrs, :confidence)),
      complete_through_ms: timestamp_ms(Map.get(attrs, :complete_through)),
      previous_complete_through_ms: timestamp_ms(Map.get(attrs, :previous_complete_through)),
      latest_receipt_time_ms: timestamp_ms(Map.get(attrs, :latest_receipt_time)),
      previous_latest_receipt_time_ms:
        timestamp_ms(Map.get(attrs, :previous_latest_receipt_time)),
      retention_starts_at_ms: timestamp_ms(Map.get(attrs, :retention_starts_at)),
      label:
        source_watermark_event_marker_label(
          Map.get(attrs, :kind),
          data_source_id,
          source_binding_id
        )
    }
    |> drop_nil_values()
  end

  defp source_watermark_event_marker(_attrs), do: nil

  defp first_present(values) do
    Enum.find(values, &present?/1)
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true

  defp source_watermark_event_cursor_time(attrs) do
    cond do
      match?(%DateTime{}, Map.get(attrs, :complete_through)) ->
        Map.get(attrs, :complete_through)

      match?(%DateTime{}, Map.get(attrs, :latest_receipt_time)) ->
        Map.get(attrs, :latest_receipt_time)

      true ->
        nil
    end
  end

  defp source_watermark_event_marker_id(
         source_record_id,
         data_source_id,
         %DateTime{} = cursor_time
       ) do
    [
      "source-watermark-event",
      source_record_id || data_source_id,
      DateTime.to_unix(cursor_time, :millisecond)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp source_watermark_event_marker_label(kind, nil, nil),
    do: "Watermark #{marker_value_text(kind) || "event"}"

  defp source_watermark_event_marker_label(kind, data_source_id, nil),
    do: "Watermark #{marker_value_text(kind) || "event"} / #{data_source_id}"

  defp source_watermark_event_marker_label(kind, nil, source_binding_id),
    do: "Watermark #{marker_value_text(kind) || "event"} / #{source_binding_id}"

  defp source_watermark_event_marker_label(kind, data_source_id, source_binding_id),
    do:
      "Watermark #{marker_value_text(kind) || "event"} / #{source_binding_id} / #{data_source_id}"

  defp frame_source_watermark_markers(%Frame{meta: meta}) when is_map(meta) do
    request_context = source_marker_context(meta)

    requested_start =
      meta
      |> context_value(:source_request_time_context)
      |> request_context_or_empty()
      |> first_datetime([:from, :start, :start_time])

    meta
    |> Map.get(:source_watermarks, [])
    |> List.wrap()
    |> Enum.flat_map(fn watermark ->
      [
        retention_gap_marker(watermark, requested_start, request_context),
        source_watermark_cursor_marker(watermark, request_context)
      ]
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp frame_source_watermark_markers(%Frame{}), do: []

  defp retention_gap_marker(watermark, %DateTime{} = requested_start, request_context)
       when is_map(watermark) do
    with :retention_gap <- context_atom(watermark, :freshness_state),
         %DateTime{} = retention_starts_at <- context_datetime(watermark, :retention_starts_at),
         :lt <- DateTime.compare(requested_start, retention_starts_at) do
      request_id = context_value(watermark, :request_id)
      data_source_id = context_value(watermark, :data_source_id)
      source_binding_id = context_value(watermark, :source_binding_id)
      logical_source = context_value(watermark, :logical_source)
      realm = context_value(watermark, :realm)

      %{
        marker_type: "retention_gap",
        marker_id: retention_gap_marker_id(request_id, data_source_id, retention_starts_at),
        starts_at_ms: DateTime.to_unix(requested_start, :millisecond),
        ends_at_ms: DateTime.to_unix(retention_starts_at, :millisecond),
        timestamp_ms: DateTime.to_unix(retention_starts_at, :millisecond),
        target: "source_watermark",
        target_id: request_id || data_source_id || source_binding_id,
        source_request_id: request_id,
        logical_source: marker_value_text(logical_source),
        source_binding_id: source_binding_id,
        data_source_id: data_source_id,
        dataset: context_value(watermark, :dataset),
        realm: marker_value_text(realm),
        time_mode: marker_value_text(Map.get(request_context, :time_mode)),
        time_axis: marker_value_text(Map.get(request_context, :time_axis)),
        replay_run_id: Map.get(request_context, :replay_run_id),
        requested_realm: marker_value_text(Map.get(request_context, :requested_realm)),
        requested_data_view: marker_value_text(Map.get(request_context, :requested_data_view)),
        requested_data_source_id: Map.get(request_context, :requested_data_source_id),
        requested_source_binding_id: Map.get(request_context, :requested_source_binding_id),
        requested_dataset: Map.get(request_context, :requested_dataset),
        requested_validity_state:
          marker_value_text(Map.get(request_context, :requested_validity_state)),
        confidence: marker_value_text(context_value(watermark, :confidence)),
        freshness_state: "retention_gap",
        complete_through_ms: timestamp_ms(context_datetime(watermark, :complete_through)),
        latest_receipt_time_ms: timestamp_ms(context_datetime(watermark, :latest_receipt_time)),
        retention_starts_at_ms: DateTime.to_unix(retention_starts_at, :millisecond),
        label: retention_gap_marker_label(data_source_id, source_binding_id)
      }
      |> drop_nil_values()
    else
      _other -> nil
    end
  end

  defp retention_gap_marker(_watermark, _requested_start, _request_context), do: nil

  defp source_watermark_cursor_marker(watermark, request_context) when is_map(watermark) do
    case source_watermark_cursor(watermark) do
      {cursor_kind, %DateTime{} = cursor_time} ->
        request_id = context_value(watermark, :request_id)
        data_source_id = context_value(watermark, :data_source_id)
        source_binding_id = context_value(watermark, :source_binding_id)
        logical_source = context_value(watermark, :logical_source)
        realm = context_value(watermark, :realm)

        %{
          marker_type: "source_watermark_cursor",
          marker_id:
            source_watermark_cursor_marker_id(
              request_id,
              data_source_id,
              cursor_kind,
              cursor_time
            ),
          timestamp_ms: DateTime.to_unix(cursor_time, :millisecond),
          target: "source_watermark",
          target_id: request_id || data_source_id || source_binding_id,
          source_request_id: request_id,
          logical_source: marker_value_text(logical_source),
          source_binding_id: source_binding_id,
          data_source_id: data_source_id,
          dataset: context_value(watermark, :dataset),
          realm: marker_value_text(realm),
          time_mode: marker_value_text(Map.get(request_context, :time_mode)),
          time_axis: marker_value_text(Map.get(request_context, :time_axis)),
          replay_run_id: Map.get(request_context, :replay_run_id),
          requested_realm: marker_value_text(Map.get(request_context, :requested_realm)),
          requested_data_view: marker_value_text(Map.get(request_context, :requested_data_view)),
          requested_data_source_id: Map.get(request_context, :requested_data_source_id),
          requested_source_binding_id: Map.get(request_context, :requested_source_binding_id),
          requested_dataset: Map.get(request_context, :requested_dataset),
          requested_validity_state:
            marker_value_text(Map.get(request_context, :requested_validity_state)),
          cursor_kind: marker_value_text(cursor_kind),
          confidence: marker_value_text(context_value(watermark, :confidence)),
          freshness_state: marker_value_text(context_value(watermark, :freshness_state)),
          complete_through_ms: timestamp_ms(context_datetime(watermark, :complete_through)),
          latest_receipt_time_ms: timestamp_ms(context_datetime(watermark, :latest_receipt_time)),
          source_watermark_event_id: context_value(watermark, :source_watermark_event_id),
          label:
            source_watermark_cursor_marker_label(cursor_kind, data_source_id, source_binding_id)
        }
        |> drop_nil_values()

      nil ->
        nil
    end
  end

  defp source_watermark_cursor_marker(_watermark, _request_context), do: nil

  defp source_watermark_cursor(watermark) when is_map(watermark) do
    cond do
      match?(%DateTime{}, context_datetime(watermark, :complete_through)) ->
        {:complete_through, context_datetime(watermark, :complete_through)}

      match?(%DateTime{}, context_datetime(watermark, :latest_receipt_time)) ->
        {:latest_receipt_time, context_datetime(watermark, :latest_receipt_time)}

      true ->
        nil
    end
  end

  defp source_watermark_cursor_marker_id(
         request_id,
         data_source_id,
         cursor_kind,
         %DateTime{} = cursor_time
       ) do
    [
      "source-watermark-cursor",
      request_id || data_source_id,
      cursor_kind,
      DateTime.to_unix(cursor_time, :millisecond)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp source_watermark_cursor_marker_label(:latest_receipt_time, nil, nil),
    do: "Watermark latest receipt"

  defp source_watermark_cursor_marker_label(:latest_receipt_time, data_source_id, nil),
    do: "Watermark latest receipt / #{data_source_id}"

  defp source_watermark_cursor_marker_label(:latest_receipt_time, nil, source_binding_id),
    do: "Watermark latest receipt / #{source_binding_id}"

  defp source_watermark_cursor_marker_label(
         :latest_receipt_time,
         data_source_id,
         source_binding_id
       ),
       do: "Watermark latest receipt / #{source_binding_id} / #{data_source_id}"

  defp source_watermark_cursor_marker_label(_cursor_kind, nil, nil),
    do: "Watermark complete through"

  defp source_watermark_cursor_marker_label(_cursor_kind, data_source_id, nil),
    do: "Watermark complete through / #{data_source_id}"

  defp source_watermark_cursor_marker_label(_cursor_kind, nil, source_binding_id),
    do: "Watermark complete through / #{source_binding_id}"

  defp source_watermark_cursor_marker_label(_cursor_kind, data_source_id, source_binding_id),
    do: "Watermark complete through / #{source_binding_id} / #{data_source_id}"

  defp retention_gap_marker_id(request_id, data_source_id, %DateTime{} = retention_starts_at) do
    [
      "retention-gap",
      request_id || data_source_id,
      DateTime.to_unix(retention_starts_at, :millisecond)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp retention_gap_marker_label(nil, nil), do: "Retention gap"
  defp retention_gap_marker_label(data_source_id, nil), do: "Retention gap / #{data_source_id}"

  defp retention_gap_marker_label(nil, source_binding_id),
    do: "Retention gap / #{source_binding_id}"

  defp retention_gap_marker_label(data_source_id, source_binding_id),
    do: "Retention gap / #{source_binding_id} / #{data_source_id}"

  defp first_datetime(context, keys) when is_map(context) and is_list(keys) do
    Enum.find_value(keys, &context_datetime(context, &1))
  end

  defp first_datetime(_context, _keys), do: nil

  defp context_datetime(context, key) when is_map(context) do
    case context_value(context, key) do
      %DateTime{} = value ->
        value

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> datetime
          _error -> nil
        end

      _value ->
        nil
    end
  end

  defp context_atom(context, key) when is_map(context) do
    case context_value(context, key) do
      value when is_atom(value) -> value
      value when is_binary(value) -> String.to_existing_atom(value)
      _value -> nil
    end
  rescue
    ArgumentError -> nil
  end
end
