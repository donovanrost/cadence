defmodule CadenceWeb.OpsDashboardShowLive.ChartAppends do
  @moduledoc """
  Live time-series append payloads for dashboard charts.

  This module owns the server-side "tlm:append" contract: point appends,
  marker-only appends, and marker snapshot diffing.
  """

  import Phoenix.LiveView, only: [push_event: 3]

  alias CadenceWeb.OpsDashboardShowLive.{
    MarkerCategories,
    RuntimeResult,
    TimeSeriesData,
    TimeSeriesWidgetMarkers
  }

  @spec push(Phoenix.LiveView.Socket.t(), map(), map()) :: Phoenix.LiveView.Socket.t()
  def push(socket, previous_data, previous_marker_snapshots \\ %{}) do
    engine_frames_by_placement = current_engine_frames_by_placement(socket)
    hidden_markers = Map.get(socket.assigns, :dashboard_hidden_marker_categories, [])

    chart_items =
      socket.assigns.dashboard_render_items
      |> Enum.filter(&(&1.widget.type == :time_series))

    {appends, marker_appends} =
      chart_items
      |> Enum.reduce({%{}, %{}}, fn item, {series_acc, marker_acc} ->
        placement_frames = Map.get(engine_frames_by_placement, item.placement_id)

        payload = chart_append_payload(item, previous_data, engine_frames_by_placement)

        markers =
          placement_frames
          |> TimeSeriesWidgetMarkers.append_markers(
            item.widget,
            Map.get(previous_marker_snapshots, item.placement_id, %{})
          )
          |> reject_hidden_markers(hidden_markers)

        {
          maybe_put_series_append(series_acc, item.placement_id, payload),
          maybe_put_marker_append(marker_acc, item.placement_id, markers)
        }
      end)

    if chart_items == [] do
      socket
    else
      payload =
        %{
          "series" => appends,
          "window_end_ms" => System.system_time(:millisecond),
          "refresh_interval_ms" => refresh_interval_ms(socket)
        }
        |> maybe_put("markers", marker_appends, marker_appends == %{})

      push_event(socket, "tlm:append", payload)
    end
  end

  @spec marker_snapshots(Phoenix.LiveView.Socket.t() | map()) :: map()
  def marker_snapshots(%{assigns: assigns}) when is_map(assigns), do: marker_snapshots(assigns)

  def marker_snapshots(assigns) when is_map(assigns) do
    frames_by_placement = Map.get(assigns, :dashboard_engine_frames_by_placement, %{})

    assigns
    |> Map.get(:dashboard_render_items, [])
    |> Enum.filter(&(&1.widget.type == :time_series))
    |> Map.new(fn item ->
      snapshot =
        frames_by_placement
        |> Map.get(item.placement_id)
        |> TimeSeriesWidgetMarkers.snapshot(item.widget)

      {item.placement_id, snapshot}
    end)
    |> Enum.reject(fn {_placement_id, snapshot} -> snapshot == %{} end)
    |> Map.new()
  end

  # Snapshots stay unfiltered so append diffing is stable across toggles;
  # un-hiding a category re-renders via the chart_epoch remount instead.
  defp reject_hidden_markers(markers, []), do: markers

  defp reject_hidden_markers(markers, hidden_markers) do
    markers
    |> Map.replace_lazy(
      :limit_markers,
      &MarkerCategories.filter_limit_markers(&1, hidden_markers)
    )
    |> Map.replace_lazy(
      :event_markers,
      &MarkerCategories.filter_event_markers(&1, hidden_markers)
    )
    |> Map.reject(fn {_key, filtered} -> filtered == [] end)
  end

  defp chart_append_payload(item, previous_data, engine_frames_by_placement) do
    engine_frames_by_placement
    |> Map.get(item.placement_id)
    |> TimeSeriesData.append(previous_data[item.placement_id])
  end

  defp current_engine_frames_by_placement(%{assigns: %{dashboard_engine_result: result}})
       when not is_nil(result) do
    RuntimeResult.frames_by_placement(result)
  end

  defp current_engine_frames_by_placement(_socket), do: %{}

  defp maybe_put_series_append(acc, _placement_id, nil), do: acc

  defp maybe_put_series_append(acc, placement_id, payload),
    do: Map.put(acc, placement_id, payload)

  defp maybe_put_marker_append(acc, _placement_id, []), do: acc
  defp maybe_put_marker_append(acc, _placement_id, markers) when markers == %{}, do: acc

  defp maybe_put_marker_append(acc, placement_id, markers),
    do: Map.put(acc, placement_id, markers)

  defp refresh_interval_ms(socket) do
    case Map.get(socket.assigns, :dashboard_live_refresh_ms) do
      value when is_integer(value) and value > 0 -> value
      _missing -> configured_refresh_interval_ms()
    end
  end

  defp configured_refresh_interval_ms do
    case Application.get_env(:cadence_web, :dashboard_live_refresh_ms, 1_000) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> 1_000
    end
  end

  defp maybe_put(map, _key, _value, true), do: map
  defp maybe_put(map, key, value, false), do: Map.put(map, key, value)
end
