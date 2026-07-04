defmodule Cadence.Dashboards.DashboardResolveResult do
  @moduledoc """
  Dashboard engine planning/resolve result.
  """

  alias Cadence.Dashboards.{
    ContractNormalization,
    DashboardResolveRequest,
    PlacementFrames,
    PlannedSourceRequest,
    ResolveWarning,
    SourceWatermark
  }

  @resolve_modes DashboardResolveRequest.resolve_modes()

  @type t :: %__MODULE__{
          dashboard_id: binary(),
          resolve_mode: atom(),
          frames_by_placement: %{optional(binary()) => PlacementFrames.t()},
          dashboard_warnings: [ResolveWarning.t()],
          watermarks: [SourceWatermark.t()],
          subscriptions: [term()],
          planned_source_requests: [PlannedSourceRequest.t()],
          plan_metadata: map()
        }

  defstruct [
    :dashboard_id,
    :resolve_mode,
    frames_by_placement: %{},
    dashboard_warnings: [],
    watermarks: [],
    subscriptions: [],
    planned_source_requests: [],
    plan_metadata: %{}
  ]

  @spec new(map() | t()) :: t()
  def new(attrs), do: normalize(attrs)

  @spec normalize(map() | t()) :: t()
  def normalize(%__MODULE__{} = result) do
    %__MODULE__{
      result
      | resolve_mode: ContractNormalization.known_atom(result.resolve_mode, @resolve_modes),
        frames_by_placement: normalize_frames_by_placement(result.frames_by_placement),
        dashboard_warnings: normalize_warnings(result.dashboard_warnings),
        watermarks: normalize_watermarks(result.watermarks),
        subscriptions: ContractNormalization.list_or_default(result.subscriptions),
        planned_source_requests: normalize_planned_requests(result.planned_source_requests),
        plan_metadata: ContractNormalization.map_or_default(result.plan_metadata)
    }
  end

  def normalize(attrs) when is_map(attrs) do
    %__MODULE__{
      dashboard_id: ContractNormalization.attr(attrs, :dashboard_id),
      resolve_mode:
        attrs
        |> ContractNormalization.attr(:resolve_mode)
        |> ContractNormalization.known_atom(@resolve_modes),
      frames_by_placement:
        attrs
        |> ContractNormalization.attr(:frames_by_placement, %{})
        |> normalize_frames_by_placement(),
      dashboard_warnings:
        attrs
        |> ContractNormalization.attr(:dashboard_warnings, [])
        |> normalize_warnings(),
      watermarks:
        attrs
        |> ContractNormalization.attr(:watermarks, [])
        |> normalize_watermarks(),
      subscriptions:
        attrs
        |> ContractNormalization.attr(:subscriptions, [])
        |> ContractNormalization.list_or_default(),
      planned_source_requests:
        attrs
        |> ContractNormalization.attr(:planned_source_requests, [])
        |> normalize_planned_requests(),
      plan_metadata:
        attrs
        |> ContractNormalization.attr(:plan_metadata, %{})
        |> ContractNormalization.map_or_default()
    }
  end

  defp normalize_frames_by_placement(frames_by_placement) when is_map(frames_by_placement) do
    Map.new(frames_by_placement, fn {placement_id, placement_frames} ->
      {placement_id, PlacementFrames.normalize(placement_frames)}
    end)
  end

  defp normalize_frames_by_placement(value), do: value

  defp normalize_warnings(warnings) when is_list(warnings),
    do: Enum.map(warnings, &ResolveWarning.normalize/1)

  defp normalize_warnings(value), do: value

  defp normalize_watermarks(watermarks) when is_list(watermarks),
    do: Enum.map(watermarks, &SourceWatermark.normalize/1)

  defp normalize_watermarks(value), do: value

  defp normalize_planned_requests(requests) when is_list(requests),
    do: Enum.map(requests, &PlannedSourceRequest.normalize/1)

  defp normalize_planned_requests(value), do: value
end
