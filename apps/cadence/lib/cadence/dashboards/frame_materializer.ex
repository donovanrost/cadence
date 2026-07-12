defmodule Cadence.Dashboards.FrameMaterializer do
  @moduledoc """
  Placement/display materialization boundary for dashboard source results.

  Source adapters return source-scoped frames. The materializer is the boundary
  where those frames become placement/role-specific output and where the frame
  cache key is assembled from display context.
  """

  alias Cadence.Dashboards.{
    DataContext,
    Frame,
    PlannedSourceRequest,
    ResolveWarning,
    RuntimeCacheKey,
    ScopeContext,
    SourceResult,
    SourceWatermark
  }

  @type materialized :: %{
          placement_id: binary(),
          request_id: binary(),
          role: atom(),
          frames: list(),
          warnings: [ResolveWarning.t()],
          frame_key: RuntimeCacheKey.t() | nil,
          capability_provenance: map() | nil
        }

  @spec materialize(PlannedSourceRequest.t(), SourceResult.t(), map(), keyword()) ::
          materialized()
  def materialize(
        %PlannedSourceRequest{} = request,
        %SourceResult{} = source_result,
        consumer,
        opts \\ []
      )
      when is_map(consumer) and is_list(opts) do
    source_result = SourceResult.normalize(source_result)
    placement_id = Map.fetch!(consumer, :placement_id)
    role = Map.get(consumer, :role, :primary)
    source_result_key = Keyword.get(opts, :source_result_key)
    capability_provenance = capability_provenance(request)

    source_watermarks = source_watermarks(source_result)
    source_request_time_context = source_request_time_context(request)
    source_request_context = source_request_context(request, source_request_time_context)

    %{
      placement_id: placement_id,
      request_id: request.request_id,
      role: role,
      frames:
        annotate_frames(
          source_result.frames,
          capability_provenance,
          source_watermarks,
          source_request_time_context,
          source_request_context
        ),
      warnings: placement_warnings(source_result.warnings, placement_id),
      frame_key: maybe_cache_key(request, source_result, consumer, source_result_key, opts),
      capability_provenance: capability_provenance
    }
  end

  @spec cache_key(
          PlannedSourceRequest.t(),
          SourceResult.t(),
          map(),
          RuntimeCacheKey.t(),
          keyword()
        ) ::
          RuntimeCacheKey.t()
  def cache_key(
        %PlannedSourceRequest{} = request,
        %SourceResult{} = source_result,
        consumer,
        %RuntimeCacheKey{layer: :source_result} = source_result_key,
        opts \\ []
      )
      when is_map(consumer) and is_list(opts) do
    source_result = SourceResult.normalize(source_result)

    RuntimeCacheKey.frame(source_result_key,
      placement_id: Map.fetch!(consumer, :placement_id),
      placement_size: Keyword.get(opts, :placement_size, %{}),
      display: Keyword.get(opts, :display, %{}),
      frame_shape: Keyword.get(opts, :frame_shape, frame_shape(source_result)),
      limit_context: Keyword.get(opts, :limit_context, request.limit_context),
      catalog_revision: Keyword.get(opts, :catalog_revision),
      telemetry_revision_dependency: telemetry_revision_dependency(source_result)
    )
  end

  defp maybe_cache_key(_request, _source_result, _consumer, nil, _opts), do: nil

  defp maybe_cache_key(
         request,
         source_result,
         consumer,
         %RuntimeCacheKey{} = source_result_key,
         opts
       ) do
    cache_key(request, source_result, consumer, source_result_key, opts)
  end

  defp frame_shape(%SourceResult{frames: [%{shape: shape} | _rest]}), do: shape
  defp frame_shape(%SourceResult{}), do: nil

  defp telemetry_revision_dependency(%SourceResult{meta: meta}) when is_map(meta) do
    Map.get(meta, :telemetry_revision_dependency)
  end

  defp telemetry_revision_dependency(%SourceResult{}), do: nil

  defp annotate_frames(
         frames,
         capability_provenance,
         source_watermarks,
         source_request_time_context,
         source_request_context
       ) do
    frames
    |> normalize_frames()
    |> Enum.map(fn
      %Frame{} = frame ->
        %Frame{
          frame
          | meta:
              frame.meta
              |> ensure_map()
              |> maybe_put(:capability_provenance, capability_provenance)
              |> maybe_put(:source_watermarks, source_watermarks)
              |> maybe_put(:source_request_time_context, source_request_time_context)
              |> maybe_put(:source_request_context, source_request_context)
        }

      frame ->
        frame
    end)
  end

  defp normalize_frames(frames) when is_list(frames),
    do: Enum.map(frames, &(Frame.normalize(&1) || &1))

  defp normalize_frames(frames), do: frames

  defp capability_provenance(%PlannedSourceRequest{} = request) do
    request.metadata
    |> ensure_map()
    |> Map.get(:capability_provenance)
  end

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, _key, value) when is_map(value) and map_size(value) == 0, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp source_watermarks(%SourceResult{watermarks: watermarks}) when is_list(watermarks) do
    watermarks
    |> Enum.map(&source_watermark_metadata/1)
    |> Enum.reject(&(&1 == %{}))
  end

  defp source_watermarks(%SourceResult{}), do: []

  defp source_watermark_metadata(%SourceWatermark{} = watermark) do
    metadata =
      watermark
      |> SourceWatermark.normalize()
      |> Map.from_struct()
      |> drop_nil_values()

    case Map.get(metadata, :meta) do
      meta when is_map(meta) ->
        meta
        |> drop_nil_values()
        |> Map.merge(metadata)

      _meta ->
        metadata
    end
  end

  defp source_watermark_metadata(watermark) when is_map(watermark) do
    watermark
    |> SourceWatermark.normalize()
    |> source_watermark_metadata()
  end

  defp source_watermark_metadata(_watermark), do: %{}

  defp source_request_time_context(%PlannedSourceRequest{time_context: time_context})
       when is_map(time_context) do
    context = context_metadata(time_context)

    %{
      mode: context_value(context, :mode),
      axis: context_value(context, :axis),
      from: context_value(context, :from),
      to: context_value(context, :to),
      start: context_value(context, :start),
      end: context_value(context, :end),
      start_time: context_value(context, :start_time),
      end_time: context_value(context, :end_time),
      replay_run_id: context_value(context, :replay_run_id)
    }
    |> drop_nil_values()
  end

  defp source_request_time_context(%PlannedSourceRequest{}), do: %{}

  defp source_request_context(
         %PlannedSourceRequest{} = request,
         source_request_time_context
       ) do
    data_context = source_request_data_context(request)
    scope_context = source_request_scope_context(request.scope_context)

    %{
      source_request_id: request.request_id,
      logical_source: request.logical_source,
      requested_scope_kind: Map.get(scope_context, :kind),
      requested_scope_ids: Map.get(scope_context, :ids),
      requested_contact_id: Map.get(scope_context, :contact_id),
      requested_contact_ids: Map.get(scope_context, :contact_ids),
      time_mode: Map.get(source_request_time_context, :mode),
      time_axis: Map.get(source_request_time_context, :axis),
      replay_run_id:
        Map.get(source_request_time_context, :replay_run_id) ||
          Map.get(data_context, :replay_run_id),
      requested_realm: Map.get(data_context, :realm),
      requested_data_view: Map.get(data_context, :view),
      requested_data_source_id: Map.get(data_context, :data_source_id),
      requested_source_binding_id: Map.get(data_context, :source_binding_id),
      requested_dataset: Map.get(data_context, :dataset),
      requested_validity_state: Map.get(data_context, :validity_state)
    }
    |> drop_nil_values()
  end

  defp source_request_scope_context(scope_context) do
    scope_context = ScopeContext.from_map(scope_context)
    kind = ScopeContext.primary_kind(scope_context)
    ids = ScopeContext.primary_ids(scope_context)
    contact_ids = ScopeContext.scope_ids(scope_context, :contact)

    %{
      kind: kind,
      ids: ids,
      contact_id: List.first(contact_ids),
      contact_ids: contact_ids
    }
    |> drop_nil_values()
  end

  defp source_request_data_context(%PlannedSourceRequest{} = request) do
    data_context = request.data_context
    logical_source = request.logical_source

    %{
      realm:
        DataContext.source_value(data_context, logical_source, :realm) ||
          inferred_replay_realm(request),
      data_source_id: DataContext.source_value(data_context, logical_source, :data_source_id),
      source_binding_id:
        DataContext.source_value(data_context, logical_source, :source_binding_id),
      dataset: DataContext.source_value(data_context, logical_source, :dataset),
      replay_run_id: DataContext.source_value(data_context, logical_source, :replay_run_id),
      view: DataContext.source_value(data_context, logical_source, :view),
      validity_state: DataContext.source_value(data_context, logical_source, :validity_state)
    }
    |> drop_nil_values()
  end

  defp context_metadata(%{__struct__: _struct} = context), do: Map.from_struct(context)
  defp context_metadata(context) when is_map(context), do: context

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp inferred_replay_realm(%PlannedSourceRequest{time_context: time_context}) do
    if normalized_time_mode(context_value(time_context, :mode)) == :replay_run do
      :replay
    end
  end

  defp normalized_time_mode(value) when is_atom(value), do: value

  defp normalized_time_mode(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> case do
      "replay_run" -> :replay_run
      other -> other
    end
  end

  defp normalized_time_mode(value), do: value

  defp drop_nil_values(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp placement_warnings(warnings, placement_id) do
    Enum.map(warnings, fn %ResolveWarning{} = warning ->
      %ResolveWarning{warning | scope: :placement, placement_id: placement_id}
    end)
  end
end
