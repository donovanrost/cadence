defmodule CadenceWeb.OpsDashboardShowLive.WidgetInspectPanelComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.WidgetInspectModel

  attr :inspect, :map, default: nil

  def inspect_panel(assigns) do
    ~H"""
    <section
      :if={@inspect == nil}
      id="dashboard-widget-inspector"
      data-widget-inspect-state="missing"
    >
      <p class="rounded border border-base-300/70 bg-base-100/40 px-2 py-2 text-xs text-base-content/60">
        This widget is no longer on the dashboard.
      </p>
    </section>
    <section
      :if={@inspect != nil}
      id="dashboard-widget-inspector"
      data-widget-inspect-placement={@inspect.placement_id}
      data-widget-inspect-state="ready"
      class="space-y-4"
    >
      <.inspect_header inspect={@inspect} />
      <.download_button inspect={@inspect} />
      <.stats_strip stats={@inspect.stats} />
      <.data_table inspect={@inspect} />
    </section>
    """
  end

  attr :inspect, :map, required: true

  defp inspect_header(assigns) do
    ~H"""
    <div class="space-y-1">
      <div class="flex flex-wrap items-center gap-2">
        <span class="badge badge-xs badge-outline">Time series</span>
        <span class="badge badge-xs" data-widget-inspect-series-count={length(@inspect.series)}>
          {length(@inspect.series)} series
        </span>
        <span class="badge badge-xs" data-widget-inspect-row-total={@inspect.row_count_total}>
          {@inspect.row_count_total} rows
        </span>
      </div>
      <p :if={@inspect.time_range} class="font-mono text-[0.68rem] text-base-content/60">
        {WidgetInspectModel.iso_timestamp(elem(@inspect.time_range, 0))} to {WidgetInspectModel.iso_timestamp(
          elem(@inspect.time_range, 1)
        )}
      </p>
      <p
        :if={@inspect.capped?}
        id="dashboard-widget-inspect-capped"
        class="text-[0.68rem] text-base-content/60"
      >
        Showing latest {length(@inspect.rows)} of {@inspect.row_count_total} rows. The CSV download
        contains the full window.
      </p>
    </div>
    """
  end

  attr :inspect, :map, required: true

  defp download_button(assigns) do
    ~H"""
    <button
      id="dashboard-widget-inspect-download"
      type="button"
      phx-hook="CsvDownload"
      data-csv={@inspect.csv}
      data-filename={csv_filename(@inspect)}
      disabled={@inspect.row_count_total == 0}
      class="btn btn-sm btn-outline justify-start"
    >
      <.icon name="hero-arrow-down-tray" class="h-4 w-4" /> Download CSV
    </button>
    """
  end

  attr :stats, :list, required: true

  defp stats_strip(assigns) do
    ~H"""
    <section class="space-y-2" data-widget-inspect-stats>
      <h3 class="hud-label">Stats</h3>
      <div
        :for={stat <- @stats}
        class="grid grid-cols-[minmax(0,1fr)_repeat(5,minmax(3rem,auto))] items-baseline gap-x-3 rounded border border-base-300/70 px-2 py-1 text-xs"
        data-widget-inspect-stat={stat.label}
      >
        <span class="truncate font-mono text-base-content/80" title={stat.label}>
          {stat.label}<span :if={stat.unit} class="text-base-content/60"> ({stat.unit})</span>
        </span>
        <.stat_value label="count" value={stat.count} />
        <.stat_value label="min" value={stat.min} />
        <.stat_value label="max" value={stat.max} />
        <.stat_value label="mean" value={stat.mean} />
        <.stat_value label="last" value={stat.last} />
      </div>
      <p :if={@stats == []} class="text-xs text-base-content/60">No series resolved.</p>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat_value(assigns) do
    ~H"""
    <span class="text-right">
      <span class="block text-[0.6rem] uppercase tracking-wide text-base-content/50">{@label}</span>
      <span class="block font-mono text-base-content/80">{format_number(@value)}</span>
    </span>
    """
  end

  attr :inspect, :map, required: true

  defp data_table(assigns) do
    ~H"""
    <section class="space-y-2" data-widget-inspect-table>
      <h3 class="hud-label">Data</h3>
      <div class="max-h-[28rem] overflow-auto rounded border border-base-300/70">
        <%!-- Hand-rolled table markup (mirrors <.table>): the component's
        column slots cannot be generated for a dynamic series list. --%>
        <table class="table table-xs">
          <thead>
            <tr>
              <th class="whitespace-nowrap">Time (UTC)</th>
              <th :for={series <- @inspect.series} class="whitespace-nowrap text-right">
                {series.label}<span :if={series.unit} class="text-base-content/50"> ({series.unit})</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@inspect.rows == []}>
              <td colspan={length(@inspect.series) + 1} class="text-base-content/60">
                No samples in the current window.
              </td>
            </tr>
            <tr :for={row <- @inspect.rows}>
              <td class="whitespace-nowrap font-mono text-[0.68rem] text-base-content/70">
                {WidgetInspectModel.iso_timestamp(row.timestamp_ms)}
              </td>
              <td :for={value <- row.values} class="text-right font-mono text-[0.68rem]">
                {format_number(value)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp csv_filename(inspect) do
    slug =
      (inspect.title || "widget")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    "#{slug}-inspect.csv"
  end

  defp format_number(nil), do: "—"
  defp format_number(value), do: to_string(value)
end
