import uPlot from "uplot";
import type { ChartModel } from "./chart-model";
import type { ChartAction } from "./chart-runtime";
import type { ChartMarker, ChartSeries } from "./chart-input";
import type { PointMetadata } from "./chart-points";

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

  markerDataLinkPayload(
    marker: ChartMarker,
    target: string | null | undefined,
    targetId: string | null | undefined,
    timestampMs: number | null | undefined,
  ) {
    return this.compactPayload({
      "link-id": marker.link_id,
      "placement-id": this.model.placementId,
      target,
      "target-id": targetId,
      "timestamp-ms": timestampMs,
      realm: marker.requested_realm || marker.realm,
      "data-view": marker.requested_data_view || marker.data_view,
      "data-source-id": marker.requested_data_source_id || marker.data_source_id,
      "source-binding-id": marker.requested_source_binding_id || marker.source_binding_id,
      "time-mode": marker.time_mode,
      "time-axis": marker.time_axis,
      "replay-run-id": marker.replay_run_id,
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

  markerLeft(marker: ChartMarker) {
    const plotLeft = this.chart.bbox.left || 0;
    if (marker.timestamp_ms == null) return null;
    const x = marker.timestamp_ms / 1000;
    return plotLeft + this.chart.valToPos(x, "x", false);
  }

  intervalBounds(marker: ChartMarker) {
    if (!marker.starts_at_ms || this.model.xs.length === 0) return null;

    const plotBounds = this.chartPlotBounds();
    const plotLeft = plotBounds.left;
    const plotRight = plotLeft + plotBounds.width;
    const startSeconds = marker.starts_at_ms / 1000;
    const endSeconds = marker.ends_at_ms
      ? marker.ends_at_ms / 1000
      : this.model.xs[this.model.xs.length - 1];
    if (endSeconds === undefined) return null;
    const xDomain = this.chartXDomain();

    if (endSeconds < xDomain.min || startSeconds > xDomain.max) return null;

    const left = Math.max(plotLeft, plotLeft + this.chart.valToPos(startSeconds, "x", false));
    const right = Math.min(plotRight, plotLeft + this.chart.valToPos(endSeconds, "x", false));
    const width = Math.max(2, right - left);

    return { left, width };
  }

  markerColor(marker: ChartMarker) {
    if (marker.normalized_state === "red") return `${this.themeColor("--chart-critical-95")}`;
    return `${this.themeColor("--chart-caution-95")}`;
  }

  limitAnalysisBucketSelectionFill(marker: ChartMarker) {
    if (marker.normalized_state === "red") return `${this.themeColor("--chart-critical-20")}`;
    return `${this.themeColor("--chart-caution-18")}`;
  }

  limitIntervalColor(_marker: ChartMarker) {
    return `${this.themeColor("--chart-caution-58")}`;
  }

  eventColor(marker: ChartMarker) {
    if (marker.severity === "critical" || marker.severity === "error")
      return `${this.themeColor("--chart-critical-90")}`;
    if (marker.severity === "warning" || marker.status === "canceled")
      return `${this.themeColor("--chart-warning-90")}`;
    if (marker.marker_type === "retention_gap") return this.retentionGapColor(marker);
    if (marker.marker_type === "source_binding_interval")
      return this.sourceBindingIntervalColor(marker);
    if (
      marker.marker_type === "source_watermark_cursor" ||
      marker.marker_type === "source_watermark_event"
    )
      return this.sourceWatermarkCursorColor(marker);
    if (
      marker.marker_type === "telemetry_revision_range" ||
      marker.marker_type === "telemetry_revision_decision" ||
      marker.marker_type === "telemetry_backfill_lifecycle"
    )
      return this.telemetryRevisionColor(marker);
    return `${this.themeColor("--chart-revision-86")}`;
  }

  retentionGapColor(_marker: ChartMarker) {
    return `${this.themeColor("--chart-critical-76")}`;
  }

  sourceBindingIntervalColor(_marker: ChartMarker) {
    return `${this.themeColor("--chart-revision-68")}`;
  }

  sourceWatermarkCursorColor(marker: ChartMarker) {
    if (marker.freshness_state === "stale") return `${this.themeColor("--chart-warning-82")}`;
    if (marker.freshness_state === "retention_gap")
      return `${this.themeColor("--chart-critical-78")}`;
    return `${this.themeColor("--chart-current-76")}`;
  }

  telemetryRevisionColor(marker: ChartMarker) {
    if (marker.revision_state === "backfill") return `${this.themeColor("--chart-backfill-72")}`;
    return `${this.themeColor("--chart-warning-78")}`;
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
