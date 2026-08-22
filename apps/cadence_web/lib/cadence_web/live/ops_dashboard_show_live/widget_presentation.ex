defmodule CadenceWeb.OpsDashboardShowLive.WidgetPresentation do
  @moduledoc false

  alias Cadence.Dashboards.{PlacementFrames, RenderWidget}

  alias CadenceWeb.OpsDashboardShowLive.{
    TimeSeriesData,
    TimeSeriesWidgetMarkers,
    WidgetData
  }

  @spec data(term(), PlacementFrames.t() | nil, RenderWidget.t()) :: term()
  defdelegate data(legacy_data, placement_frames, widget), to: WidgetData

  @spec backfill(term(), PlacementFrames.t() | nil, RenderWidget.t()) :: term()
  def backfill(_legacy_backfill, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :time_series
      }) do
    TimeSeriesData.backfill(placement_frames)
  end

  def backfill(_legacy_backfill, _placement_frames, %RenderWidget{}), do: nil

  @spec compare_backfill(PlacementFrames.t() | nil, RenderWidget.t()) :: term()
  def compare_backfill(%PlacementFrames{} = placement_frames, %RenderWidget{
        type: :time_series
      }) do
    TimeSeriesData.backfill(placement_frames)
  end

  def compare_backfill(_placement_frames, %RenderWidget{}), do: nil

  @spec limit_markers(PlacementFrames.t() | nil, RenderWidget.t()) :: [map()]
  defdelegate limit_markers(placement_frames, widget), to: TimeSeriesWidgetMarkers

  @spec event_markers(PlacementFrames.t() | nil, RenderWidget.t()) :: [map()]
  defdelegate event_markers(placement_frames, widget), to: TimeSeriesWidgetMarkers

  @spec annotations(PlacementFrames.t() | nil, RenderWidget.t()) :: [map()]
  defdelegate annotations(placement_frames, widget), to: TimeSeriesWidgetMarkers
end
