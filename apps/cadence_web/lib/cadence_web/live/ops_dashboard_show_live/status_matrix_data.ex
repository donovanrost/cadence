defmodule CadenceWeb.OpsDashboardShowLive.StatusMatrixData do
  @moduledoc false

  alias Cadence.Dashboards.{Frame, PlacementFrames, ScopeContext}

  alias CadenceWeb.OpsDashboardShowLive.{
    DataManagementPresentation,
    WidgetLifecyclePresentation,
    WidgetLinks
  }

  @stale_warning_codes [
    :watermark_unknown,
    :stale_data,
    :missing_snapshot,
    :unknown_watermark,
    :source_degraded
  ]

  @data_table_fields [
    :observable_id,
    :frame_observable_id,
    :label,
    :source,
    :status_policy,
    :product_family,
    :supported_capability,
    :source_request_id,
    :logical_source,
    :realm,
    :data_source_id,
    :source_binding_id,
    :replay_run_id,
    :dataset,
    :query_scope_kind,
    :query_scope_id,
    :query_scope_ids,
    :spacecraft_id,
    :resource_id,
    :scope_kind,
    :transport_id,
    :source_endpoint_id,
    :ground_station_id,
    :link_id,
    :contact_id,
    :value,
    :unit,
    :sample_id,
    :receipt_time,
    :quality_state,
    :normalized_state,
    :limit_state,
    :violation?,
    :links,
    :data_management,
    :stale?
  ]

  @spec rows(PlacementFrames.t()) :: [map()]
  def rows(%PlacementFrames{primary: frames} = placement_frames) when is_list(frames) do
    limit_overlays = limit_overlays_by_observable(placement_frames)

    Enum.flat_map(frames, &row(&1, limit_overlays))
  end

  @spec data_table_rows([map()]) :: [map()]
  def data_table_rows(rows) when is_list(rows), do: Enum.map(rows, &data_table_row/1)

  defp data_table_row(row) when is_map(row) do
    row
    |> Map.take(@data_table_fields)
    |> Map.put_new(:unit, nil)
    |> Map.put_new(:links, [])
  end

  defp row(%Frame{source: :telemetry, shape: :scalar} = telemetry_frame, limits) do
    with %{time: time, value: value, sample_id: sample_id, quality_state: quality_state} <-
           telemetry_scalar_data(telemetry_frame),
         observable_id when is_binary(observable_id) <- observable_id(telemetry_frame) do
      limit = Map.get(limits, observable_id)

      [
        %{
          observable_id: observable_id,
          label: observable_id,
          source: :telemetry,
          status_policy: :limit_state,
          spacecraft_id: spacecraft_id(telemetry_frame.scope),
          value: value,
          sample_id: sample_id,
          receipt_time: time,
          quality_state: quality_state || :good,
          normalized_state: limit && limit.normalized_state,
          limit_state: limit && limit.limit_state,
          violation?: (limit && limit.violation?) || false,
          links:
            WidgetLinks.widget_data_links(telemetry_frame, nil) ++ WidgetLinks.limit_links(limit),
          data_management: DataManagementPresentation.frame(telemetry_frame),
          stale?: frame_stale?(telemetry_frame)
        }
        |> Map.merge(frame_query_scope_context(telemetry_frame))
        |> Map.merge(telemetry_source_context(telemetry_frame, observable_id))
      ]
    else
      _missing -> []
    end
  end

  defp row(
         %Frame{source: :operational_observables, shape: :matrix, fields: fields} = frame,
         _limits
       ) do
    cond do
      field_values(fields, "phase") != [] ->
        contact_phase_rows(frame, fields)

      field_values(fields, "connection_state") != [] ->
        connection_state_rows(frame, fields)

      operational_state_values(fields) != [] ->
        operational_state_rows(frame, fields)

      field_values(fields, "value") != [] and field_values(fields, "unit") != [] ->
        metric_rows(frame, fields)

      true ->
        []
    end
  end

  defp row(%Frame{}, _limits), do: []

  defp contact_phase_rows(frame, fields) do
    observable_ids = field_values(fields, "observable_id")
    contact_ids = field_values(fields, "contact_id")
    contact_kinds = field_values(fields, "contact_kind")
    phases = field_values(fields, "phase")
    observed_at = field_values(fields, "observed_at")
    freshness_states = field_values(fields, "freshness_state")
    ages_ms = field_values(fields, "age_ms")
    links = WidgetLinks.data_links(frame)

    phases
    |> Enum.with_index()
    |> Enum.map(fn {phase, index} ->
      observable_id = Enum.at(observable_ids, index) || observable_id(frame)
      contact_id = Enum.at(contact_ids, index)
      contact_kind = Enum.at(contact_kinds, index)
      observed_time = Enum.at(observed_at, index)
      freshness_state = Enum.at(freshness_states, index)

      %{
        observable_id: operational_row_id(observable_id, contact_id, index),
        frame_observable_id: observable_id,
        label: operational_label(observable_id, contact_id, contact_kind),
        source: :operational_observables,
        status_policy: :contact_phase,
        contact_id: contact_id,
        contact_kind: contact_kind,
        phase: phase,
        spacecraft_id: nil,
        value: phase,
        sample_id: contact_id,
        receipt_time: observed_time,
        quality_state: contact_kind,
        normalized_state: phase,
        limit_state: nil,
        violation?: false,
        freshness_state: freshness_state,
        age_ms: Enum.at(ages_ms, index),
        links: operational_links(links, contact_id),
        data_management: DataManagementPresentation.frame(frame),
        stale?: frame_stale?(frame) or stale_freshness_state?(freshness_state)
      }
      |> Map.merge(operational_source_context(frame, observable_id, :contacts_phase))
    end)
  end

  defp connection_state_rows(frame, fields) do
    observable_ids = field_values(fields, "observable_id")
    resource_ids = field_values(fields, "resource_id")
    labels = field_values(fields, "label")
    scope_kinds = field_values(fields, "scope_kind")
    link_ids = field_values(fields, "link_id")
    contact_ids = field_values(fields, "contact_id")
    transport_ids = field_values(fields, "transport_id")
    source_endpoint_ids = field_values(fields, "source_endpoint_id")
    ground_station_ids = field_values(fields, "ground_station_id")
    adapter_keys = field_values(fields, "adapter_key")
    connection_states = field_values(fields, "connection_state")
    observed_at = field_values(fields, "observed_at")
    freshness_states = field_values(fields, "freshness_state")
    ages_ms = field_values(fields, "age_ms")
    links = WidgetLinks.data_links(frame)

    connection_states
    |> Enum.with_index()
    |> Enum.map(fn {connection_state, index} ->
      observable_id = Enum.at(observable_ids, index) || observable_id(frame)
      resource_id = Enum.at(resource_ids, index)
      label = Enum.at(labels, index) || resource_id || observable_id
      adapter_key = Enum.at(adapter_keys, index)
      freshness_state = Enum.at(freshness_states, index)

      row = %{
        observable_id: operational_row_id(observable_id, resource_id, index),
        frame_observable_id: observable_id,
        label: label,
        source: :operational_observables,
        status_policy: :connection_state,
        resource_id: resource_id,
        scope_kind: Enum.at(scope_kinds, index),
        link_id: Enum.at(link_ids, index),
        contact_id: Enum.at(contact_ids, index),
        transport_id: Enum.at(transport_ids, index),
        source_endpoint_id: Enum.at(source_endpoint_ids, index),
        ground_station_id: Enum.at(ground_station_ids, index),
        connection_state: connection_state,
        adapter_key: adapter_key,
        spacecraft_id: nil,
        value: connection_state,
        sample_id: resource_id,
        receipt_time: Enum.at(observed_at, index),
        quality_state: adapter_key,
        normalized_state: connection_state,
        limit_state: nil,
        violation?: false,
        freshness_state: freshness_state,
        age_ms: Enum.at(ages_ms, index),
        links: [],
        data_management: DataManagementPresentation.frame(frame),
        stale?: frame_stale?(frame) or stale_freshness_state?(freshness_state)
      }

      row = %{row | links: operational_resource_links(links, row)}

      row
      |> Map.merge(operational_source_context(frame, observable_id, :connection_state))
    end)
  end

  defp operational_state_rows(frame, fields) do
    observable_ids = field_values(fields, "observable_id")
    resource_ids = field_values(fields, "resource_id")
    labels = field_values(fields, "label")
    scope_kinds = field_values(fields, "scope_kind")
    link_ids = field_values(fields, "link_id")
    transport_ids = field_values(fields, "transport_id")
    source_endpoint_ids = field_values(fields, "source_endpoint_id")
    ground_station_ids = field_values(fields, "ground_station_id")
    adapter_keys = field_values(fields, "adapter_key")
    states = operational_state_values(fields)
    normalized_states = field_values(fields, "normalized_state")
    observed_at = field_values(fields, "observed_at")
    freshness_states = field_values(fields, "freshness_state")
    ages_ms = field_values(fields, "age_ms")
    links = WidgetLinks.data_links(frame)

    states
    |> Enum.with_index()
    |> Enum.map(fn {state, index} ->
      observable_id = Enum.at(observable_ids, index) || observable_id(frame)
      resource_id = Enum.at(resource_ids, index)
      label = Enum.at(labels, index) || resource_id || observable_id
      adapter_key = Enum.at(adapter_keys, index)
      freshness_state = Enum.at(freshness_states, index)
      product_family = operational_state_product_family(frame)

      row = %{
        observable_id: operational_row_id(observable_id, resource_id, index),
        frame_observable_id: observable_id,
        label: label,
        source: :operational_observables,
        status_policy: operational_state_status_policy(frame),
        resource_id: resource_id,
        scope_kind: Enum.at(scope_kinds, index),
        link_id: Enum.at(link_ids, index),
        transport_id: Enum.at(transport_ids, index),
        source_endpoint_id: Enum.at(source_endpoint_ids, index),
        ground_station_id: Enum.at(ground_station_ids, index),
        adapter_key: adapter_key,
        spacecraft_id: nil,
        value: state,
        sample_id: resource_id,
        receipt_time: Enum.at(observed_at, index),
        quality_state: adapter_key,
        normalized_state: Enum.at(normalized_states, index) || state,
        limit_state: nil,
        violation?: false,
        freshness_state: freshness_state,
        age_ms: Enum.at(ages_ms, index),
        links: [],
        data_management: DataManagementPresentation.frame(frame),
        stale?: frame_stale?(frame) or stale_freshness_state?(freshness_state)
      }

      row = %{row | links: operational_resource_links(links, row)}

      row
      |> Map.merge(operational_source_context(frame, observable_id, product_family))
    end)
  end

  defp metric_rows(frame, fields) do
    observable_ids = field_values(fields, "observable_id")
    resource_ids = field_values(fields, "resource_id")
    labels = field_values(fields, "label")
    scope_kinds = field_values(fields, "scope_kind")
    link_ids = field_values(fields, "link_id")
    transport_ids = field_values(fields, "transport_id")
    source_endpoint_ids = field_values(fields, "source_endpoint_id")
    ground_station_ids = field_values(fields, "ground_station_id")
    contact_ids = field_values(fields, "contact_id")
    spacecraft_ids = field_values(fields, "spacecraft_id")
    adapter_keys = field_values(fields, "adapter_key")
    values = field_values(fields, "value")
    units = field_values(fields, "unit")
    observed_at = field_values(fields, "observed_at")
    freshness_states = field_values(fields, "freshness_state")
    ages_ms = field_values(fields, "age_ms")
    links = WidgetLinks.data_links(frame)

    values
    |> Enum.with_index()
    |> Enum.map(fn {value, index} ->
      observable_id = Enum.at(observable_ids, index) || observable_id(frame)
      resource_id = Enum.at(resource_ids, index)
      label = Enum.at(labels, index) || resource_id || observable_id
      adapter_key = Enum.at(adapter_keys, index)
      observed_time = Enum.at(observed_at, index)
      freshness_state = Enum.at(freshness_states, index)
      product_family = operational_metric_product_family(frame)

      row = %{
        observable_id: operational_row_id(observable_id, resource_id, index),
        frame_observable_id: observable_id,
        label: label,
        source: :operational_observables,
        status_policy: :metric_value,
        resource_id: resource_id,
        scope_kind: Enum.at(scope_kinds, index),
        link_id: Enum.at(link_ids, index),
        transport_id: Enum.at(transport_ids, index),
        source_endpoint_id: Enum.at(source_endpoint_ids, index),
        ground_station_id: Enum.at(ground_station_ids, index),
        contact_id: Enum.at(contact_ids, index),
        spacecraft_id: Enum.at(spacecraft_ids, index),
        adapter_key: adapter_key,
        unit: Enum.at(units, index),
        freshness_state: freshness_state,
        age_ms: Enum.at(ages_ms, index),
        value: value,
        sample_id: resource_id,
        receipt_time: observed_time,
        quality_state: metric_quality_state(value, observed_time),
        normalized_state: metric_normalized_state(value, observed_time),
        limit_state: nil,
        violation?: false,
        links: [],
        data_management: DataManagementPresentation.frame(frame),
        stale?: frame_stale?(frame) or stale_freshness_state?(freshness_state)
      }

      row = %{row | links: operational_resource_links(links, row)}

      row
      |> Map.merge(operational_source_context(frame, observable_id, product_family))
    end)
  end

  defp telemetry_scalar_data(%Frame{source: :telemetry, shape: :scalar, fields: fields}) do
    with %{values: [time | _]} <- field_by_name(fields, "time"),
         value_field when not is_nil(value_field) <- value_field(fields),
         [value | _] <- value_field.values do
      %{
        time: time,
        value: value,
        sample_id: value_field.metadata |> metadata_values(:sample_ids) |> List.first(),
        quality_state: value_field.metadata |> metadata_values(:quality_states) |> List.first()
      }
    else
      _missing -> nil
    end
  end

  defp telemetry_scalar_data(%Frame{}), do: nil

  defp operational_metric_product_family(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :product_family) || Map.get(meta, :supported_capability) || :metric_value
  end

  defp operational_metric_product_family(_frame), do: :metric_value

  defp operational_state_product_family(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :product_family) || Map.get(meta, :supported_capability) || :operational_state
  end

  defp operational_state_product_family(_frame), do: :operational_state

  defp operational_state_status_policy(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :state_color_policy) || Map.get(meta, :status_policy) || :operational_state
  end

  defp operational_state_status_policy(_frame), do: :operational_state

  defp telemetry_source_context(frame, observable_id) do
    meta = frame.meta || %{}

    %{
      frame_observable_id: observable_id,
      product_family: Map.get(meta, :supported_capability) || :latest_value,
      supported_capability: Map.get(meta, :supported_capability),
      source_request_id: Map.get(meta, :source_request_id),
      logical_source: Map.get(meta, :logical_source),
      realm: Map.get(meta, :realm),
      data_source_id: Map.get(meta, :data_source_id),
      source_binding_id: Map.get(meta, :source_binding_id),
      replay_run_id: Map.get(meta, :replay_run_id),
      dataset: Map.get(meta, :dataset)
    }
    |> drop_nil_values()
  end

  defp operational_source_context(frame, observable_id, product_family) do
    meta = frame.meta || %{}

    %{
      frame_observable_id: observable_id,
      product_family: product_family,
      supported_capability: Map.get(meta, :supported_capability),
      source_request_id: Map.get(meta, :source_request_id),
      logical_source: Map.get(meta, :logical_source),
      realm: Map.get(meta, :realm),
      data_source_id: Map.get(meta, :data_source_id),
      source_binding_id: Map.get(meta, :source_binding_id),
      replay_run_id: Map.get(meta, :replay_run_id),
      dataset: Map.get(meta, :dataset)
    }
    |> Map.merge(frame_query_scope_context(frame))
    |> drop_nil_values()
  end

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

  defp limit_overlays_by_observable(%PlacementFrames{overlays: %{limits: limit_frames}})
       when is_list(limit_frames) do
    limit_frames
    |> Enum.flat_map(fn frame ->
      case limit_overlay_frame_data(frame) do
        nil -> []
        data -> [{data.observable_id, data}]
      end
    end)
    |> Map.new()
  end

  defp limit_overlays_by_observable(%PlacementFrames{}), do: %{}

  defp limit_overlay_frame_data(%Frame{source: :limits, shape: :scalar} = frame) do
    with observable_id when is_binary(observable_id) <- observable_id(frame),
         %{values: [normalized_state | _]} <- field_by_name(frame.fields, "normalized_state"),
         %{values: [limit_state | _]} <- field_by_name(frame.fields, "limit_state") do
      %{
        observable_id: observable_id,
        normalized_state: normalized_state,
        limit_state: limit_state,
        violation?: field_values(frame.fields, "violation") |> List.first() |> truthy?(),
        limit_event_id: Map.get(frame.meta, :limit_event_id),
        links: WidgetLinks.data_links(frame)
      }
    else
      _missing -> nil
    end
  end

  defp limit_overlay_frame_data(%Frame{}), do: nil

  defp value_field(fields) do
    Enum.find(fields, &representative_value_field?/1) ||
      Enum.find(fields, &(&1.kind in [:number, :enum, :boolean]))
  end

  defp representative_value_field?(field), do: field.name not in ["time", "receipt_time"]

  defp metadata_values(metadata, key) when is_map(metadata) do
    case Map.get(metadata, key) || Map.get(metadata, Atom.to_string(key)) do
      values when is_list(values) -> values
      nil -> []
      value -> [value]
    end
  end

  defp metadata_values(_metadata, _key), do: []

  defp metric_quality_state(nil, _observed_at), do: :no_data
  defp metric_quality_state(_value, nil), do: :no_data
  defp metric_quality_state(_value, _observed_at), do: :observed

  defp metric_normalized_state(nil, _observed_at), do: :no_data
  defp metric_normalized_state(_value, nil), do: :no_data
  defp metric_normalized_state(_value, _observed_at), do: :observed

  defp operational_state_values(fields) do
    case field_values(fields, "state") do
      [] ->
        if field_values(fields, "value") == [] do
          field_values(fields, "normalized_state")
        else
          []
        end

      states ->
        states
    end
  end

  defp stale_freshness_state?(state), do: state in [:stale, "stale", :unknown, "unknown"]

  defp operational_row_id(observable_id, resource_id, index) do
    [observable_id, resource_id || Integer.to_string(index)]
    |> Enum.reject(&blank?/1)
    |> Enum.join(":")
  end

  defp operational_label(observable_id, contact_id, contact_kind) do
    [observable_id, contact_kind, contact_id]
    |> Enum.reject(&blank?/1)
    |> Enum.map_join(" / ", &to_string/1)
  end

  defp operational_links(links, contact_id) do
    links
    |> Enum.filter(&(&1.target == :contact and &1.target_id == contact_id))
    |> WidgetLinks.filter_widget_links()
  end

  defp operational_resource_links(links, row) do
    row_targets = [
      {:link, Map.get(row, :link_id)},
      {:transport, Map.get(row, :transport_id)},
      {:source_endpoint, Map.get(row, :source_endpoint_id)},
      {:ground_station, Map.get(row, :ground_station_id)},
      {:contact, Map.get(row, :contact_id)}
    ]

    links
    |> Enum.filter(fn link ->
      Enum.any?(row_targets, fn {target, target_id} ->
        target_id not in [nil, ""] and link.target == target and link.target_id == target_id
      end)
    end)
    |> WidgetLinks.filter_widget_links()
  end

  defp frame_stale?(%Frame{meta: meta}) when is_map(meta) do
    meta
    |> Map.get(:warning_codes, Map.get(meta, "warning_codes", []))
    |> List.wrap()
    |> Enum.map(&WidgetLifecyclePresentation.normalize_warning_code/1)
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

  defp spacecraft_id(%{primary: %{ids: [spacecraft_id | _rest]}}), do: spacecraft_id
  defp spacecraft_id(%{"primary" => %{"ids" => [spacecraft_id | _rest]}}), do: spacecraft_id
  defp spacecraft_id(_scope), do: nil

  defp drop_nil_values(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp drop_empty_scope_values(map) do
    Map.reject(map, fn
      {_key, []} -> true
      {_key, value} -> is_nil(value)
    end)
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_value), do: false
end
