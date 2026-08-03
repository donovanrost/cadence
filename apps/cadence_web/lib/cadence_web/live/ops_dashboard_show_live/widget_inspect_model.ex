defmodule CadenceWeb.OpsDashboardShowLive.WidgetInspectModel do
  @moduledoc """
  Data model for the Grafana-style widget inspect panel.

  Merges a time-series widget's backfill series into a single table
  (union of timestamps across series, blank cells for gaps), computes
  per-series stats, and renders the full dataset as CSV for download.
  The on-screen table is capped; the CSV is not.
  """

  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @max_table_rows 500

  @spec max_table_rows() :: pos_integer()
  def max_table_rows, do: @max_table_rows

  @spec build(term(), [map()], map()) :: map() | nil
  def build({:widget_inspect, %{placement_id: placement_id}}, render_items, frames_by_placement) do
    render_items
    |> Enum.find(&(&1.placement_id == placement_id))
    |> build_for_item(frames_by_placement)
  end

  def build(_panel, _render_items, _frames_by_placement), do: nil

  defp build_for_item(%{widget: %{type: :time_series} = widget} = item, frames_by_placement) do
    series =
      frames_by_placement
      |> Map.get(item.placement_id)
      |> then(&WidgetPresentation.backfill(nil, &1, widget))
      |> series_list()

    from_series(item.placement_id, widget.title, series)
  end

  defp build_for_item(_item, _frames_by_placement), do: nil

  @doc "Builds the inspect model from already-extracted backfill series."
  @spec from_series(binary(), binary() | nil, [map()]) :: map()
  def from_series(placement_id, title, series) when is_list(series) do
    rows = merged_rows(series)

    %{
      placement_id: placement_id,
      title: title,
      series: Enum.map(series, &%{label: series_label(&1), unit: &1[:unit]}),
      rows: Enum.take(rows, @max_table_rows),
      row_count_total: length(rows),
      capped?: length(rows) > @max_table_rows,
      stats: Enum.map(series, &series_stats/1),
      csv: csv(series, rows),
      time_range: time_range(rows)
    }
  end

  defp series_list(%{series: series}) when is_list(series), do: series
  defp series_list(_backfill), do: []

  # Union of timestamps across series, latest first, blanks for gaps.
  defp merged_rows(series) do
    value_maps = Enum.map(series, &points_by_timestamp/1)

    value_maps
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    |> Enum.sort(:desc)
    |> Enum.map(fn timestamp_ms ->
      %{
        timestamp_ms: timestamp_ms,
        values: Enum.map(value_maps, &Map.get(&1, timestamp_ms))
      }
    end)
  end

  defp points_by_timestamp(%{points: points}) when is_list(points) do
    for point <- points, [timestamp_ms, value | _meta] = point, is_number(value), into: %{} do
      {timestamp_ms, value}
    end
  end

  defp points_by_timestamp(_series), do: %{}

  defp series_stats(series) do
    values =
      series
      |> Map.get(:points, [])
      |> Enum.flat_map(fn
        [_timestamp_ms, value | _meta] when is_number(value) -> [value]
        _point -> []
      end)

    %{
      label: series_label(series),
      unit: series[:unit],
      count: length(values),
      min: safe_min(values),
      max: safe_max(values),
      mean: mean(values),
      last: List.last(values)
    }
  end

  defp safe_min([]), do: nil
  defp safe_min(values), do: Enum.min(values)

  defp safe_max([]), do: nil
  defp safe_max(values), do: Enum.max(values)

  defp mean([]), do: nil
  defp mean(values), do: Float.round(Enum.sum(values) / length(values), 3)

  defp time_range([]), do: nil

  defp time_range(rows) do
    {List.last(rows).timestamp_ms, List.first(rows).timestamp_ms}
  end

  defp csv(series, rows) do
    header = ["time_utc" | Enum.map(series, &csv_column_label/1)]

    data_rows =
      rows
      |> Enum.reverse()
      |> Enum.map(fn row ->
        [iso_timestamp(row.timestamp_ms) | Enum.map(row.values, &csv_value/1)]
      end)

    [header | data_rows]
    |> Enum.map_join("\r\n", fn fields -> Enum.map_join(fields, ",", &csv_field/1) end)
  end

  defp csv_column_label(series) do
    case series[:unit] do
      unit when is_binary(unit) and unit != "" -> "#{series_label(series)} (#{unit})"
      _missing -> series_label(series)
    end
  end

  defp series_label(series) do
    series[:label] || series[:observable_id] || series[:id] || "value"
  end

  defp csv_value(nil), do: ""
  defp csv_value(value), do: to_string(value)

  defp csv_field(field) do
    field = to_string(field)

    if String.contains?(field, [",", "\"", "\n", "\r"]) do
      "\"" <> String.replace(field, "\"", "\"\"") <> "\""
    else
      field
    end
  end

  @spec iso_timestamp(integer()) :: binary()
  def iso_timestamp(timestamp_ms) when is_integer(timestamp_ms) do
    timestamp_ms
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_iso8601()
  end
end
