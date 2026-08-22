defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkers do
  @moduledoc """
  Marker and overlay projection for time-series widgets.

  The dashboard render contract keeps markers separate from series samples so
  chart clients can render operational context without coupling to source frame
  internals.
  """

  alias Cadence.Dashboards.{Frame, PlacementFrames}

  alias CadenceWeb.OpsDashboardShowLive.{
    TimeSeriesLimitMarkers,
    TimeSeriesMissionEventMarkers,
    TimeSeriesSourceBindingMarkers,
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
    |> collapse_source_watermark_markers()
    |> Enum.uniq_by(
      &(Map.get(&1, :marker_id) ||
          Map.get(&1, :link_id) ||
          {Map.get(&1, :marker_type), Map.get(&1, :target_id), marker_sort_time(&1)})
    )
  end

  def event_markers(_placement_frames), do: []

  defp event_frame_markers(%Frame{source: :events, shape: :intervals}), do: []

  defp event_frame_markers(%Frame{source: :events, shape: :events} = frame) do
    cond do
      source_health_event_frame?(frame) ->
        []

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

  defp source_health_event_frame?(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :family, Map.get(meta, "family")) in [:source_health, "source_health"]
  end

  defp source_health_event_frame?(%Frame{}), do: false

  # Watermark advances are high-frequency ingestion bookkeeping. A chart only
  # needs the newest completeness boundary for each source; the full event
  # history remains available through event timelines and diagnostics.
  defp collapse_source_watermark_markers(markers) do
    cursor_identities =
      markers
      |> Enum.filter(&(Map.get(&1, :marker_type) == "source_watermark_cursor"))
      |> latest_source_watermark_markers()
      |> Map.new(&{source_watermark_identity(&1), &1})

    fallback_events =
      markers
      |> Enum.filter(&(Map.get(&1, :marker_type) == "source_watermark_event"))
      |> latest_source_watermark_markers()
      |> Enum.reject(&Map.has_key?(cursor_identities, source_watermark_identity(&1)))

    markers
    |> Enum.reject(
      &(Map.get(&1, :marker_type) in ["source_watermark_cursor", "source_watermark_event"])
    )
    |> Kernel.++(Map.values(cursor_identities))
    |> Kernel.++(fallback_events)
  end

  defp latest_source_watermark_markers(markers) do
    markers
    |> Enum.group_by(&source_watermark_identity/1)
    |> Enum.map(fn {_identity, candidates} ->
      Enum.max_by(candidates, &marker_sort_time/1, fn -> nil end)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp source_watermark_identity(marker) do
    {
      Map.get(marker, :logical_source),
      Map.get(marker, :data_source_id),
      Map.get(marker, :source_binding_id),
      Map.get(marker, :dataset),
      Map.get(marker, :realm),
      Map.get(marker, :replay_run_id)
    }
  end

  defp marker_sort_time(%{timestamp_ms: timestamp_ms}), do: timestamp_ms
  defp marker_sort_time(%{starts_at_ms: starts_at_ms}), do: starts_at_ms
  defp marker_sort_time(_marker), do: nil
end
