defmodule CadenceWeb.OpsDashboardShowLive.StateTimelineData do
  @moduledoc false

  alias Cadence.Dashboards.{Frame, PlacementFrames, ScopeContext}
  alias CadenceWeb.OpsDashboardShowLive.DataManagementPresentation
  alias CadenceWeb.OpsDashboardShowLive.WidgetLinks

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
    |> Enum.sort_by(&sort_key/1)
    |> close_segments()
  end

  @spec lanes([map()]) :: [map()]
  def lanes(rows) when is_list(rows) do
    Enum.reduce(rows, [], &put_lane/2)
  end

  defp frame_rows(%Frame{source: :limits, shape: :events, fields: fields} = frame) do
    observable_id = observable_id(frame)
    times = field_values(fields, "time")
    limit_event_ids = field_values(fields, "limit_event_id")
    sample_ids = field_values(fields, "sample_id")
    limit_definition_ids = field_values(fields, "limit_definition_id")
    limit_definition_versions = field_values(fields, "limit_definition_version")
    normalized_states = field_values(fields, "normalized_state")
    limit_states = field_values(fields, "limit_state")
    violations = field_values(fields, "violation")

    times
    |> Enum.with_index()
    |> Enum.map(fn {time, index} ->
      limit_event_id = Enum.at(limit_event_ids, index)
      sample_id = Enum.at(sample_ids, index)
      limit_definition_id = Enum.at(limit_definition_ids, index)

      row(
        %{
          observable_id: observable_id,
          starts_at: time,
          normalized_state: Enum.at(normalized_states, index),
          limit_state: Enum.at(limit_states, index),
          violation?: truthy?(Enum.at(violations, index)),
          limit_event_id: limit_event_id,
          sample_id: sample_id,
          limit_definition_id: limit_definition_id,
          limit_definition_version: Enum.at(limit_definition_versions, index),
          links:
            limit_links(
              frame,
              observable_id,
              limit_event_id,
              sample_id,
              limit_definition_id
            ),
          data_management: DataManagementPresentation.frame(frame),
          stale?: frame_stale?(frame),
          index: index
        }
        |> Map.merge(frame_source_context(frame))
        |> Map.merge(frame_query_scope_context(frame))
      )
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp frame_rows(%Frame{source: :limits, shape: :scalar, fields: fields} = frame) do
    observable_id = observable_id(frame)
    time = field_values(fields, "time") |> List.first()
    limit_event_id = context_value(frame.meta, :limit_event_id)
    sample_id = context_value(frame.meta, :sample_id)
    limit_definition_id = context_value(frame.meta, :limit_definition_id)

    [
      row(
        %{
          observable_id: observable_id,
          starts_at: time,
          normalized_state: field_values(fields, "normalized_state") |> List.first(),
          limit_state: field_values(fields, "limit_state") |> List.first(),
          violation?: field_values(fields, "violation") |> List.first() |> truthy?(),
          limit_event_id: limit_event_id,
          sample_id: sample_id,
          limit_definition_id: limit_definition_id,
          limit_definition_version: context_value(frame.meta, :limit_definition_version),
          links:
            limit_links(
              frame,
              observable_id,
              limit_event_id,
              sample_id,
              limit_definition_id
            ),
          data_management: DataManagementPresentation.frame(frame),
          stale?: frame_stale?(frame),
          index: 0
        }
        |> Map.merge(frame_source_context(frame))
        |> Map.merge(frame_query_scope_context(frame))
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp frame_rows(
         %Frame{
           source: :operational_observables,
           shape: :events,
           fields: fields
         } = frame
       ) do
    times = field_values(fields, "time")
    ends_at_values = field_values(fields, "ends_at")
    observable_ids = field_values(fields, "observable_id")
    resource_ids = field_values(fields, "resource_id")
    lane_ids = field_values(fields, "lane_id")
    labels = field_values(fields, "label")
    scope_kinds = field_values(fields, "scope_kind")
    link_ids = field_values(fields, "link_id")
    contact_ids = field_values(fields, "contact_id")
    contact_kinds = field_values(fields, "contact_kind")
    transport_ids = field_values(fields, "transport_id")
    source_endpoint_ids = field_values(fields, "source_endpoint_id")
    ground_station_ids = field_values(fields, "ground_station_id")
    adapter_keys = field_values(fields, "adapter_key")
    phases = field_values(fields, "phase")
    connection_states = field_values(fields, "connection_state")
    states = field_values(fields, "state")
    normalized_states = field_values(fields, "normalized_state")
    source_event_ids = field_values(fields, "source_event_id")

    status_policy = operational_status_policy(fields)

    times
    |> Enum.with_index()
    |> Enum.map(fn {time, index} ->
      contact_id = Enum.at(contact_ids, index)
      observable_id = Enum.at(observable_ids, index) || observable_id(frame)
      resource_id = Enum.at(resource_ids, index)

      attrs =
        %{
          observable_id: observable_id,
          source: :operational_observables,
          status_policy: status_policy,
          starts_at: time,
          ends_at: Enum.at(ends_at_values, index),
          normalized_state:
            Enum.at(normalized_states, index) || Enum.at(phases, index) ||
              Enum.at(connection_states, index) || Enum.at(states, index),
          label: Enum.at(labels, index),
          lane_id: Enum.at(lane_ids, index),
          lane_label: Enum.at(lane_ids, index) || resource_id || observable_id,
          resource_id: resource_id,
          scope_kind: Enum.at(scope_kinds, index),
          link_id: Enum.at(link_ids, index),
          contact_id: contact_id,
          contact_kind: Enum.at(contact_kinds, index),
          transport_id: Enum.at(transport_ids, index),
          source_endpoint_id: Enum.at(source_endpoint_ids, index),
          ground_station_id: Enum.at(ground_station_ids, index),
          adapter_key: Enum.at(adapter_keys, index),
          source_event_id: Enum.at(source_event_ids, index),
          sample_id: contact_id || resource_id,
          data_management: DataManagementPresentation.frame(frame),
          stale?: frame_stale?(frame),
          index: index
        }
        |> Map.merge(frame_source_context(frame))
        |> Map.merge(frame_query_scope_context(frame))

      attrs
      |> Map.put(:links, operational_links(frame, attrs))
      |> row()
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp frame_rows(%Frame{}), do: []

  defp row(%{starts_at: %DateTime{}, normalized_state: state} = attrs)
       when not is_nil(state) do
    observable_id = Map.get(attrs, :observable_id)
    starts_at = Map.fetch!(attrs, :starts_at)
    index = Map.get(attrs, :index, 0)

    %{
      row_id: row_id(observable_id, starts_at, index),
      observable_id: observable_id,
      label: Map.get(attrs, :label),
      source: Map.get(attrs, :source, :limits),
      status_policy: Map.get(attrs, :status_policy, :limit_state),
      lane_key: lane_key(attrs),
      lane_label: Map.get(attrs, :lane_label) || lane_label(attrs),
      starts_at: starts_at,
      ends_at: Map.get(attrs, :ends_at),
      normalized_state: state,
      limit_state: Map.get(attrs, :limit_state),
      violation?: Map.get(attrs, :violation?, false),
      resource_id: Map.get(attrs, :resource_id),
      lane_id: Map.get(attrs, :lane_id),
      scope_kind: Map.get(attrs, :scope_kind),
      link_id: Map.get(attrs, :link_id),
      contact_id: Map.get(attrs, :contact_id),
      contact_kind: Map.get(attrs, :contact_kind),
      transport_id: Map.get(attrs, :transport_id),
      source_endpoint_id: Map.get(attrs, :source_endpoint_id),
      ground_station_id: Map.get(attrs, :ground_station_id),
      adapter_key: Map.get(attrs, :adapter_key),
      source_event_id: Map.get(attrs, :source_event_id),
      limit_event_id: Map.get(attrs, :limit_event_id),
      sample_id: Map.get(attrs, :sample_id),
      limit_definition_id: Map.get(attrs, :limit_definition_id),
      limit_definition_version: Map.get(attrs, :limit_definition_version),
      source_request_id: Map.get(attrs, :source_request_id),
      logical_source: Map.get(attrs, :logical_source),
      realm: Map.get(attrs, :realm),
      data_source_id: Map.get(attrs, :data_source_id),
      source_binding_id: Map.get(attrs, :source_binding_id),
      replay_run_id: Map.get(attrs, :replay_run_id),
      dataset: Map.get(attrs, :dataset),
      query_scope_kind: Map.get(attrs, :query_scope_kind),
      query_scope_id: Map.get(attrs, :query_scope_id),
      query_scope_ids: Map.get(attrs, :query_scope_ids),
      links: Map.get(attrs, :links, []),
      data_management: Map.get(attrs, :data_management),
      stale?: Map.get(attrs, :stale?, false)
    }
    |> drop_nil_values()
  end

  defp row(_attrs), do: nil

  defp close_segments(rows) do
    rows
    |> Enum.group_by(&Map.get(&1, :lane_key))
    |> Enum.map(fn {_lane_key, lane_rows} ->
      sorted_lane_rows = Enum.sort_by(lane_rows, &sort_key/1)

      sorted_lane_rows
      |> Enum.with_index()
      |> Enum.map(fn {row, index} ->
        next_row = Enum.at(sorted_lane_rows, index + 1)

        Map.put(
          row,
          :ends_at,
          Map.get(row, :ends_at) || (next_row && Map.get(next_row, :starts_at))
        )
      end)
    end)
    |> Enum.sort_by(&lane_sort_key/1)
    |> List.flatten()
  end

  defp put_lane(row, lanes) do
    lane_key = Map.get(row, :lane_key)

    case Enum.find_index(lanes, &(&1.lane_key == lane_key)) do
      nil -> lanes ++ [lane(row, lane_key)]
      index -> List.update_at(lanes, index, &append_lane_row(&1, row))
    end
  end

  defp lane(row, lane_key) do
    %{
      lane_key: lane_key,
      label: Map.get(row, :lane_label) || lane_key,
      source: Map.get(row, :source),
      scope_kind: Map.get(row, :scope_kind),
      observable_id: Map.get(row, :observable_id),
      resource_id: Map.get(row, :resource_id),
      rows: [row]
    }
  end

  defp append_lane_row(lane, row) do
    %{lane | rows: lane.rows ++ [row]}
  end

  defp limit_links(frame, observable_id, limit_event_id, sample_id, limit_definition_id) do
    allowed_targets = [
      {:telemetry_point, observable_id},
      {:limit_event, limit_event_id},
      {:telemetry_sample, sample_id},
      {:limit_definition, limit_definition_id}
    ]

    frame
    |> WidgetLinks.data_links()
    |> Enum.filter(fn link ->
      Enum.any?(allowed_targets, fn {target, target_id} ->
        not blank?(target_id) and link.target == target and link.target_id == target_id
      end)
    end)
    |> WidgetLinks.filter_widget_links()
  end

  defp operational_links(frame, attrs) do
    contact_id = Map.get(attrs, :contact_id)

    row_targets = [
      {:contact, contact_id},
      {:transport, Map.get(attrs, :transport_id)},
      {:source_endpoint, Map.get(attrs, :source_endpoint_id)},
      {:ground_station, Map.get(attrs, :ground_station_id)},
      {:operational_event, Map.get(attrs, :source_event_id)}
    ]

    frame
    |> WidgetLinks.data_links()
    |> Enum.filter(fn link ->
      Enum.any?(row_targets, fn {target, target_id} ->
        not blank?(target_id) and link.target == target and link.target_id == target_id
      end)
    end)
    |> WidgetLinks.filter_widget_links()
  end

  defp operational_status_policy(fields) do
    cond do
      field_values(fields, "phase") != [] -> :contact_phase
      field_values(fields, "connection_state") != [] -> :connection_state
      true -> :operational_state
    end
  end

  defp row_id(observable_id, %DateTime{} = time, index) do
    ["state", observable_id, DateTime.to_unix(time, :millisecond), index]
    |> Enum.reject(&blank?/1)
    |> Enum.join(":")
  end

  defp lane_key(attrs) do
    [
      Map.get(attrs, :source, :limits),
      Map.get(attrs, :observable_id),
      Map.get(attrs, :lane_id) || Map.get(attrs, :resource_id) || Map.get(attrs, :contact_id) ||
        Map.get(attrs, :transport_id) || Map.get(attrs, :source_endpoint_id) ||
        Map.get(attrs, :ground_station_id)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.map_join(":", &to_string/1)
  end

  defp lane_label(attrs) do
    Map.get(attrs, :label) || Map.get(attrs, :resource_id) || Map.get(attrs, :contact_id) ||
      Map.get(attrs, :observable_id)
  end

  defp lane_sort_key([]), do: {0, ""}

  defp lane_sort_key([first | _rows]) do
    {time_sort, _row_id} = sort_key(first)
    {time_sort, Map.get(first, :lane_label, Map.get(first, :lane_key, ""))}
  end

  defp sort_key(%{starts_at: %DateTime{} = starts_at} = row) do
    {DateTime.to_unix(starts_at, :microsecond), Map.get(row, :row_id, "")}
  end

  defp sort_key(row), do: {0, Map.get(row, :row_id, "")}

  defp frame_stale?(%Frame{meta: meta}) when is_map(meta) do
    meta
    |> Map.get(:warning_codes, Map.get(meta, "warning_codes", []))
    |> List.wrap()
    |> Enum.map(&warning_code_atom/1)
    |> Enum.any?(&(&1 in @stale_warning_codes))
  end

  defp frame_stale?(%Frame{}), do: false

  defp field_values(fields, field_name) do
    case field_by_name(fields, field_name) do
      %{values: values} when is_list(values) -> values
      _missing -> []
    end
  end

  defp field_by_name(fields, name), do: Enum.find(fields, &(&1.name == name))

  defp observable_id(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :observable_id, Map.get(meta, "observable_id"))
  end

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

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

  defp frame_query_scope_context(%Frame{scope: scope}) when is_map(scope) do
    scope_kind = ScopeContext.primary_kind(scope)
    scope_ids = ScopeContext.primary_ids(scope)

    %{
      query_scope_kind: scope_kind && to_string(scope_kind),
      query_scope_id: List.first(scope_ids),
      query_scope_ids: scope_ids
    }
    |> drop_empty_scope_values()
  end

  defp frame_query_scope_context(%Frame{}), do: %{}

  defp drop_empty_scope_values(map) do
    Map.reject(map, fn
      {_key, []} -> true
      {_key, value} -> is_nil(value)
    end)
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

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_value), do: false
end
