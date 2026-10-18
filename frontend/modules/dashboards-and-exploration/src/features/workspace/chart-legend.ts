import type uPlot from "uplot";
import type { ChartSeries } from "./chart-input";
import type { ChartSurface } from "./chart-surface";

/** Owns the legend and shared cursor tooltip; legend controls request a coordinated plot rebuild. */
export class ChartLegend {
  readonly legendLayer: HTMLDivElement;
  readonly tooltipLayer: HTMLDivElement;
  constructor(private readonly surface: ChartSurface) {
    this.legendLayer = this.buildLegendLayer();
    this.tooltipLayer = this.buildTooltipLayer();
  }
  buildLegendLayer() {
    const layer = document.createElement("div");
    layer.className = "telemetry-chart-legend";
    layer.dataset.chartLegend = "series";
    Object.assign(layer.style, {
      position: "absolute",
      left: "0",
      right: "0",
      bottom: "0",
      minHeight: `${this.surface.model.legendHeight()}px`,
      display: "flex",
      flexWrap: "wrap",
      alignItems: "center",
      justifyContent: "flex-start",
      gap: "10px",
      overflow: "hidden",
      padding: "4px 8px",
      pointerEvents: "none",
      zIndex: "5",
    });
    return layer;
  }

  buildTooltipLayer() {
    const layer = document.createElement("div");
    layer.dataset.chartSharedTooltip = "true";
    Object.assign(layer.style, {
      position: "absolute",
      left: "0",
      top: "0",
      display: "none",
      maxWidth: "55%",
      border: `1px solid ${this.surface.themeColor("--chart-label-20")}`,
      borderRadius: "2px",
      background: `${this.surface.themeColor("--chart-tooltip-surface-96")}`,
      boxShadow: `0 4px 12px ${this.surface.themeColor("--chart-shadow-35")}`,
      color: `${this.surface.themeColor("--chart-foreground-94")}`,
      font: this.surface.themeColor("--chart-font"),
      lineHeight: "1.45",
      padding: "6px 8px",
      pointerEvents: "none",
      zIndex: "6",
    });
    return layer;
  }

  renderSharedTooltip(u: uPlot) {
    if (!this.tooltipLayer || !this.surface.model.sharedTooltip) return;

    const index = u && u.cursor && u.cursor.idx;
    if (
      index == null ||
      !Number.isInteger(index) ||
      !Number.isFinite(this.surface.model.xs[index])
    ) {
      this.tooltipLayer.style.display = "none";
      return;
    }

    const rows = this.surface.model.seriesList.flatMap((series, seriesIndex) => {
      if (!this.surface.model.seriesVisible(series)) return [];
      const value = this.surface.model.seriesYs[seriesIndex]?.[index];
      if (!Number.isFinite(value)) return [];
      return [`${series.label || series.id}: ${value}${series.unit ? ` ${series.unit}` : ""}`];
    });

    if (rows.length === 0) {
      this.tooltipLayer.style.display = "none";
      return;
    }

    const seconds = this.surface.model.xs[index];
    if (seconds === undefined) return;
    const timestamp = new Date(seconds * 1000).toISOString();
    this.tooltipLayer.textContent = `${timestamp}\n${rows.join("  ·  ")}`;
    this.tooltipLayer.style.whiteSpace = "pre-wrap";
    this.tooltipLayer.style.display = "block";
    this.positionSharedTooltip(u);
  }

  positionSharedTooltip(u: uPlot) {
    const cursorLeft = u?.cursor?.left;
    const cursorTop = u?.cursor?.top;
    if (
      cursorLeft === undefined ||
      cursorTop === undefined ||
      !Number.isFinite(cursorLeft) ||
      !Number.isFinite(cursorTop)
    )
      return;

    const plotBounds = this.surface.chartPlotBounds();
    const chartWidth = this.surface.el.clientWidth || plotBounds.left + plotBounds.width;
    const chartHeight = this.surface.el.clientHeight || plotBounds.top + plotBounds.height;
    const contentBottom = Math.max(0, chartHeight - this.surface.model.legendHeight());
    const tooltipWidth = this.tooltipLayer.offsetWidth || 160;
    const tooltipHeight = this.tooltipLayer.offsetHeight || 48;
    const pointerLeft = plotBounds.left + cursorLeft;
    const pointerTop = plotBounds.top + cursorTop;
    const gap = 12;
    const inset = 6;

    const rightLeft = pointerLeft + gap;
    const leftLeft = pointerLeft - gap - tooltipWidth;
    const belowTop = pointerTop + gap;
    const aboveTop = pointerTop - gap - tooltipHeight;
    const placeRight = rightLeft + tooltipWidth <= chartWidth - inset;
    const placeBelow = belowTop + tooltipHeight <= contentBottom - inset;
    const maxLeft = Math.max(inset, chartWidth - tooltipWidth - inset);
    const maxTop = Math.max(inset, contentBottom - tooltipHeight - inset);
    const left = Math.min(Math.max(placeRight ? rightLeft : leftLeft, inset), maxLeft);
    const top = Math.min(Math.max(placeBelow ? belowTop : aboveTop, inset), maxTop);

    this.tooltipLayer.style.left = `${Math.round(left)}px`;
    this.tooltipLayer.style.top = `${Math.round(top)}px`;
    this.tooltipLayer.dataset.chartTooltipPlacementX = placeRight ? "right" : "left";
    this.tooltipLayer.dataset.chartTooltipPlacementY = placeBelow ? "below" : "above";
  }

  renderLegend() {
    if (!this.legendLayer) return;

    this.legendLayer.replaceChildren();
    const visible = this.surface.model.legendVisible();
    this.legendLayer.dataset.chartLegendVisible = visible ? "true" : "false";
    this.legendLayer.style.display = visible ? "flex" : "none";
    if (!visible) return;

    const sourceUnitGroups = this.surface.model.sourceUnitGroups();

    const palette = this.surface.chartPalette();

    if (sourceUnitGroups.length > 1) {
      this.legendLayer.appendChild(this.axisModeButton());
    }

    this.surface.model.seriesList.forEach((series, index) => {
      const item = document.createElement("button");
      const visible = this.surface.model.seriesVisible(series);

      item.type = "button";
      item.dataset.chartLegendItem = series.id || `${index}`;
      item.dataset.chartLegendUnit = series.unit || "";
      item.dataset.chartLegendScale = this.surface.model.unitScaleKey(series.unit);
      item.dataset.chartSeriesRole = series.role || "primary";
      item.dataset.chartSeriesHidden = visible ? "false" : "true";
      item.setAttribute("aria-pressed", visible ? "true" : "false");
      item.title = `${series.label || series.id}${series.unit ? ` (${series.unit})` : ""}`;
      item.setAttribute("aria-label", `${visible ? "Hide" : "Show"} ${item.title}`);

      const swatch = document.createElement("span");
      Object.assign(swatch.style, {
        width: "14px",
        height: "2px",
        borderRadius: "1px",
        background: this.surface.seriesLegendColor(series, index, palette),
        flex: "0 0 auto",
      });

      if (series.role === "compare") {
        swatch.style.borderRadius = "0";
        swatch.style.height = "2px";
        swatch.style.borderTop = `1px dashed ${this.surface.seriesLegendColor(series, index, palette)}`;
        swatch.style.background = "transparent";
      }

      const label = document.createElement("span");
      label.textContent = this.legendLabel(series);
      Object.assign(label.style, {
        overflow: "hidden",
        textOverflow: "ellipsis",
        whiteSpace: "nowrap",
      });

      Object.assign(item.style, {
        display: "inline-flex",
        alignItems: "center",
        gap: "4px",
        maxWidth: "220px",
        border: "0",
        borderRadius: "2px",
        background: "transparent",
        color: visible
          ? `${this.surface.themeColor("--chart-label-90")}`
          : `${this.surface.themeColor("--chart-muted-62")}`,
        cursor: "pointer",
        font: "500 11px ui-sans-serif, system-ui, sans-serif",
        lineHeight: "1",
        padding: "2px 0",
        opacity: visible ? "1" : "0.58",
        pointerEvents: "auto",
      });

      if (!visible) {
        label.style.textDecoration = "line-through";
      }

      item.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        this.toggleSeries(series.id);
      });

      item.appendChild(swatch);
      item.appendChild(label);
      this.legendLayer.appendChild(item);
    });
  }

  axisModeButton() {
    const button = document.createElement("button");
    const nextMode = this.surface.model.axisMode === "unit" ? "shared" : "unit";

    button.type = "button";
    button.dataset.chartAxisMode = this.surface.model.axisMode;
    button.title =
      this.surface.model.axisMode === "unit"
        ? "Switch chart to one shared value axis"
        : "Group chart axes by engineering unit";
    button.setAttribute("aria-label", button.title);
    button.textContent = this.surface.model.axisMode === "unit" ? "Axis: unit" : "Axis: shared";
    Object.assign(button.style, {
      border: "0",
      borderRadius: "2px",
      background: "transparent",
      color: `${this.surface.themeColor("--chart-label-72")}`,
      cursor: "pointer",
      font: "500 11px ui-sans-serif, system-ui, sans-serif",
      lineHeight: "1",
      padding: "2px 0",
      pointerEvents: "auto",
    });

    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      this.surface.model.axisMode = nextMode;
      this.surface.rebuild();
    });

    return button;
  }

  toggleSeries(seriesId: string) {
    if (!seriesId) return;

    if (this.surface.model.hiddenSeriesIds.has(seriesId)) {
      this.surface.model.hiddenSeriesIds.delete(seriesId);
      this.surface.rebuild();
      return;
    }

    if (this.surface.model.visibleSeriesCount() <= 1) return;

    this.surface.model.hiddenSeriesIds.add(seriesId);
    this.surface.rebuild();
  }

  legendLabel(series: ChartSeries) {
    const label = series.label || series.id || this.surface.model.widgetId;
    return series.unit ? `${label} [${series.unit}]` : label;
  }
}
