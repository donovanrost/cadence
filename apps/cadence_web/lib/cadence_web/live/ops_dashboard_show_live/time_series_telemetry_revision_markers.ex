defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesTelemetryRevisionMarkers do
  @moduledoc false

  alias Cadence.Dashboards.{Frame, PlacementFrames}

  alias CadenceWeb.OpsDashboardShowLive.WidgetLifecyclePresentation

  import CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkerSupport

  def range_markers(%PlacementFrames{primary: frames}) when is_list(frames) do
    frames
    |> Enum.flat_map(&frame_telemetry_revision_markers/1)
    |> Enum.uniq_by(& &1.marker_id)
  end

  def range_markers(%PlacementFrames{}), do: []
  def range_markers(_placement_frames), do: []

  @spec event_frame?(Frame.t()) :: boolean()
  def event_frame?(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :family, Map.get(meta, "family")) in [
      :telemetry_revision,
      "telemetry_revision"
    ]
  end

  def event_frame?(%Frame{}), do: false

  @spec event_markers(Frame.t()) :: [map()]
  def event_markers(%Frame{fields: fields} = frame) do
    source_context = source_marker_context(frame.meta)
    links = event_links(frame, :telemetry_revision_decision_event)
    occurred_at = field_values(fields, "occurred_at")
    kinds = field_values(fields, "kind")
    severities = field_values(fields, "severity")
    titles = field_values(fields, "title")
    source_record_ids = field_values(fields, "source_record_id")
    observation_identity_ids = field_values(fields, "observation_identity_id")
    realms = field_values(fields, "realm")
    data_source_ids = field_values(fields, "data_source_id")
    source_binding_ids = field_values(fields, "source_binding_id")
    observable_ids = field_values(fields, "observable_id")
    point_ids = field_values(fields, "point_id")
    spacecraft_ids = field_values(fields, "spacecraft_id")
    decision_reasons = field_values(fields, "decision_reason")
    actor_ids = field_values(fields, "actor_id")
    actor_kinds = field_values(fields, "actor_kind")
    previous_validity_states = field_values(fields, "previous_validity_state")
    new_validity_states = field_values(fields, "new_validity_state")
    previous_canonical_revisions = field_values(fields, "previous_canonical_revision")
    new_canonical_revisions = field_values(fields, "new_canonical_revision")

    occurred_at
    |> Enum.with_index()
    |> Enum.map(fn {time, index} ->
      decision_event_marker(%{
        time: time,
        kind: Enum.at(kinds, index),
        severity: Enum.at(severities, index),
        title: Enum.at(titles, index),
        source_record_id: Enum.at(source_record_ids, index),
        observation_identity_id: Enum.at(observation_identity_ids, index),
        realm: Enum.at(realms, index),
        data_source_id: Enum.at(data_source_ids, index),
        source_binding_id: Enum.at(source_binding_ids, index),
        observable_id: Enum.at(observable_ids, index),
        point_id: Enum.at(point_ids, index),
        spacecraft_id: Enum.at(spacecraft_ids, index),
        decision_reason: Enum.at(decision_reasons, index),
        actor_id: Enum.at(actor_ids, index),
        actor_kind: Enum.at(actor_kinds, index),
        previous_validity_state: Enum.at(previous_validity_states, index),
        new_validity_state: Enum.at(new_validity_states, index),
        previous_canonical_revision: Enum.at(previous_canonical_revisions, index),
        new_canonical_revision: Enum.at(new_canonical_revisions, index),
        link: Enum.at(links, index),
        source_context: source_context
      })
    end)
    |> Enum.reject(&is_nil/1)
  end

  def event_markers(_frame), do: []

  defp frame_telemetry_revision_markers(%Frame{source: :telemetry, meta: meta} = frame)
       when is_map(meta) do
    warning_codes =
      meta
      |> Map.get(:warning_codes, [])
      |> List.wrap()
      |> Enum.map(&WidgetLifecyclePresentation.normalize_warning_code/1)

    source_context = source_marker_context(meta)

    [:corrected_range, :advisory_backfill]
    |> Enum.filter(&(&1 in warning_codes))
    |> Enum.map(&telemetry_revision_marker(frame, &1, source_context))
    |> Enum.reject(&is_nil/1)
  end

  defp frame_telemetry_revision_markers(%Frame{}), do: []

  defp telemetry_revision_marker(%Frame{fields: fields, meta: meta}, warning_code, source_context)
       when is_map(meta) do
    with {%DateTime{} = starts_at, %DateTime{} = ends_at} <- frame_time_range(fields) do
      revision_state = context_value(meta, :revision_state) |> request_context_or_empty()
      dependency = revision_dependency(meta, revision_state)
      target_id = context_value(dependency, :fingerprint) || context_value(meta, :observable_id)

      %{
        marker_type: "telemetry_revision_range",
        marker_id:
          telemetry_revision_marker_id(
            warning_code,
            target_id,
            context_value(meta, :observable_id),
            starts_at,
            ends_at
          ),
        starts_at_ms: DateTime.to_unix(starts_at, :millisecond),
        ends_at_ms: DateTime.to_unix(ends_at, :millisecond),
        timestamp_ms: DateTime.to_unix(ends_at, :millisecond),
        target: "telemetry_revision_state",
        target_id: target_id,
        source_request_id: Map.get(source_context, :source_request_id),
        logical_source: marker_value_text(Map.get(source_context, :logical_source)),
        source_binding_id: Map.get(source_context, :source_binding_id),
        data_source_id: Map.get(source_context, :data_source_id),
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
          marker_value_text(Map.get(source_context, :requested_validity_state)),
        observable_id: context_value(meta, :observable_id),
        point_id: context_value(meta, :point_id),
        data_view: marker_value_text(context_value(meta, :data_view)),
        revision_state: telemetry_revision_marker_state(warning_code),
        warning_code: marker_value_text(warning_code),
        dependency_fingerprint: context_value(revision_state, :dependency_fingerprint),
        identity_count: context_value(revision_state, :identity_count),
        canonical_count: context_value(revision_state, :canonical_count),
        superseded_count: context_value(revision_state, :superseded_count),
        advisory_count: context_value(revision_state, :advisory_count),
        conflict_count: context_value(revision_state, :conflict_count),
        duplicate_count: context_value(revision_state, :duplicate_count),
        label: telemetry_revision_marker_label(warning_code, context_value(meta, :observable_id))
      }
      |> drop_nil_values()
    end
  end

  defp frame_time_range(fields) do
    starts =
      field_values(fields, "time") ++
        field_values(fields, "bucket_start")

    ends =
      field_values(fields, "time") ++
        field_values(fields, "bucket_end")

    with %DateTime{} = starts_at <- earliest_datetime(starts),
         %DateTime{} = ends_at <- latest_datetime(ends) do
      {starts_at, ends_at}
    else
      _other -> nil
    end
  end

  defp revision_dependency(meta, revision_state) do
    case context_value(meta, :telemetry_revision_dependency) do
      dependency when is_map(dependency) -> dependency
      _missing -> context_value(revision_state, :dependency) |> request_context_or_empty()
    end
  end

  defp telemetry_revision_marker_id(
         warning_code,
         target_id,
         observable_id,
         %DateTime{} = starts_at,
         %DateTime{} = ends_at
       ) do
    [
      "telemetry-revision",
      warning_code,
      target_id || observable_id,
      DateTime.to_unix(starts_at, :millisecond),
      DateTime.to_unix(ends_at, :millisecond)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp telemetry_revision_marker_state(:corrected_range), do: "corrected"
  defp telemetry_revision_marker_state(:advisory_backfill), do: "backfill"
  defp telemetry_revision_marker_state(warning_code), do: marker_value_text(warning_code)

  defp telemetry_revision_marker_label(:corrected_range, nil), do: "Corrected telemetry range"

  defp telemetry_revision_marker_label(:corrected_range, observable_id),
    do: "Corrected telemetry range / #{observable_id}"

  defp telemetry_revision_marker_label(:advisory_backfill, nil), do: "Backfilled telemetry range"

  defp telemetry_revision_marker_label(:advisory_backfill, observable_id),
    do: "Backfilled telemetry range / #{observable_id}"

  defp decision_event_marker(%{time: %DateTime{} = time} = attrs) do
    source_context = Map.get(attrs, :source_context, %{})
    link = Map.get(attrs, :link)
    source_record_id = Map.get(attrs, :source_record_id)
    observation_identity_id = Map.get(attrs, :observation_identity_id)
    data_source_id = Map.get(attrs, :data_source_id) || Map.get(source_context, :data_source_id)

    source_binding_id =
      Map.get(attrs, :source_binding_id) || Map.get(source_context, :source_binding_id)

    observable_id = Map.get(attrs, :observable_id) || Map.get(attrs, :point_id)
    realm = Map.get(attrs, :realm) || Map.get(source_context, :realm)

    %{
      marker_type: "telemetry_revision_decision",
      marker_id: decision_event_marker_id(source_record_id, time),
      timestamp_ms: DateTime.to_unix(time, :millisecond),
      link_id: data_link_id(link),
      data_link_target: data_link_target(link),
      data_link_target_id: data_link_target_id(link),
      target: "telemetry_revision",
      target_id: observation_identity_id || source_record_id,
      telemetry_revision_decision_event_id: source_record_id,
      observation_identity_id: observation_identity_id,
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
      decision_reason: Map.get(attrs, :decision_reason),
      actor_id: Map.get(attrs, :actor_id),
      actor_kind: marker_value_text(Map.get(attrs, :actor_kind)),
      previous_validity_state: marker_value_text(Map.get(attrs, :previous_validity_state)),
      new_validity_state: marker_value_text(Map.get(attrs, :new_validity_state)),
      previous_canonical_revision: Map.get(attrs, :previous_canonical_revision),
      new_canonical_revision: Map.get(attrs, :new_canonical_revision),
      label:
        decision_event_marker_label(Map.get(attrs, :kind), observable_id, observation_identity_id)
    }
    |> drop_nil_values()
  end

  defp decision_event_marker(_attrs), do: nil

  defp decision_event_marker_id(source_record_id, %DateTime{} = time) do
    [
      "telemetry-revision-decision",
      source_record_id,
      DateTime.to_unix(time, :millisecond)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp decision_event_marker_label(kind, observable_id, observation_identity_id) do
    [
      "Revision #{marker_value_text(kind) || "decision"}",
      observable_id,
      observation_identity_id
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" / ")
  end

  defp earliest_datetime(values) when is_list(values) do
    values
    |> Enum.map(&normalize_datetime/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.min(DateTime, fn -> nil end)
  end

  defp latest_datetime(values) when is_list(values) do
    values
    |> Enum.map(&normalize_datetime/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp normalize_datetime(%DateTime{} = value), do: value

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp normalize_datetime(_value), do: nil
end
