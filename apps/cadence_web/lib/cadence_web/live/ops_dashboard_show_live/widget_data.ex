defmodule CadenceWeb.OpsDashboardShowLive.WidgetData do
  @moduledoc """
  Presenter for resolved dashboard widget data.

  This module turns engine placement frames into the widget-data maps consumed
  by the LiveView render model and legacy component surfaces.
  """

  alias Cadence.Dashboards.{Frame, PlacementFrames, RenderWidget}

  alias CadenceWeb.OpsDashboardShowLive.{
    ConstellationWidgetData,
    ContextScopePolicy,
    MatrixWidgetData,
    PointWidgetData,
    TimelineWidgetData,
    TimeSeriesData
  }

  @spec data(term(), PlacementFrames.t() | nil, RenderWidget.t()) :: term()
  def data(_legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :value_tile,
        binding: %{source: :operational_observables, mode: :context}
      }) do
    PointWidgetData.data(placement_frames)
  end

  def data(_legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :value_tile,
        binding: %{mode: :context}
      }) do
    PointWidgetData.context_data(placement_frames)
  end

  def data(_legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :time_series,
        binding: %{source: :operational_observables, mode: :context}
      }) do
    engine_time_series_data(placement_frames)
  end

  def data(_legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :time_series,
        binding: %{mode: :context}
      }) do
    context_widget_data(placement_frames, &engine_time_series_data/1)
  end

  def data(_legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :status_matrix,
        binding: %{source: :operational_observables, mode: :context}
      }) do
    MatrixWidgetData.status_matrix(placement_frames)
  end

  def data(_legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :status_matrix,
        binding: %{mode: :context}
      }) do
    context_widget_data(placement_frames, &MatrixWidgetData.status_matrix/1)
  end

  def data(_legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :data_table,
        binding: %{source: :operational_observables, mode: :context}
      }) do
    MatrixWidgetData.data_table(placement_frames)
  end

  def data(_legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :data_table,
        binding: %{mode: :context}
      }) do
    context_widget_data(placement_frames, &MatrixWidgetData.data_table/1)
  end

  def data(_legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :value_tile
      }) do
    PointWidgetData.data(placement_frames)
  end

  def data(_legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :time_series
      }) do
    engine_time_series_data(placement_frames)
  end

  def data(_legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :status_matrix
      }) do
    MatrixWidgetData.status_matrix(placement_frames)
  end

  def data(_legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :data_table
      }) do
    MatrixWidgetData.data_table(placement_frames)
  end

  def data(_legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :state_timeline
      }) do
    TimelineWidgetData.state_timeline(placement_frames)
  end

  def data(_legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :event_timeline
      }) do
    TimelineWidgetData.event_timeline(placement_frames)
  end

  def data(legacy_data, %PlacementFrames{} = placement_frames, %RenderWidget{
        type: :constellation_health
      }) do
    ConstellationWidgetData.data(placement_frames) || legacy_data
  end

  def data(legacy_data, _placement_frames, %RenderWidget{}), do: legacy_data

  defp context_widget_data(
         %PlacementFrames{primary: [%Frame{} = telemetry_frame | _]} = frames,
         fun
       ) do
    if ContextScopePolicy.resolved?(telemetry_frame),
      do: fun.(frames),
      else: PointWidgetData.unresolved_data()
  end

  defp context_widget_data(%PlacementFrames{} = frames, _fun) do
    PointWidgetData.source_failure_data(frames) || PointWidgetData.unresolved_data()
  end

  defp engine_time_series_data(%PlacementFrames{} = placement_frames) do
    TimeSeriesData.data(placement_frames) || PointWidgetData.source_failure_data(placement_frames)
  end
end
