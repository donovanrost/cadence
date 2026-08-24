defmodule CadenceWeb.OpsDashboardShowLive.WidgetInspectPanelComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.WidgetInspectModel

  attr(:inspect, :map, default: nil)

  def inspect_panel(assigns) do
    assigns = assign(assigns, :presentation, inspect_panel_presentation(assigns.inspect))

    ~H"""
    <.vue
      id="dashboard-widget-inspector-component"
      v-component="WidgetInspectPanel"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  @doc "Builds the JSON-safe presentation contract for the widget inspect panel."
  @spec inspect_panel_presentation(map() | nil) :: map()
  def inspect_panel_presentation(nil) do
    %{
      state: "missing",
      root: %{
        attrs: %{
          "id" => "dashboard-widget-inspector",
          "data-widget-inspect-state" => "missing"
        }
      },
      missing: %{
        class:
          "rounded border border-base-300/70 bg-base-100/40 px-2 py-2 text-xs text-base-content/60",
        text: "This widget is no longer on the dashboard."
      }
    }
  end

  def inspect_panel_presentation(inspect) when is_map(inspect) do
    %{
      state: "ready",
      root: %{
        attrs: %{
          "id" => "dashboard-widget-inspector",
          "class" => "space-y-4",
          "data-widget-inspect-placement" => inspect.placement_id,
          "data-widget-inspect-state" => "ready"
        }
      },
      header: inspect_header_presentation(inspect),
      download: download_presentation(inspect),
      stats: stats_presentation(inspect.stats),
      table: table_presentation(inspect)
    }
  end

  defp inspect_header_presentation(inspect) do
    series_count = length(inspect.series)

    %{
      class: "space-y-1",
      badges_class: "flex flex-wrap items-center gap-2",
      type_badge: %{
        class: "badge badge-xs badge-outline",
        text: "Time series"
      },
      series_badge: %{
        attrs: %{"data-widget-inspect-series-count" => series_count},
        class: "badge badge-xs",
        text: "#{series_count} series"
      },
      rows_badge: %{
        attrs: %{"data-widget-inspect-row-total" => inspect.row_count_total},
        class: "badge badge-xs",
        text: "#{inspect.row_count_total} rows"
      },
      time_range: time_range_presentation(inspect.time_range),
      capped: capped_presentation(inspect)
    }
  end

  defp time_range_presentation(nil), do: nil

  defp time_range_presentation({from_ms, to_ms}) do
    %{
      class: "font-mono text-[0.68rem] text-base-content/60",
      text:
        "#{WidgetInspectModel.iso_timestamp(from_ms)} to #{WidgetInspectModel.iso_timestamp(to_ms)}"
    }
  end

  defp capped_presentation(%{capped?: capped?}) when capped? in [false, nil], do: nil

  defp capped_presentation(inspect) do
    %{
      id: "dashboard-widget-inspect-capped",
      class: "text-[0.68rem] text-base-content/60",
      text:
        "Showing latest #{length(inspect.rows)} of #{inspect.row_count_total} rows. The CSV download contains the full window."
    }
  end

  defp download_presentation(inspect) do
    %{
      component: "CsvDownloadButton",
      host: %{
        id: "dashboard-widget-inspect-download-component"
      },
      props: %{
        csv: inspect.csv,
        filename: csv_filename(inspect),
        disabled: inspect.row_count_total == 0
      }
    }
  end

  defp stats_presentation(stats) do
    %{
      attrs: %{"data-widget-inspect-stats" => ""},
      class: "space-y-2",
      heading: %{class: "hud-label", text: "Stats"},
      rows: Enum.map(stats, &stat_presentation/1),
      empty: %{
        visible: stats == [],
        class: "text-xs text-base-content/60",
        text: "No series resolved."
      }
    }
  end

  defp stat_presentation(stat) do
    %{
      attrs: %{"data-widget-inspect-stat" => stat.label},
      class:
        "grid grid-cols-[minmax(0,1fr)_repeat(5,minmax(3rem,auto))] items-baseline gap-x-3 rounded border border-base-300/70 px-2 py-1 text-xs",
      label: %{
        class: "truncate font-mono text-base-content/80",
        text: to_string(stat.label),
        title: to_string(stat.label),
        unit: unit_suffix(stat.unit),
        unit_class: "text-base-content/60"
      },
      values:
        Enum.map(
          [
            {"count", stat.count},
            {"min", stat.min},
            {"max", stat.max},
            {"mean", stat.mean},
            {"last", stat.last}
          ],
          &stat_value_presentation/1
        )
    }
  end

  defp stat_value_presentation({label, value}) do
    %{
      class: "text-right",
      label: %{
        class: "block text-[0.6rem] uppercase tracking-wide text-base-content/50",
        text: label
      },
      value: %{
        class: "block font-mono text-base-content/80",
        text: format_number(value)
      }
    }
  end

  defp table_presentation(inspect) do
    %{
      attrs: %{"data-widget-inspect-table" => ""},
      class: "space-y-2",
      heading: %{class: "hud-label", text: "Data"},
      scroll_class: "max-h-[28rem] overflow-auto rounded border border-base-300/70",
      table_class: "table table-xs",
      time_header: %{class: "whitespace-nowrap", text: "Time (UTC)"},
      series_headers: Enum.map(inspect.series, &series_header_presentation/1),
      rows: Enum.map(inspect.rows, &row_presentation/1),
      empty: %{
        visible: inspect.rows == [],
        colspan: length(inspect.series) + 1,
        class: "text-base-content/60",
        text: "No samples in the current window."
      }
    }
  end

  defp series_header_presentation(series) do
    %{
      class: "whitespace-nowrap text-right",
      text: to_string(series.label),
      unit: unit_suffix(series.unit),
      unit_class: "text-base-content/50"
    }
  end

  defp row_presentation(row) do
    %{
      timestamp: %{
        class: "whitespace-nowrap font-mono text-[0.68rem] text-base-content/70",
        text: WidgetInspectModel.iso_timestamp(row.timestamp_ms)
      },
      values:
        Enum.map(row.values, fn value ->
          %{
            class: "text-right font-mono text-[0.68rem]",
            text: format_number(value)
          }
        end)
    }
  end

  defp csv_filename(inspect) do
    slug =
      (inspect.title || "widget")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    "#{slug}-inspect.csv"
  end

  defp unit_suffix(unit) when unit in [false, nil], do: nil
  defp unit_suffix(unit), do: " (#{unit})"

  defp format_number(nil), do: "—"
  defp format_number(value), do: to_string(value)
end
