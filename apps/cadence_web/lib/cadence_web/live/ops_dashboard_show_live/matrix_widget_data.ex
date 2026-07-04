defmodule CadenceWeb.OpsDashboardShowLive.MatrixWidgetData do
  @moduledoc """
  Presenter for row-oriented status matrix and data table widgets.
  """

  alias Cadence.Dashboards.PlacementFrames

  alias CadenceWeb.OpsDashboardShowLive.{
    DataManagementPresentation,
    StatusMatrixData,
    WidgetLifecyclePresentation,
    WidgetLinks
  }

  @spec status_matrix(PlacementFrames.t()) :: map()
  def status_matrix(%PlacementFrames{} = placement_frames) do
    rows = StatusMatrixData.rows(placement_frames)

    if rows == [] do
      empty_data(placement_frames, :status_matrix)
    else
      %{
        kind: :status_matrix,
        rows: rows,
        links: rows |> Enum.flat_map(& &1.links) |> WidgetLinks.uniq_link_summaries(),
        data_management: DataManagementPresentation.aggregate_rows(rows),
        stale?: Enum.any?(rows, & &1.stale?),
        unresolved?: false,
        engine_backed?: true
      }
      |> put_row_lifecycle(placement_frames, rows)
    end
  end

  @spec data_table(PlacementFrames.t()) :: map()
  def data_table(%PlacementFrames{} = placement_frames) do
    rows = StatusMatrixData.rows(placement_frames)

    if rows == [] do
      empty_data(placement_frames, :data_table)
    else
      %{
        kind: :data_table,
        rows: StatusMatrixData.data_table_rows(rows),
        links: rows |> Enum.flat_map(& &1.links) |> WidgetLinks.uniq_link_summaries(),
        data_management: DataManagementPresentation.aggregate_rows(rows),
        stale?: Enum.any?(rows, & &1.stale?),
        unresolved?: false,
        engine_backed?: true
      }
      |> put_row_lifecycle(placement_frames, rows)
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

  defp put_row_lifecycle(data, placement_frames, rows) do
    WidgetLifecyclePresentation.put(
      data,
      placement_frames,
      placement_frames.primary,
      WidgetLifecyclePresentation.aggregate_row_data_state(rows),
      Enum.any?(rows, & &1.stale?)
    )
  end
end
