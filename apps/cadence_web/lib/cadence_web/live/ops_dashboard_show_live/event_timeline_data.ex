defmodule CadenceWeb.OpsDashboardShowLive.EventTimelineData do
  @moduledoc false

  alias Cadence.Dashboards.{Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.{DataManagementPresentation, WidgetLinks}

  @stale_warning_codes [
    :watermark_unknown,
    :stale_data,
    :missing_snapshot,
    :unknown_watermark,
    :source_degraded
  ]

  @spec rows(PlacementFrames.t()) :: [map()]
  def rows(%PlacementFrames{primary: frames}) when is_list(frames) do
    frames
    |> Enum.flat_map(&frame_rows/1)
    |> Enum.uniq_by(& &1.row_id)
    |> Enum.sort_by(&sort_key/1)
  end

  @spec stale?(PlacementFrames.t()) :: boolean()
  def stale?(%PlacementFrames{primary: frames}) when is_list(frames) do
    Enum.any?(frames, &frame_stale?/1)
  end

  def stale?(%PlacementFrames{}), do: false

  defp frame_rows(%Frame{source: :events, shape: :intervals, fields: fields} = frame) do
    starts_at = field_values(fields, "starts_at")
    ends_at = field_values(fields, "ends_at")
    kinds = field_values(fields, "kind")
    statuses = field_values(fields, "status")
    labels = field_values(fields, "label")
    contact_ids = field_values(fields, "contact_id")
    source_event_ids = field_values(fields, "source_event_id")
    family = frame_family(frame) || :contacts

    starts_at
    |> Enum.with_index()
    |> Enum.map(fn {start_time, index} ->
      contact_id = Enum.at(contact_ids, index)
      source_event_id = Enum.at(source_event_ids, index)
      kind = Enum.at(kinds, index)
      status = Enum.at(statuses, index)
      label = Enum.at(labels, index)

      %{
        row_id: row_id("interval", contact_id, start_time, index),
        lane: family,
        category: family,
        kind: kind,
        severity: :info,
        status: status,
        title: label || contact_id || "Contact interval",
        occurred_at: start_time,
        starts_at: start_time,
        ends_at: Enum.at(ends_at, index),
        source_record_id: contact_id,
        contact_id: contact_id,
        operational_event_id: source_event_id,
        target: :contact,
        target_id: contact_id,
        links:
          event_links(frame, :contact, contact_id) ++
            event_links(frame, :operational_event, source_event_id),
        stale?: frame_stale?(frame)
      }
      |> Map.merge(frame_source_context(frame))
      |> drop_nil_values()
    end)
  end

  defp frame_rows(%Frame{source: :events, shape: :events, fields: fields} = frame) do
    occurred_at = field_values(fields, "occurred_at")
    categories = field_values(fields, "category")
    kinds = field_values(fields, "kind")
    severities = field_values(fields, "severity")
    titles = field_values(fields, "title")
    mission_event_ids = field_values(fields, "mission_event_id")
    source_record_ids = field_values(fields, "source_record_id")
    operational_event_ids = field_values(fields, "operational_event_id")
    backfill_run_ids = field_values(fields, "backfill_run_id")
    workflow_run_ids = field_values(fields, "workflow_run_id")
    workflow_job_ids = field_values(fields, "workflow_job_id")
    workflow_job_statuses = field_values(fields, "workflow_job_status")
    workflow_job_failures = field_values(fields, "workflow_job_failure")
    logical_sources = field_values(fields, "logical_source")
    data_source_ids = field_values(fields, "data_source_id")
    source_binding_ids = field_values(fields, "source_binding_id")
    realms = field_values(fields, "realm")
    replay_run_ids = field_values(fields, "replay_run_id")
    datasets = field_values(fields, "dataset")
    complete_through_values = field_values(fields, "complete_through")
    previous_complete_through_values = field_values(fields, "previous_complete_through")
    latest_receipt_time_values = field_values(fields, "latest_receipt_time")
    previous_latest_receipt_time_values = field_values(fields, "previous_latest_receipt_time")
    retention_starts_at_values = field_values(fields, "retention_starts_at")
    capability_statuses = field_values(fields, "capability_status")
    requested_time_axes = field_values(fields, "requested_time_axis")
    executed_time_axes = field_values(fields, "executed_time_axis")
    source_execution_statuses = field_values(fields, "source_execution_status")
    source_execution_cache_statuses = field_values(fields, "source_execution_cache_status")
    confidence_values = field_values(fields, "confidence")
    reason_values = field_values(fields, "reason")
    target = event_target(frame)
    family = frame_family(frame)

    occurred_at
    |> Enum.with_index()
    |> Enum.map(fn {time, index} ->
      source_record_id = Enum.at(source_record_ids, index)
      mission_event_id = Enum.at(mission_event_ids, index)
      operational_event_id = Enum.at(operational_event_ids, index)
      category = Enum.at(categories, index) || family || :events

      target_id =
        event_target_id(target, mission_event_id, source_record_id, operational_event_id)

      %{
        row_id: row_id("event", source_record_id, time, index),
        lane: category,
        category: category,
        kind: Enum.at(kinds, index),
        severity: Enum.at(severities, index),
        title: Enum.at(titles, index) || source_record_id || "Event",
        occurred_at: time,
        source_record_id: source_record_id,
        backfill_run_id: Enum.at(backfill_run_ids, index),
        workflow_run_id: Enum.at(workflow_run_ids, index),
        workflow_job_id: Enum.at(workflow_job_ids, index),
        workflow_job_status: Enum.at(workflow_job_statuses, index),
        workflow_job_failure: Enum.at(workflow_job_failures, index),
        target: target,
        target_id: target_id,
        logical_source: Enum.at(logical_sources, index),
        data_source_id: Enum.at(data_source_ids, index),
        source_binding_id: Enum.at(source_binding_ids, index),
        realm: Enum.at(realms, index),
        replay_run_id: Enum.at(replay_run_ids, index),
        dataset: Enum.at(datasets, index),
        complete_through: Enum.at(complete_through_values, index),
        previous_complete_through: Enum.at(previous_complete_through_values, index),
        latest_receipt_time: Enum.at(latest_receipt_time_values, index),
        previous_latest_receipt_time: Enum.at(previous_latest_receipt_time_values, index),
        retention_starts_at: Enum.at(retention_starts_at_values, index),
        capability_status: Enum.at(capability_statuses, index),
        requested_time_axis: Enum.at(requested_time_axes, index),
        executed_time_axis: Enum.at(executed_time_axes, index),
        source_execution_status: Enum.at(source_execution_statuses, index),
        source_execution_cache_status: Enum.at(source_execution_cache_statuses, index),
        confidence: Enum.at(confidence_values, index),
        reason: Enum.at(reason_values, index),
        links: event_links(frame, target, target_id),
        stale?: frame_stale?(frame)
      }
      |> Map.merge(frame_source_context(frame), fn _key, value, frame_value ->
        value || frame_value
      end)
      |> put_data_management()
      |> drop_nil_values()
    end)
  end

  defp frame_rows(%Frame{}), do: []

  defp event_target(frame) do
    cond do
      source_health_event_frame?(frame) -> :source_health_event
      telemetry_backfill_lifecycle_event_frame?(frame) -> :telemetry_backfill_lifecycle_event
      telemetry_revision_decision_event_frame?(frame) -> :telemetry_revision_decision_event
      source_watermark_event_frame?(frame) -> :source_watermark_event
      source_capability_posture_event_frame?(frame) -> :operational_event
      true -> :mission_event
    end
  end

  defp event_target_id(
         :operational_event,
         _mission_event_id,
         _source_record_id,
         operational_event_id
       ),
       do: operational_event_id

  defp event_target_id(_target, mission_event_id, source_record_id, _operational_event_id),
    do: mission_event_id || source_record_id

  defp event_links(frame, target, target_id) do
    frame
    |> WidgetLinks.data_links()
    |> Enum.filter(fn link ->
      link.target == target and (blank?(target_id) or link.target_id == target_id)
    end)
    |> WidgetLinks.filter_widget_links()
  end

  defp row_id(prefix, record_id, %DateTime{} = time, index) do
    [prefix, record_id, DateTime.to_unix(time, :millisecond), index]
    |> Enum.reject(&blank?/1)
    |> Enum.join(":")
  end

  defp row_id(prefix, record_id, _time, index) do
    [prefix, record_id, index]
    |> Enum.reject(&blank?/1)
    |> Enum.join(":")
  end

  defp sort_key(%{occurred_at: %DateTime{} = occurred_at} = row) do
    {DateTime.to_unix(occurred_at, :microsecond), Map.get(row, :row_id, "")}
  end

  defp sort_key(row), do: {0, Map.get(row, :row_id, "")}

  defp frame_family(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :family, Map.get(meta, "family"))
  end

  defp frame_family(%Frame{}), do: nil

  defp frame_stale?(%Frame{meta: meta}) when is_map(meta) do
    meta
    |> Map.get(:warning_codes, Map.get(meta, "warning_codes", []))
    |> List.wrap()
    |> Enum.map(&warning_code_atom/1)
    |> Enum.any?(&(&1 in @stale_warning_codes))
  end

  defp frame_stale?(%Frame{}), do: false

  defp source_health_event_frame?(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :family, Map.get(meta, "family")) in [:source_health, "source_health"]
  end

  defp source_health_event_frame?(%Frame{}), do: false

  defp source_watermark_event_frame?(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :family, Map.get(meta, "family")) in [:source_watermark, "source_watermark"]
  end

  defp source_watermark_event_frame?(%Frame{}), do: false

  defp source_capability_posture_event_frame?(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :family, Map.get(meta, "family")) in [
      :source_capability,
      "source_capability"
    ]
  end

  defp source_capability_posture_event_frame?(%Frame{}), do: false

  defp telemetry_backfill_lifecycle_event_frame?(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :family, Map.get(meta, "family")) in [
      :telemetry_backfill,
      "telemetry_backfill"
    ]
  end

  defp telemetry_backfill_lifecycle_event_frame?(%Frame{}), do: false

  defp telemetry_revision_decision_event_frame?(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :family, Map.get(meta, "family")) in [
      :telemetry_revision,
      "telemetry_revision"
    ]
  end

  defp telemetry_revision_decision_event_frame?(%Frame{}), do: false

  defp field_values(fields, field_name) do
    case field_by_name(fields, field_name) do
      %{values: values} when is_list(values) -> values
      _missing -> []
    end
  end

  defp field_by_name(fields, name), do: Enum.find(fields, &(&1.name == name))

  defp frame_source_context(%Frame{meta: meta}) when is_map(meta) do
    %{
      source_request_id: context_value(meta, :source_request_id),
      logical_source: context_value(meta, :logical_source),
      realm: context_value(meta, :realm),
      data_source_id: context_value(meta, :data_source_id),
      source_binding_id: context_value(meta, :source_binding_id),
      replay_run_id: context_value(meta, :replay_run_id),
      dataset: context_value(meta, :dataset)
    }
    |> drop_nil_values()
  end

  defp frame_source_context(%Frame{}), do: %{}

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

  defp put_data_management(row) do
    Map.put(row, :data_management, DataManagementPresentation.event_row(row))
  end

  defp warning_code_atom(code) when is_atom(code), do: code

  defp warning_code_atom(code) when is_binary(code) do
    String.to_existing_atom(code)
  rescue
    ArgumentError -> nil
  end

  defp warning_code_atom(_code), do: nil

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
