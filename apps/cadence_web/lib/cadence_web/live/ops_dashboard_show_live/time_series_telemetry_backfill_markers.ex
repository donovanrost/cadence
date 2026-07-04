defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesTelemetryBackfillMarkers do
  @moduledoc """
  Projects telemetry backfill lifecycle event frames into chart markers.
  """

  alias Cadence.Dashboards.Frame

  import CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkerSupport

  @spec event_frame?(Frame.t()) :: boolean()
  def event_frame?(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :family, Map.get(meta, "family")) in [
      :telemetry_backfill,
      "telemetry_backfill"
    ]
  end

  def event_frame?(%Frame{}), do: false

  @spec event_markers(Frame.t()) :: [map()]
  def event_markers(%Frame{fields: fields} = frame) do
    source_context = source_marker_context(frame.meta)
    links = event_links(frame, :telemetry_backfill_lifecycle_event)
    occurred_at = field_values(fields, "occurred_at")
    kinds = field_values(fields, "kind")
    severities = field_values(fields, "severity")
    titles = field_values(fields, "title")
    source_record_ids = field_values(fields, "source_record_id")
    backfill_run_ids = field_values(fields, "backfill_run_id")
    realms = field_values(fields, "realm")
    data_source_ids = field_values(fields, "data_source_id")
    source_binding_ids = field_values(fields, "source_binding_id")
    observable_ids = field_values(fields, "observable_id")
    point_ids = field_values(fields, "point_id")
    spacecraft_ids = field_values(fields, "spacecraft_id")
    source_from = field_values(fields, "source_from")
    source_to = field_values(fields, "source_to")
    receipt_from = field_values(fields, "receipt_from")
    receipt_to = field_values(fields, "receipt_to")
    sample_counts = field_values(fields, "sample_count")
    selected_sample_counts = field_values(fields, "selected_sample_count")
    projection_effects = field_values(fields, "projection_effect")
    write_validity_states = field_values(fields, "write_validity_state")
    record_current_values = field_values(fields, "record_current_values")
    refresh_latest_values = field_values(fields, "refresh_latest_value")
    authorities = field_values(fields, "authority")
    reasons = field_values(fields, "reason")
    actor_ids = field_values(fields, "actor_id")
    actor_kinds = field_values(fields, "actor_kind")

    occurred_at
    |> Enum.with_index()
    |> Enum.map(fn {time, index} ->
      event_marker(%{
        time: time,
        kind: Enum.at(kinds, index),
        severity: Enum.at(severities, index),
        title: Enum.at(titles, index),
        source_record_id: Enum.at(source_record_ids, index),
        backfill_run_id: Enum.at(backfill_run_ids, index),
        realm: Enum.at(realms, index),
        data_source_id: Enum.at(data_source_ids, index),
        source_binding_id: Enum.at(source_binding_ids, index),
        observable_id: Enum.at(observable_ids, index),
        point_id: Enum.at(point_ids, index),
        spacecraft_id: Enum.at(spacecraft_ids, index),
        source_from: Enum.at(source_from, index),
        source_to: Enum.at(source_to, index),
        receipt_from: Enum.at(receipt_from, index),
        receipt_to: Enum.at(receipt_to, index),
        sample_count: Enum.at(sample_counts, index),
        selected_sample_count: Enum.at(selected_sample_counts, index),
        projection_effect: Enum.at(projection_effects, index),
        write_validity_state: Enum.at(write_validity_states, index),
        record_current_values: Enum.at(record_current_values, index),
        refresh_latest_value: Enum.at(refresh_latest_values, index),
        authority: Enum.at(authorities, index),
        reason: Enum.at(reasons, index),
        actor_id: Enum.at(actor_ids, index),
        actor_kind: Enum.at(actor_kinds, index),
        link: Enum.at(links, index),
        source_context: source_context
      })
    end)
    |> Enum.reject(&is_nil/1)
  end

  def event_markers(_frame), do: []

  defp event_marker(%{time: %DateTime{} = time} = attrs) do
    source_context = Map.get(attrs, :source_context, %{})
    link = Map.get(attrs, :link)
    source_record_id = Map.get(attrs, :source_record_id)
    backfill_run_id = Map.get(attrs, :backfill_run_id)
    data_source_id = Map.get(attrs, :data_source_id) || Map.get(source_context, :data_source_id)

    source_binding_id =
      Map.get(attrs, :source_binding_id) || Map.get(source_context, :source_binding_id)

    observable_id = Map.get(attrs, :observable_id) || Map.get(attrs, :point_id)
    realm = Map.get(attrs, :realm) || Map.get(source_context, :realm)

    %{
      marker_type: "telemetry_backfill_lifecycle",
      marker_id:
        marker_id(
          source_record_id,
          backfill_run_id,
          Map.get(attrs, :source_from) || time
        ),
      timestamp_ms: DateTime.to_unix(time, :millisecond),
      starts_at_ms: timestamp_ms(Map.get(attrs, :source_from)),
      ends_at_ms: timestamp_ms(Map.get(attrs, :source_to)),
      link_id: data_link_id(link),
      data_link_target: data_link_target(link),
      data_link_target_id: data_link_target_id(link),
      target: "telemetry_backfill",
      target_id: backfill_run_id || source_record_id,
      telemetry_backfill_lifecycle_event_id: source_record_id,
      backfill_run_id: backfill_run_id,
      source_request_id: Map.get(source_context, :source_request_id),
      logical_source: "telemetry",
      source_binding_id: source_binding_id,
      data_source_id: data_source_id,
      dataset: Map.get(source_context, :dataset),
      realm: marker_value_text(realm),
      observable_id: observable_id,
      point_id: Map.get(attrs, :point_id),
      spacecraft_id: Map.get(attrs, :spacecraft_id),
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
      authority: marker_value_text(Map.get(attrs, :authority)),
      sample_count: Map.get(attrs, :sample_count),
      selected_sample_count: Map.get(attrs, :selected_sample_count),
      projection_effect: marker_value_text(Map.get(attrs, :projection_effect)),
      write_validity_state: marker_value_text(Map.get(attrs, :write_validity_state)),
      record_current_values: Map.get(attrs, :record_current_values),
      refresh_latest_value: Map.get(attrs, :refresh_latest_value),
      summary: execution_summary(attrs),
      source_from_ms: timestamp_ms(Map.get(attrs, :source_from)),
      source_to_ms: timestamp_ms(Map.get(attrs, :source_to)),
      receipt_from_ms: timestamp_ms(Map.get(attrs, :receipt_from)),
      receipt_to_ms: timestamp_ms(Map.get(attrs, :receipt_to)),
      actor_id: Map.get(attrs, :actor_id),
      actor_kind: marker_value_text(Map.get(attrs, :actor_kind)),
      revision_state: "backfill",
      label: marker_label(Map.get(attrs, :kind), observable_id, backfill_run_id)
    }
    |> drop_nil_values()
  end

  defp event_marker(_attrs), do: nil

  defp marker_id(source_record_id, backfill_run_id, %DateTime{} = marker_time) do
    [
      "telemetry-backfill-lifecycle",
      source_record_id || backfill_run_id,
      DateTime.to_unix(marker_time, :millisecond)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp marker_label(kind, observable_id, backfill_run_id) do
    [
      label_prefix(kind),
      observable_id,
      backfill_run_id
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" / ")
  end

  defp label_prefix(kind) do
    case marker_value_text(kind) do
      nil ->
        "Backfill event"

      "import_" <> label ->
        "Import #{String.replace(label, "_", " ")}"

      "backfill_" <> label ->
        "Backfill #{String.replace(label, "_", " ")}"

      "late_data_" <> label ->
        "Late data #{String.replace(label, "_", " ")}"

      label ->
        "Backfill #{String.replace(label, "_", " ")}"
    end
  end

  defp execution_summary(attrs) do
    [
      selected_sample_count_summary(Map.get(attrs, :selected_sample_count)),
      write_validity_summary(
        Map.get(attrs, :write_validity_state),
        Map.get(attrs, :projection_effect)
      ),
      projection_refresh_summary(
        Map.get(attrs, :record_current_values),
        Map.get(attrs, :refresh_latest_value)
      ),
      projection_effect_summary(Map.get(attrs, :projection_effect))
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, "; ")
    end
  end

  defp selected_sample_count_summary(nil), do: nil
  defp selected_sample_count_summary(1), do: "1 selected sample"
  defp selected_sample_count_summary(count), do: "#{count} selected samples"

  defp write_validity_summary(nil, _projection_effect), do: nil

  defp write_validity_summary(state, projection_effect) do
    if marker_value_text(projection_effect) == "audit_event_only" do
      "records #{marker_value_text(state)} audit decision"
    else
      "writes #{marker_value_text(state)} history"
    end
  end

  defp projection_refresh_summary(true, true), do: "refreshes current/latest"
  defp projection_refresh_summary(false, false), do: "does not refresh current/latest"
  defp projection_refresh_summary(true, _latest?), do: "refreshes current"
  defp projection_refresh_summary(_current?, true), do: "refreshes latest"
  defp projection_refresh_summary(_current?, _latest?), do: nil

  defp projection_effect_summary(nil), do: nil

  defp projection_effect_summary(effect),
    do: "effect #{marker_value_text(effect)}"
end
