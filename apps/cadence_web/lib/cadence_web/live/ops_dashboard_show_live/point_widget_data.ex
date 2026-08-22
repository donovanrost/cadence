defmodule CadenceWeb.OpsDashboardShowLive.PointWidgetData do
  @moduledoc """
  Presenter for point-shaped widget data.

  Value tiles and time-series source-failure fallbacks share the same point
  lifecycle shape, so this module owns that contract directly.
  """

  alias Cadence.Dashboards.{Frame, PlacementFrames, ScopeContext}

  alias CadenceWeb.OpsDashboardShowLive.{
    ContextScopePolicy,
    DataManagementPresentation,
    TimeSeriesData,
    WidgetLifecyclePresentation,
    WidgetLinks
  }

  @spec data(PlacementFrames.t()) :: map()
  def data(
        %PlacementFrames{primary: [%Frame{source: :telemetry} = telemetry_frame | _]} =
          placement_frames
      ) do
    case telemetry_scalar_data(telemetry_frame) do
      %{time: time, value: value, sample_id: sample_id, quality_state: quality_state} ->
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
          limit_event: limit_overlay_data(placement_frames),
          links: WidgetLinks.widget_data_links(telemetry_frame, placement_frames),
          data_management: DataManagementPresentation.frame(telemetry_frame),
          stale?: :watermark_unknown in List.wrap(telemetry_frame.meta.warning_codes),
          unresolved?: false,
          engine_backed?: true
        }
        |> Map.merge(frame_source_context(telemetry_frame))
        |> WidgetLifecyclePresentation.put(
          placement_frames,
          telemetry_frame,
          :ready,
          :watermark_unknown in List.wrap(telemetry_frame.meta.warning_codes)
        )

      _missing ->
        empty_data(placement_frames)
    end
  end

  def data(
        %PlacementFrames{
          primary: [
            %Frame{source: :operational_observables, shape: :matrix} = operational_frame | _
          ]
        } = placement_frames
      ) do
    case operational_metric_data(operational_frame) do
      %{value: value, observed_at: %DateTime{} = observed_at} = metric when not is_nil(value) ->
        %{
          kind: :point,
          spacecraft_id: nil,
          sample: %{
            sample_id: metric.sample_id,
            raw_value: value,
            engineering_value: value,
            receipt_time: observed_at,
            generation_time: observed_at,
            quality_state: metric.quality_state
          },
          unit: metric.unit,
          label: metric.label,
          limit_event: nil,
          links: WidgetLinks.widget_data_links(operational_frame, placement_frames),
          data_management: DataManagementPresentation.frame(operational_frame),
          stale?:
            :watermark_unknown in List.wrap(Map.get(operational_frame.meta, :warning_codes)),
          unresolved?: false,
          engine_backed?: true
        }
        |> Map.merge(frame_source_context(operational_frame))
        |> WidgetLifecyclePresentation.put(
          placement_frames,
          operational_frame,
          :ready,
          :watermark_unknown in List.wrap(Map.get(operational_frame.meta, :warning_codes))
        )

      %{unit: unit, label: label} ->
        %{
          kind: :point,
          spacecraft_id: nil,
          sample: nil,
          unit: unit,
          label: label,
          limit_event: nil,
          links: WidgetLinks.widget_data_links(operational_frame, placement_frames),
          data_management: DataManagementPresentation.frame(operational_frame),
          stale?:
            :watermark_unknown in List.wrap(Map.get(operational_frame.meta, :warning_codes)),
          unresolved?: false,
          engine_backed?: true
        }
        |> Map.merge(frame_source_context(operational_frame))
        |> WidgetLifecyclePresentation.put(
          placement_frames,
          operational_frame,
          :no_data,
          :watermark_unknown in List.wrap(Map.get(operational_frame.meta, :warning_codes))
        )

      _missing ->
        empty_data(placement_frames)
    end
  end

  def data(%PlacementFrames{} = placement_frames), do: empty_data(placement_frames)

  @spec context_data(PlacementFrames.t()) :: map()
  def context_data(%PlacementFrames{} = placement_frames) do
    if ContextScopePolicy.resolved?(placement_frames),
      do: data(placement_frames),
      else: source_failure_data(placement_frames) || unresolved_data()
  end

  @spec source_failure_data(PlacementFrames.t()) :: map() | nil
  def source_failure_data(%PlacementFrames{} = placement_frames) do
    data = empty_data(placement_frames)

    case WidgetLifecyclePresentation.state(data.lifecycle) do
      state when state in [:error, :unsupported, :retention_gap] -> data
      _state -> nil
    end
  end

  @spec unresolved_data() :: map()
  def unresolved_data do
    %{
      kind: :point,
      spacecraft_id: nil,
      sample: nil,
      limit_event: nil,
      links: [],
      stale?: false,
      unresolved?: true,
      lifecycle: WidgetLifecyclePresentation.classify(data_state: :no_data),
      lifecycle_state: :no_data
    }
  end

  defp empty_data(%PlacementFrames{} = placement_frames) do
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
      :no_data,
      false
    )
  end

  defp telemetry_scalar_data(%Frame{source: :telemetry, shape: :scalar} = frame),
    do: TimeSeriesData.scalar_data(frame)

  defp telemetry_scalar_data(%Frame{}), do: nil

  defp operational_metric_data(%Frame{
         source: :operational_observables,
         shape: :matrix,
         fields: fields
       }) do
    values = field_values(fields, "value")
    observed_at = field_values(fields, "observed_at")
    units = field_values(fields, "unit")
    labels = field_values(fields, "label")
    resource_ids = field_values(fields, "resource_id")

    case values do
      [value | _rest] ->
        %{
          value: value,
          observed_at: List.first(observed_at),
          unit: List.first(units),
          label: List.first(labels),
          sample_id: List.first(resource_ids),
          quality_state: metric_quality_state(value, List.first(observed_at))
        }

      [] ->
        nil
    end
  end

  defp operational_metric_data(%Frame{}), do: nil

  defp frame_source_context(%Frame{} = frame) do
    source_request_context = context_value(frame.meta, :source_request_context) || %{}

    %{
      frame_observable_id: first_context_value([{frame.meta, :observable_id}]),
      source_request_id:
        first_context_value([
          {frame.meta, :source_request_id},
          {source_request_context, :source_request_id}
        ]),
      logical_source:
        first_context_value([
          {frame.meta, :logical_source},
          {source_request_context, :logical_source}
        ]),
      realm:
        first_context_value([
          {frame.meta, :realm},
          {frame.meta, :requested_realm},
          {source_request_context, :realm},
          {source_request_context, :requested_realm}
        ]),
      data_source_id:
        first_context_value([
          {frame.meta, :data_source_id},
          {frame.meta, :requested_data_source_id},
          {source_request_context, :data_source_id},
          {source_request_context, :requested_data_source_id}
        ]),
      source_binding_id:
        first_context_value([
          {frame.meta, :source_binding_id},
          {frame.meta, :requested_source_binding_id},
          {source_request_context, :source_binding_id},
          {source_request_context, :requested_source_binding_id}
        ]),
      dataset:
        first_context_value([
          {frame.meta, :dataset},
          {frame.meta, :requested_dataset},
          {source_request_context, :dataset},
          {source_request_context, :requested_dataset}
        ]),
      replay_run_id:
        first_context_value([
          {frame.meta, :replay_run_id},
          {source_request_context, :replay_run_id}
        ])
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
    |> Map.merge(frame_query_scope_context(frame))
  end

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

  defp first_context_value(context_keys) do
    Enum.find_value(context_keys, fn {context, key} ->
      case context_value(context, key) do
        value when value in [nil, ""] -> nil
        value -> value
      end
    end)
  end

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

  defp metric_quality_state(nil, _observed_at), do: :no_data
  defp metric_quality_state(_value, nil), do: :no_data
  defp metric_quality_state(_value, _observed_at), do: :observed

  defp limit_overlay_data(%PlacementFrames{overlays: %{limits: [%Frame{} = limit_frame | _]}}) do
    with %{values: [normalized_state | _]} <-
           field_by_name(limit_frame.fields, "normalized_state"),
         %{values: [limit_state | _]} <- field_by_name(limit_frame.fields, "limit_state") do
      %{
        normalized_state: normalized_state,
        limit_state: limit_state,
        limit_event_id: Map.get(limit_frame.meta, :limit_event_id),
        links: WidgetLinks.data_links(limit_frame)
      }
    else
      _missing -> nil
    end
  end

  defp limit_overlay_data(%PlacementFrames{}), do: nil

  defp field_values(fields, field_name) do
    case field_by_name(fields, field_name) do
      %{values: values} when is_list(values) -> values
      _missing -> []
    end
  end

  defp field_by_name(fields, name), do: Enum.find(fields, &(&1.name == name))

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
end
