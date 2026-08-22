defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesWidgetMarkers do
  @moduledoc """
  Widget-facing marker contract for time-series charts.

  Lower-level projector modules translate engine frames into marker maps. This
  module owns the chart payload shape and widget-type gating used by render and
  live append paths.
  """

  alias Cadence.Dashboards.{PlacementFrames, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.{TimeSeriesAnnotations, TimeSeriesMarkers}

  @spec annotations(PlacementFrames.t() | nil, RenderWidget.t()) :: [map()]
  def annotations(%PlacementFrames{} = placement_frames, %RenderWidget{type: :time_series}) do
    TimeSeriesAnnotations.annotations(placement_frames)
  end

  def annotations(_placement_frames, %RenderWidget{}), do: []

  @spec limit_markers(PlacementFrames.t() | nil, RenderWidget.t()) :: [map()]
  def limit_markers(%PlacementFrames{} = placement_frames, %RenderWidget{type: :time_series}) do
    TimeSeriesMarkers.limit_markers(placement_frames)
  end

  def limit_markers(_placement_frames, %RenderWidget{}), do: []

  @spec event_markers(PlacementFrames.t() | nil, RenderWidget.t()) :: [map()]
  def event_markers(%PlacementFrames{} = placement_frames, %RenderWidget{type: :time_series}) do
    TimeSeriesMarkers.event_markers(placement_frames)
  end

  def event_markers(_placement_frames, %RenderWidget{}), do: []

  @spec append_markers(PlacementFrames.t() | nil, RenderWidget.t()) :: map()
  def append_markers(%PlacementFrames{} = placement_frames, %RenderWidget{type: :time_series}) do
    append_markers(placement_frames, %RenderWidget{type: :time_series}, %{})
  end

  def append_markers(_placement_frames, %RenderWidget{}), do: %{}

  @spec append_markers(PlacementFrames.t() | nil, RenderWidget.t(), map()) :: map()
  def append_markers(
        %PlacementFrames{} = placement_frames,
        %RenderWidget{type: :time_series},
        previous_snapshot
      )
      when is_map(previous_snapshot) do
    limit_markers =
      placement_frames
      |> TimeSeriesMarkers.limit_markers()
      |> new_markers(Map.get(previous_snapshot, :limit_markers, MapSet.new()))

    event_markers =
      placement_frames
      |> TimeSeriesMarkers.event_markers()
      |> new_markers(Map.get(previous_snapshot, :event_markers, MapSet.new()))

    annotations =
      placement_frames
      |> TimeSeriesAnnotations.annotations()
      |> new_markers(Map.get(previous_snapshot, :annotations, MapSet.new()))

    %{}
    |> maybe_put(:limit_markers, limit_markers)
    |> maybe_put(:event_markers, event_markers)
    |> maybe_put(:annotations, annotations)
  end

  def append_markers(_placement_frames, %RenderWidget{}, _previous_snapshot), do: %{}

  @spec snapshot(PlacementFrames.t() | nil, RenderWidget.t()) :: map()
  def snapshot(%PlacementFrames{} = placement_frames, %RenderWidget{type: :time_series}) do
    %{
      limit_markers:
        placement_frames
        |> TimeSeriesMarkers.limit_markers()
        |> marker_fingerprints(),
      event_markers:
        placement_frames
        |> TimeSeriesMarkers.event_markers()
        |> marker_fingerprints(),
      annotations:
        placement_frames
        |> TimeSeriesAnnotations.annotations()
        |> marker_fingerprints()
    }
  end

  def snapshot(_placement_frames, %RenderWidget{}), do: %{}

  defp new_markers(markers, previous_fingerprints) do
    previous_fingerprints = map_set_or_empty(previous_fingerprints)
    Enum.reject(markers, &(marker_fingerprint(&1) in previous_fingerprints))
  end

  defp marker_fingerprints(markers) do
    markers
    |> Enum.map(&marker_fingerprint/1)
    |> MapSet.new()
  end

  defp marker_fingerprint(marker) when is_map(marker) do
    {marker_identity(marker), :erlang.phash2(marker)}
  end

  defp marker_identity(marker) do
    Map.get(marker, :annotation_id) ||
      Map.get(marker, :link_id) ||
      Map.get(marker, :marker_id) ||
      {
        Map.get(marker, :marker_type),
        Map.get(marker, :target_id),
        Map.get(marker, :limit_event_id),
        Map.get(marker, :limit_definition_id),
        Map.get(marker, :mission_event_id),
        Map.get(marker, :timestamp_ms),
        Map.get(marker, :starts_at_ms),
        Map.get(marker, :ends_at_ms)
      }
  end

  defp map_set_or_empty(%MapSet{} = map_set), do: map_set
  defp map_set_or_empty(_value), do: MapSet.new()

  defp maybe_put(payload, _key, []), do: payload
  defp maybe_put(payload, key, markers), do: Map.put(payload, key, markers)
end
