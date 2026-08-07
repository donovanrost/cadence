defmodule Cadence.Dashboards.PlacementFrames do
  @moduledoc """
  Engine result bucket for one placement.
  """

  alias Cadence.Dashboards.{Annotation, Frame, ResolveWarning}
  alias Cadence.Platform.ContractNormalization

  @type t :: %__MODULE__{
          primary: [Frame.t()],
          overlays: map(),
          annotations: [Annotation.t()],
          warnings: [ResolveWarning.t()],
          planned_request_ids: [binary()]
        }

  defstruct primary: [], overlays: %{}, annotations: [], warnings: [], planned_request_ids: []

  @spec new(map() | t()) :: t()
  def new(attrs), do: normalize(attrs)

  @spec normalize(map() | t()) :: t()
  def normalize(%__MODULE__{} = placement_frames) do
    %__MODULE__{
      placement_frames
      | primary: normalize_frames(placement_frames.primary),
        overlays: normalize_overlay_frames(placement_frames.overlays),
        annotations: normalize_annotations(placement_frames.annotations),
        warnings: normalize_warnings(placement_frames.warnings),
        planned_request_ids:
          ContractNormalization.binary_list(placement_frames.planned_request_ids)
    }
  end

  def normalize(placement_frames) when is_map(placement_frames) do
    %__MODULE__{
      primary:
        placement_frames
        |> ContractNormalization.attr(:primary, [])
        |> normalize_frames(),
      overlays:
        placement_frames
        |> ContractNormalization.attr(:overlays, %{})
        |> normalize_overlay_frames(),
      annotations:
        placement_frames
        |> ContractNormalization.attr(:annotations, [])
        |> normalize_annotations(),
      warnings:
        placement_frames
        |> ContractNormalization.attr(:warnings, [])
        |> normalize_warnings(),
      planned_request_ids:
        placement_frames
        |> ContractNormalization.attr(:planned_request_ids, [])
        |> ContractNormalization.binary_list()
    }
  end

  defp normalize_frames(frames) when is_list(frames), do: Enum.map(frames, &normalize_frame/1)
  defp normalize_frames(frames), do: frames

  defp normalize_frame(frame), do: Frame.normalize(frame) || frame

  defp normalize_overlay_frames(overlays) when is_map(overlays) do
    Map.new(overlays, fn {overlay, frames} ->
      {ContractNormalization.existing_atom(overlay), normalize_frames(frames)}
    end)
  end

  defp normalize_overlay_frames(overlays), do: overlays

  defp normalize_annotations(annotations) when is_list(annotations) do
    Enum.map(annotations, &(Annotation.normalize(&1) || &1))
  end

  defp normalize_annotations(annotations), do: annotations

  defp normalize_warnings(warnings) when is_list(warnings),
    do: Enum.map(warnings, &ResolveWarning.normalize/1)

  defp normalize_warnings(warnings), do: warnings
end
