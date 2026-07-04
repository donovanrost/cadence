defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkers do
  @moduledoc """
  Marker and overlay projection for time-series widgets.

  The dashboard render contract keeps markers separate from series samples so
  chart clients can render operational context without coupling to source frame
  internals.
  """

  alias Cadence.Dashboards.{Frame, PlacementFrames}

  alias CadenceWeb.OpsDashboardShowLive.{
    TimeSeriesContactIntervalMarkers,
    TimeSeriesLimitMarkers,
    TimeSeriesMissionEventMarkers,
    TimeSeriesSourceBindingMarkers,
    TimeSeriesSourceHealthMarkers,
    TimeSeriesSourceWatermarkMarkers,
    TimeSeriesTelemetryBackfillMarkers,
    TimeSeriesTelemetryRevisionMarkers
  }

  @spec limit_markers(PlacementFrames.t() | nil) :: [map()]
  def limit_markers(placement_frames), do: TimeSeriesLimitMarkers.limit_markers(placement_frames)

  @spec event_markers(PlacementFrames.t() | nil) :: [map()]
  def event_markers(%PlacementFrames{} = placement_frames) do
    event_markers =
      case placement_frames do
        %PlacementFrames{overlays: %{events: event_frames}} when is_list(event_frames) ->
          Enum.flat_map(event_frames, &event_frame_markers/1)

        _placement_frames ->
          []
      end

    (event_markers ++
       TimeSeriesSourceBindingMarkers.interval_markers(placement_frames) ++
       TimeSeriesSourceWatermarkMarkers.frame_markers(placement_frames) ++
       TimeSeriesTelemetryRevisionMarkers.range_markers(placement_frames))
    |> Enum.uniq_by(
      &(Map.get(&1, :marker_id) ||
          Map.get(&1, :link_id) ||
          {Map.get(&1, :marker_type), Map.get(&1, :target_id), marker_sort_time(&1)})
    )
  end

  def event_markers(_placement_frames), do: []

  defp event_frame_markers(%Frame{source: :events, shape: :intervals} = frame),
    do: TimeSeriesContactIntervalMarkers.interval_markers(frame)

  defp event_frame_markers(%Frame{source: :events, shape: :events} = frame) do
    cond do
      TimeSeriesSourceHealthMarkers.event_frame?(frame) ->
        TimeSeriesSourceHealthMarkers.event_markers(frame)

      TimeSeriesSourceWatermarkMarkers.event_frame?(frame) ->
        TimeSeriesSourceWatermarkMarkers.event_markers(frame)

      TimeSeriesTelemetryBackfillMarkers.event_frame?(frame) ->
        TimeSeriesTelemetryBackfillMarkers.event_markers(frame)

      TimeSeriesTelemetryRevisionMarkers.event_frame?(frame) ->
        TimeSeriesTelemetryRevisionMarkers.event_markers(frame)

      true ->
        TimeSeriesMissionEventMarkers.event_markers(frame)
    end
  end

  defp event_frame_markers(_frame), do: []

  defp marker_sort_time(%{timestamp_ms: timestamp_ms}), do: timestamp_ms
  defp marker_sort_time(%{starts_at_ms: starts_at_ms}), do: starts_at_ms
  defp marker_sort_time(_marker), do: nil
end
