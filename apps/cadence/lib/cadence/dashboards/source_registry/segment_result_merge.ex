defmodule Cadence.Dashboards.SourceRegistry.SegmentResultMerge do
  @moduledoc """
  Merges compatible source results returned for effective binding segments.
  """

  alias Cadence.Dashboards.{
    DataLinks,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolveWarning,
    SourceResult
  }

  @type segment_metadata_fun :: (term() -> map())

  @spec merge(PlannedSourceRequest.t(), [{term(), SourceResult.t()}], segment_metadata_fun()) ::
          {:ok, SourceResult.t()} | {:error, ResolveWarning.t()}
  def merge(%PlannedSourceRequest{} = request, segment_results, segment_metadata)
      when is_list(segment_results) and is_function(segment_metadata, 1) do
    warnings = Enum.flat_map(segment_results, fn {_binding, result} -> result.warnings end)
    watermarks = Enum.flat_map(segment_results, fn {_binding, result} -> result.watermarks end)

    annotations =
      segment_results
      |> Enum.flat_map(fn {_binding, result} -> result.annotations end)
      |> Enum.uniq_by(& &1.annotation_id)

    segment_metadata =
      Enum.map(segment_results, fn {binding, _result} ->
        segment_metadata.(binding)
      end)

    with {:ok, frames} <- merge_segment_frames(request, segment_results) do
      {:ok,
       SourceResult.new(%{
         request_id: request.request_id,
         frames: frames,
         annotations: annotations,
         warnings: warnings,
         watermarks: watermarks,
         meta: %{
           logical_source: request.logical_source,
           returned_frame_count: length(frames),
           returned_annotation_count: length(annotations),
           degraded?: Enum.any?(warnings, &(&1.severity == :error)),
           segmented_source_bindings?: true,
           source_binding_segment_count: length(segment_metadata),
           source_binding_segments: segment_metadata
         }
       })}
    end
  end

  defp merge_segment_frames(%PlannedSourceRequest{} = request, segment_results) do
    frames =
      Enum.flat_map(segment_results, fn {_binding, result} -> result.frames end)

    frames
    |> Enum.map(& &1.frame_id)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn frame_id, {:ok, merged_frames} ->
      segment_frames = Enum.filter(frames, &(&1.frame_id == frame_id))

      case merge_frame_segments(request, segment_frames) do
        {:ok, frame} -> {:cont, {:ok, merged_frames ++ [frame]}}
        {:error, warning} -> {:halt, {:error, warning}}
      end
    end)
  end

  defp merge_frame_segments(%PlannedSourceRequest{}, []), do: {:ok, nil}

  defp merge_frame_segments(%PlannedSourceRequest{}, [%Frame{} = frame]) do
    {:ok, frame}
  end

  defp merge_frame_segments(%PlannedSourceRequest{} = request, [%Frame{} = first | rest] = frames) do
    if Enum.all?(rest, &compatible_frame_segment?(first, &1)) do
      {:ok, merge_compatible_frame_segments(frames)}
    else
      {:error, segment_merge_warning(request, frames)}
    end
  end

  defp compatible_frame_segment?(%Frame{} = left, %Frame{} = right) do
    left.source == right.source and left.shape == right.shape and
      left.time_axis == right.time_axis and
      field_signature(left.fields) == field_signature(right.fields)
  end

  defp field_signature(fields) do
    Enum.map(fields, fn %Field{} = field -> {field.name, field.kind} end)
  end

  defp merge_compatible_frame_segments([%Frame{} = first | _rest] = frames) do
    %Frame{
      first
      | fields: merge_segment_fields(frames),
        meta: merge_segment_frame_meta(frames)
    }
  end

  defp merge_segment_fields([%Frame{} = first | _rest] = frames) do
    first.fields
    |> Enum.with_index()
    |> Enum.map(fn {%Field{} = field, index} ->
      segment_fields = Enum.map(frames, &Enum.at(&1.fields, index))

      %Field{
        field
        | values: Enum.flat_map(segment_fields, & &1.values),
          metadata: merge_segment_field_metadata(segment_fields)
      }
    end)
  end

  defp merge_segment_field_metadata(segment_fields) do
    segment_fields
    |> Enum.map(&ensure_map(&1.metadata))
    |> merge_metadata_maps()
  end

  defp merge_segment_frame_meta(frames) do
    segment_metadata =
      frames
      |> Enum.map(&frame_source_binding_segment/1)
      |> Enum.reject(&is_nil/1)

    frames
    |> Enum.map(&ensure_map(&1.meta))
    |> merge_metadata_maps()
    |> Map.drop([
      :source_binding_id,
      :source_binding_version,
      :source_binding_event_id,
      :source_binding_interval,
      :source_binding_segment,
      :data_source_id,
      :dataset
    ])
    |> Map.put(:segmented_source_bindings?, true)
    |> Map.put(:source_binding_segments, segment_metadata)
    |> Map.put(:source_binding_segment_count, length(segment_metadata))
    |> Map.put(:data_source_ids, unique_meta_values(frames, :data_source_id))
    |> Map.put(:datasets, unique_meta_values(frames, :dataset))
    |> Map.put(
      :returned_points,
      Enum.reduce(frames, 0, &(Map.get(&1.meta, :returned_points, 0) + &2))
    )
    |> Map.put(:truncated?, Enum.any?(frames, &Map.get(&1.meta, :truncated?, false)))
  end

  defp merge_metadata_maps([]), do: %{}

  defp merge_metadata_maps([first | rest]) do
    Enum.reduce(rest, first, fn metadata, acc ->
      Map.merge(acc, metadata, &merge_metadata_value/3)
    end)
  end

  defp merge_metadata_value(_key, left, right) when is_list(left) and is_list(right) do
    Enum.uniq(left ++ right)
  end

  defp merge_metadata_value(_key, left, right) do
    if left == right, do: left, else: right || left
  end

  defp frame_source_binding_segment(%Frame{} = frame) do
    frame.meta
    |> ensure_map()
    |> Map.get(:source_binding_segment)
  end

  defp unique_meta_values(frames, key) do
    frames
    |> Enum.map(&Map.get(ensure_map(&1.meta), key))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp segment_merge_warning(%PlannedSourceRequest{} = request, frames) do
    %ResolveWarning{
      code: :source_binding_segment_merge_unsupported,
      severity: :error,
      scope: :dashboard,
      message: "Source binding segments returned incompatible frame shapes",
      details: %{
        source_request_id: request.request_id,
        logical_source: request.logical_source,
        frame_ids: Enum.map(frames, & &1.frame_id),
        frame_shapes: Enum.map(frames, & &1.shape) |> Enum.uniq(),
        time_axes: Enum.map(frames, & &1.time_axis) |> Enum.uniq(),
        field_signatures: Enum.map(frames, &field_signature(&1.fields)) |> Enum.uniq()
      },
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}
end
