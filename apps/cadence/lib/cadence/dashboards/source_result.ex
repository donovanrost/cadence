defmodule Cadence.Dashboards.SourceResult do
  @moduledoc """
  Result returned by dashboard source adapters.

  The engine planner produces `PlannedSourceRequest` values. Source adapters
  resolve those requests into normalized frames plus structured degradation
  metadata that callers can surface without coupling widgets to backend details.
  """

  alias Cadence.Dashboards.{Annotation, Frame, ResolveWarning}
  alias Cadence.Platform.ContractNormalization

  alias Cadence.DataSources.SourceWatermark

  @type t :: %__MODULE__{
          request_id: binary() | nil,
          frames: [Frame.t()],
          annotations: [Annotation.t()],
          warnings: [ResolveWarning.t()],
          watermarks: [SourceWatermark.t()],
          meta: map()
        }

  defstruct [
    :request_id,
    frames: [],
    annotations: [],
    warnings: [],
    watermarks: [],
    meta: %{}
  ]

  @spec new(map() | t()) :: t()
  def new(attrs), do: normalize(attrs)

  @spec normalize(map() | t()) :: t() | nil
  def normalize(%__MODULE__{} = result) do
    %__MODULE__{
      result
      | frames: normalize_frames(result.frames),
        annotations: normalize_annotations(result.annotations),
        warnings: normalize_warnings(result.warnings),
        watermarks: normalize_watermarks(result.watermarks),
        meta: ContractNormalization.map_or_default(result.meta)
    }
  end

  def normalize(result) when is_map(result) do
    %__MODULE__{
      request_id: ContractNormalization.attr(result, :request_id),
      frames:
        result
        |> ContractNormalization.attr(:frames, [])
        |> normalize_frames(),
      annotations:
        result
        |> ContractNormalization.attr(:annotations, [])
        |> normalize_annotations(),
      warnings:
        result
        |> ContractNormalization.attr(:warnings, [])
        |> normalize_warnings(),
      watermarks:
        result
        |> ContractNormalization.attr(:watermarks, [])
        |> normalize_watermarks(),
      meta:
        result
        |> ContractNormalization.attr(:meta, %{})
        |> ContractNormalization.map_or_default()
    }
  end

  def normalize(_other), do: nil

  defp normalize_frames(frames) when is_list(frames),
    do: Enum.map(frames, &(Frame.normalize(&1) || &1))

  defp normalize_frames(frames), do: frames

  defp normalize_annotations(annotations) when is_list(annotations) do
    Enum.map(annotations, &(Annotation.normalize(&1) || &1))
  end

  defp normalize_annotations(annotations), do: annotations

  defp normalize_warnings(warnings) when is_list(warnings),
    do: Enum.map(warnings, &normalize_warning/1)

  defp normalize_warnings(warnings), do: warnings

  defp normalize_warning(%ResolveWarning{} = warning), do: ResolveWarning.normalize(warning)
  defp normalize_warning(warning) when is_map(warning), do: ResolveWarning.normalize(warning)
  defp normalize_warning(warning), do: warning

  defp normalize_watermarks(watermarks) when is_list(watermarks),
    do: Enum.map(watermarks, &normalize_watermark/1)

  defp normalize_watermarks(watermarks), do: watermarks

  defp normalize_watermark(%SourceWatermark{} = watermark),
    do: SourceWatermark.normalize(watermark)

  defp normalize_watermark(watermark) when is_map(watermark),
    do: SourceWatermark.normalize(watermark)

  defp normalize_watermark(watermark), do: watermark
end
