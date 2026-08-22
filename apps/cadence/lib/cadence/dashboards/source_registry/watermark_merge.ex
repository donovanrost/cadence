defmodule Cadence.Dashboards.SourceRegistry.WatermarkMerge do
  @moduledoc """
  Applies durable source-watermark projections to source facts and results.
  """

  alias Cadence.Dashboards.{
    Frame,
    PlannedSourceRequest,
    ResolveWarning,
    SourceFacts,
    SourceResult
  }

  alias Cadence.DataSources.{SourceWatermark, SourceWatermarkStatus}

  @spec merge_facts(SourceFacts.t(), SourceWatermarkStatus.t(), PlannedSourceRequest.t()) ::
          SourceFacts.t()
  def merge_facts(
        %SourceFacts{} = facts,
        %SourceWatermarkStatus{} = status,
        %PlannedSourceRequest{} = request
      ) do
    watermark = watermark(status, request)

    SourceFacts.new(%{
      facts
      | watermark: watermark,
        watermarks: [watermark],
        meta: durable_meta(facts.meta, status)
    })
  end

  @spec merge_result(SourceResult.t(), SourceWatermarkStatus.t(), PlannedSourceRequest.t()) ::
          SourceResult.t()
  def merge_result(
        %SourceResult{} = result,
        %SourceWatermarkStatus{} = status,
        %PlannedSourceRequest{} = request
      ) do
    watermark = watermark(status, request)

    result
    |> clear_unknown_watermark_warnings(watermark)
    |> then(
      &SourceResult.new(%{
        &1
        | watermarks: [watermark],
          meta: durable_meta(result.meta, status)
      })
    )
  end

  defp watermark(%SourceWatermarkStatus{} = status, %PlannedSourceRequest{} = request) do
    SourceWatermarkStatus.to_source_watermark(status,
      request_id: request.request_id,
      scope: request.scope_context
    )
  end

  defp durable_meta(meta, %SourceWatermarkStatus{} = status) do
    meta
    |> ensure_map()
    |> Map.put(:durable_source_watermark?, true)
    |> Map.put(:source_watermark_event_id, status.source_watermark_event_id)
    |> Map.put(:source_watermark_observed_at, status.observed_at)
    |> Map.put(:source_watermark_last_seen_at, status.last_seen_at)
    |> Map.put(:source_watermark_reason, status.reason)
  end

  defp clear_unknown_watermark_warnings(
         %SourceResult{} = result,
         %SourceWatermark{confidence: confidence}
       )
       when confidence in [:authoritative, :best_effort] do
    %SourceResult{
      result
      | warnings: Enum.reject(result.warnings, &watermark_unknown_warning?/1),
        frames: Enum.map(result.frames, &clear_frame_warning_code(&1, :watermark_unknown))
    }
  end

  defp clear_unknown_watermark_warnings(%SourceResult{} = result, _watermark), do: result

  defp watermark_unknown_warning?(%ResolveWarning{code: code}),
    do: normalize_warning_code(code) == :watermark_unknown

  defp watermark_unknown_warning?(warning) when is_map(warning),
    do: warning |> map_value(:code) |> normalize_warning_code() == :watermark_unknown

  defp watermark_unknown_warning?(_warning), do: false

  defp clear_frame_warning_code(%Frame{meta: meta} = frame, code) when is_map(meta) do
    warning_codes =
      meta
      |> Map.get(:warning_codes, Map.get(meta, "warning_codes", []))
      |> List.wrap()
      |> Enum.reject(&(normalize_warning_code(&1) == code))

    %Frame{frame | meta: Map.put(meta, :warning_codes, warning_codes)}
  end

  defp clear_frame_warning_code(frame, _code), do: frame

  defp normalize_warning_code(code) when is_atom(code), do: code

  defp normalize_warning_code(code) when is_binary(code) do
    code
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  defp normalize_warning_code(_code), do: nil

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}
end
