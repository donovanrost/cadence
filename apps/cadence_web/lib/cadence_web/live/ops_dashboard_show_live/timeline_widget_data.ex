defmodule CadenceWeb.OpsDashboardShowLive.TimelineWidgetData do
  @moduledoc """
  Presenter for state and event timeline widgets.
  """

  alias Cadence.Dashboards.PlacementFrames

  alias CadenceWeb.OpsDashboardShowLive.{
    DataManagementPresentation,
    EventTimelineData,
    StateTimelineData,
    WidgetLifecyclePresentation,
    WidgetLinks
  }

  @spec state_timeline(PlacementFrames.t()) :: map()
  def state_timeline(%PlacementFrames{} = placement_frames) do
    rows = StateTimelineData.rows(placement_frames)

    if rows == [] do
      empty_data(placement_frames, :state_timeline)
    else
      stale? = Enum.any?(rows, & &1.stale?)

      %{
        kind: :state_timeline,
        rows: rows,
        lanes: StateTimelineData.lanes(rows),
        links: rows |> Enum.flat_map(& &1.links) |> WidgetLinks.uniq_link_summaries(),
        data_management: DataManagementPresentation.aggregate_rows(rows),
        stale?: stale?,
        unresolved?: false,
        engine_backed?: true
      }
      |> put_ready_lifecycle(placement_frames, stale?)
    end
  end

  @spec event_timeline(PlacementFrames.t()) :: map()
  def event_timeline(%PlacementFrames{} = placement_frames) do
    rows = EventTimelineData.rows(placement_frames)

    if rows == [] do
      empty_data(placement_frames, :event_timeline)
    else
      stale? = EventTimelineData.stale?(placement_frames)

      %{
        kind: :event_timeline,
        rows: rows,
        links: rows |> Enum.flat_map(& &1.links) |> WidgetLinks.uniq_link_summaries(),
        data_management: DataManagementPresentation.aggregate_rows(rows),
        stale?: stale?,
        unresolved?: false,
        engine_backed?: true
      }
      |> put_ready_lifecycle(placement_frames, stale?)
    end
  end

  defp empty_data(%PlacementFrames{} = placement_frames, kind) do
    %{
      kind: kind,
      rows: [],
      links: [],
      data_management: DataManagementPresentation.placement(placement_frames),
      stale?: false,
      unresolved?: false,
      engine_backed?: true
    }
    |> WidgetLifecyclePresentation.put(
      placement_frames,
      placement_frames.primary,
      :no_data,
      false
    )
  end

  defp put_ready_lifecycle(data, placement_frames, stale?) do
    WidgetLifecyclePresentation.put(
      data,
      placement_frames,
      placement_frames.primary,
      :ready,
      stale?
    )
  end
end
