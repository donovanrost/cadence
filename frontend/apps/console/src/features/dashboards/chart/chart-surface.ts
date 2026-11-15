import uPlot from "uplot";
import type { ChartModel } from "./chart-model.ts";
import type { ChartAction } from "./chart-runtime.ts";
import type { ChartSeries } from "./chart-input.ts";
import type { ChartInterval } from "./chart-markers.ts";
import type { PointMetadata } from "./chart-points.ts";

/** Shared plot geometry, themed colors and native action payloads for render-only layers. */
export class ChartSurface {
  plot: uPlot | null = null;
  themeStyles: CSSStyleDeclaration | undefined;
  rangeSelectionInFlight = false;
  constructor(
    readonly el: HTMLElement,
    public model: ChartModel,
    readonly pushEvent: (action: ChartAction, payload: Record<string, unknown>) => void,
    readonly rebuild: () => void,
  ) {}
  get chart(): uPlot {
    if (!this.plot) throw Error("Chart surface used outside its mounted lifetime");
    return this.plot;
  }
  themeColor(token: string) {
    this.themeStyles ??= getComputedStyle(this.el);
    const value = this.themeStyles.getPropertyValue(token).trim();
    if (!value) throw new Error(`Missing Cadence chart token ${token}`);
    return value;
  }

  pointDataLinkPayload(metadata: PointMetadata, timestampMs: number) {
    const target =
      metadata.target || metadata.link_target || (metadata.sample_id ? "telemetry_sample" : null);
    const targetId = metadata.target_id || metadata.link_target_id || metadata.sample_id;

    return this.compactPayload({
      "link-id": metadata.link_id,
      "placement-id": this.model.placementId,
      target,
      "target-id": targetId,
      "timestamp-ms": timestampMs,
      "series-role": metadata.series_role,
      "compare-of": metadata.compare_of,
      realm: this.el.dataset.dataRealm,
      "data-view": metadata.data_view,
      "data-source-id": metadata.data_source_id || this.el.dataset.dataSourceId,
      "source-binding-id": metadata.source_binding_id || this.el.dataset.sourceBindingId,
      "time-mode": this.el.dataset.timeMode,
      "time-axis": metadata.time_axis || this.el.dataset.timeAxis,
      "replay-run-id": this.el.dataset.replayRunId,
    });
  }

  /** A mark's data link. The console's markers carry no data scope of their own (no realm/view). */
  markerDataLinkPayload(
    linkId: string,
    target: string,
    targetId: string | null,
    timestampMs: number,
  ) {
    return this.compactPayload({
      "link-id": linkId,
      "placement-id": this.model.placementId,
      target,
      "target-id": targetId,
      "timestamp-ms": timestampMs,
    });
  }

  compactPayload(payload: Record<string, unknown>) {
    return Object.fromEntries(
      Object.entries(payload).filter(
        ([, value]) => value !== null && value !== undefined && value !== "",
      ),
    );
  }

  chartPlotBounds() {
    const bbox = this.plot?.bbox;
    const reportedRatio = Number(uPlot.pxRatio || globalThis.devicePixelRatio || 1);
    const pixelRatio = Number.isFinite(reportedRatio) && reportedRatio > 0 ? reportedRatio : 1;

    return {
      left: Number(bbox?.left || 0) / pixelRatio,
      top: Number(bbox?.top || 0) / pixelRatio,
      width: Number(bbox?.width || this.el.clientWidth * pixelRatio) / pixelRatio,
      height: Number(bbox?.height || this.el.clientHeight * pixelRatio) / pixelRatio,
    };
  }

  chartXDomain() {
    const scale = this.plot?.scales.x;

    return {
      min: scale?.min ?? this.model.xs[0] ?? Number.NaN,
      max: scale?.max ?? this.model.xs.at(-1) ?? Number.NaN,
    };
  }

  markerLeft(timestampMs: number) {
    const plotLeft = this.chart.bbox.left || 0;
    return plotLeft + this.chart.valToPos(timestampMs / 1000, "x", false);
  }

  intervalBounds(marker: ChartInterval) {
    // Drawn on an empty range too (ux: a pass with no samples is what an operator needs to see).
    if (!marker.starts_at_ms) return null;

    const plotBounds = this.chartPlotBounds();
    const plotLeft = plotBounds.left;
    const plotRight = plotLeft + plotBounds.width;
    const startSeconds = marker.starts_at_ms / 1000;
    const xDomain = this.chartXDomain();
    const endSeconds = marker.ends_at_ms
      ? marker.ends_at_ms / 1000
      : (this.model.xs.at(-1) ?? xDomain.max);
    if (!Number.isFinite(endSeconds)) return null;

    if (endSeconds < xDomain.min || startSeconds > xDomain.max) return null;

    const left = Math.max(plotLeft, plotLeft + this.chart.valToPos(startSeconds, "x", false));
    const right = Math.min(plotRight, plotLeft + this.chart.valToPos(endSeconds, "x", false));
    const width = Math.max(2, right - left);

    return { left, width };
  }

  chartSize() {
    // Keep Grafana-style legends in a fixed footer rather than layering them
    // over the plot or making the panel itself scroll.
    const containerHeight = this.el.clientHeight || 180;
    return {
      width: this.el.clientWidth,
      height: Math.max(containerHeight - this.model.legendHeight(), 80),
    };
  }

  chartPalette() {
    const accent = getComputedStyle(this.el).color || this.themeColor("--chart-series-primary");
    return [
      accent,
      `${this.themeColor("--chart-current-92")}`,
      `${this.themeColor("--chart-warning-90")}`,
      `${this.themeColor("--chart-critical-88")}`,
      `${this.themeColor("--chart-compare-90")}`,
    ];
  }

  seriesLegendColor(series: ChartSeries | undefined, index: number, palette: string[]) {
    const color = palette[index % palette.length] ?? this.themeColor("--chart-series-primary");
    return series && series.role === "compare" ? this.compareSeriesColor(color) : color;
  }

  compareSeriesColor(_color: string) {
    return `${this.themeColor("--chart-text-secondary-76")}`;
  }
}
