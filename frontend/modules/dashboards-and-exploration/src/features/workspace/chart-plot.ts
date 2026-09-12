import uPlot from "uplot";
import type { ChartSurface } from "./chart-surface";

/** Owns uPlot creation, options and range-selection listeners. */
export class ChartPlot {
  private rangeSelectionOverlay: Element | null = null;
  private handleRangeSelection: (() => void) | null = null;
  private rangeSelectionTimer: ReturnType<typeof setTimeout> | undefined;
  constructor(
    private readonly surface: ChartSurface,
    private readonly cursor: (plot: uPlot) => void,
  ) {}
  mount() {
    this.surface.plot = new uPlot(
      this.chartOptions(),
      this.surface.model.plotData(),
      this.surface.el,
    );
    this.installRangeSelection();
  }
  destroy() {
    clearTimeout(this.rangeSelectionTimer);
    if (this.rangeSelectionOverlay && this.handleRangeSelection)
      this.rangeSelectionOverlay.removeEventListener("mouseup", this.handleRangeSelection);
    this.rangeSelectionOverlay = null;
    this.handleRangeSelection = null;
    this.surface.rangeSelectionInFlight = false;
    this.surface.plot?.destroy();
    this.surface.plot = null;
  }
  chartOptions(): uPlot.Options {
    // Derive the series color from the surrounding theme instead of
    // hardcoding palette values.
    const palette = this.surface.chartPalette();
    const axis = {
      stroke: `${this.surface.themeColor("--chart-label-62")}`,
      grid: { stroke: `${this.surface.themeColor("--chart-label-8")}` },
      ticks: { stroke: `${this.surface.themeColor("--chart-label-12")}` },
      font: this.surface.themeColor("--chart-font"),
    };

    return {
      ...this.surface.chartSize(),
      legend: { show: false },
      cursor: {
        drag: { x: this.surface.el.dataset.editMode !== "true", y: false },
        sync: { key: this.surface.el.dataset.correlationGroup || "cadence-dashboard-time" },
      },
      hooks: {
        setCursor: [(u) => this.cursor(u)],
      },
      scales: this.chartScales(),
      series: [{}].concat(this.chartSeriesOptions(palette)),
      bands: this.chartBands(palette),
      axes: this.chartAxes(axis),
    };
  }

  chartScales(): uPlot.Scales {
    return this.surface.model.unitGroups().reduce(
      (scales, unit) => ({
        ...scales,
        [this.surface.model.unitScaleKey(unit)]: {},
      }),
      {
        x: {
          time: true,
          range: (_u, dataMin, dataMax) => this.surface.model.chartXRange(dataMin, dataMax),
        },
      },
    );
  }

  chartAxes(axis: uPlot.Axis): uPlot.Axis[] {
    const unitGroups = this.surface.model.unitGroups();

    return [
      axis,
      ...unitGroups.map((unit, index) => ({
        ...axis,
        scale: this.surface.model.unitScaleKey(unit),
        ...(unit || this.surface.el.dataset.unit
          ? { label: unit || this.surface.el.dataset.unit || "" }
          : {}),
        side: index % 2 === 0 ? (3 as const) : (1 as const),
      })),
    ];
  }

  chartSeriesOptions(palette: string[]): uPlot.Series[] {
    return this.surface.model.plotSeries.map((entry) => {
      const series = this.surface.model.seriesList[entry.seriesIndex];
      if (!series) throw Error("Plot series has no source series");
      const color =
        palette[entry.seriesIndex % palette.length] ??
        this.surface.themeColor("--chart-series-primary");

      if (entry.kind === "line") {
        const compare = series.role === "compare";

        return {
          label: series.label || series.id || this.surface.model.widgetId,
          show: this.surface.model.seriesVisible(series),
          scale: this.surface.model.unitScaleKey(series.unit),
          stroke: compare ? this.surface.compareSeriesColor(color) : color,
          width: compare ? Math.max(this.lineWidthValue() - 0.4, 0.8) : this.lineWidthValue(),
          ...(compare ? { dash: [6, 4] } : {}),
          spanGaps: this.surface.model.spanGaps,
          gaps: (plot, seriesIndex, idx0, idx1, nullGaps) =>
            this.surface.model.seriesGaps(plot, seriesIndex, idx0, idx1, nullGaps),
          ...(this.surface.model.fillOpacity > 0 ? { fill: this.seriesFillColor(color) } : {}),
          points: { show: this.surface.model.showPoints, size: 4 },
        };
      }

      return {
        label: `${series.label || series.id || this.surface.model.widgetId} ${entry.kind === "envelope_low" ? "min" : "max"}`,
        show: this.surface.model.seriesVisible(series),
        scale: this.surface.model.unitScaleKey(series.unit),
        stroke: `${this.surface.themeColor("--chart-shadow-0")}`,
        width: 0,
        points: { show: false },
        spanGaps: false,
        gaps: (plot, seriesIndex, idx0, idx1, nullGaps) =>
          this.surface.model.seriesGaps(plot, seriesIndex, idx0, idx1, nullGaps),
      };
    });
  }

  lineWidthValue() {
    if (this.surface.model.lineWidth === "thin") return 1;
    if (this.surface.model.lineWidth === "bold") return 3;
    return 2;
  }

  seriesFillColor(color: string) {
    const alpha = this.surface.model.fillOpacity / 100;
    if (color.startsWith("rgba(")) {
      const parts = color.slice(5, -1).split(",");
      if (parts.length >= 3) return `rgba(${parts.slice(0, 3).join(",")}, ${alpha})`;
    }
    return `rgba(${this.surface.themeColor("--chart-color-selection")}, ${alpha})`;
  }

  installRangeSelection() {
    if (!this.surface.chart || this.surface.el.dataset.editMode === "true") return;

    const overlay = this.surface.el.querySelector(".u-over");
    if (!overlay) return;

    if (this.rangeSelectionOverlay && this.handleRangeSelection) {
      this.rangeSelectionOverlay.removeEventListener("mouseup", this.handleRangeSelection);
    }

    this.rangeSelectionOverlay = overlay;
    this.handleRangeSelection = () => {
      const selection = this.surface.chart.select;
      if (!selection || selection.width < 8) return;

      const fromSeconds = this.surface.chart.posToVal(selection.left, "x");
      const toSeconds = this.surface.chart.posToVal(selection.left + selection.width, "x");
      if (!Number.isFinite(fromSeconds) || !Number.isFinite(toSeconds)) return;

      const from = new Date(Math.min(fromSeconds, toSeconds) * 1000).toISOString();
      const to = new Date(Math.max(fromSeconds, toSeconds) * 1000).toISOString();
      this.surface.rangeSelectionInFlight = true;
      this.surface.pushEvent("set_chart_time_range", { from, to });
      this.surface.chart.setSelect({ left: 0, width: 0, top: 0, height: 0 }, false);
      clearTimeout(this.rangeSelectionTimer);
      this.rangeSelectionTimer = setTimeout(() => {
        this.surface.rangeSelectionInFlight = false;
      }, 0);
    };
    overlay.addEventListener("mouseup", this.handleRangeSelection);
  }

  chartBands(palette: string[]): uPlot.Band[] {
    const bands: uPlot.Band[] = [];
    const plotSeries = this.surface.model.plotSeries;

    plotSeries.forEach((entry, index) => {
      if (entry.kind !== "envelope_high") return;
      if (!this.surface.model.seriesVisible(this.surface.model.seriesList[entry.seriesIndex]))
        return;

      const lowIndex = plotSeries.findIndex(
        (candidate) =>
          candidate.kind === "envelope_low" && candidate.seriesIndex === entry.seriesIndex,
      );
      if (lowIndex < 0) return;

      const color =
        palette[entry.seriesIndex % palette.length] ??
        this.surface.themeColor("--chart-series-primary");
      bands.push({
        series: [index + 1, lowIndex + 1],
        fill: () => this.envelopeBandColor(color),
      });
    });

    return bands;
  }

  envelopeBandColor(color: string) {
    if (color.startsWith("rgba(")) {
      const parts = color.slice(5, -1).split(",");
      if (parts.length >= 3) return `rgba(${parts.slice(0, 3).join(",")}, 0.16)`;
    }

    return `${this.surface.themeColor("--chart-selection-14")}`;
  }
}
