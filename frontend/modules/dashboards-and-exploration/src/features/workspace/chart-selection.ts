import type { ChartMarker } from "./chart-input";
import type { PointMetadata } from "./chart-points";
import type { ChartSurface } from "./chart-surface";

/** Owns point hit testing and selected evidence overlays. */
export class ChartSelection {
  readonly selectionLayer: HTMLDivElement;
  constructor(private readonly surface: ChartSurface) {
    this.selectionLayer = this.buildSelectionLayer();
  }
  openPointInspector(event: MouseEvent) {
    if (this.surface.rangeSelectionInFlight) return;
    const index = this.pointIndexFromEvent(event);
    if (index === null || index === undefined) return;

    const metadata = this.pointMetadataAt(index, event);
    if (!metadata.link_id) return;

    const timestamp = this.surface.model.xs[index];
    if (timestamp === undefined) return;
    this.surface.pushEvent(
      "open_data_link",
      this.surface.pointDataLinkPayload(metadata, Math.round(timestamp * 1000)),
    );
  }

  pointMetadataAt(index: number, event: MouseEvent): PointMetadata {
    const seriesMeta = this.surface.model.seriesPointMeta;
    const pointerTop = this.pointerTop(event);
    const candidates = [];

    for (let seriesIndex = 0; seriesIndex < seriesMeta.length; seriesIndex += 1) {
      const series = this.surface.model.seriesList[seriesIndex];
      if (!series || !this.surface.model.seriesVisible(series)) continue;

      const metadataByTime = seriesMeta[seriesIndex];
      const metadata = metadataByTime?.[index] ?? {};
      if (!metadata.link_id) continue;

      const value = this.surface.model.seriesYs[seriesIndex]?.[index];
      if (value === null || value === undefined) continue;

      const top =
        (this.surface.chart.bbox.top || 0) +
        this.surface.chart.valToPos(value, this.surface.model.unitScaleKey(series.unit), false);

      candidates.push({
        metadata,
        distance: pointerTop === null || Number.isNaN(top) ? 0 : Math.abs(top - pointerTop),
      });
    }

    candidates.sort((left, right) => left.distance - right.distance);
    return (candidates[0] && candidates[0].metadata) || {};
  }

  pointerTop(event: MouseEvent) {
    const overlay = this.surface.el.querySelector(".u-over");
    if (!overlay || !event) return null;

    const rect = overlay.getBoundingClientRect();
    const top = event.clientY - rect.top;
    if (top < 0 || top > rect.height) return null;

    return top;
  }

  pointIndexFromEvent(event: MouseEvent) {
    if (!this.surface.chart || this.surface.model.xs.length === 0) return null;

    const overlay = this.surface.el.querySelector(".u-over");
    if (!overlay) return this.surface.chart.cursor && this.surface.chart.cursor.idx;

    const rect = overlay.getBoundingClientRect();
    const left = event.clientX - rect.left;
    if (left < 0 || left > rect.width) return null;

    return this.surface.chart.posToIdx(left);
  }

  buildSelectionLayer() {
    const layer = document.createElement("div");
    layer.className = "telemetry-chart-selection";
    Object.assign(layer.style, {
      position: "absolute",
      inset: "0",
      bottom: `${this.surface.model.legendHeight()}px`,
      pointerEvents: "none",
      zIndex: "4",
    });
    return layer;
  }

  renderSelection() {
    if (!this.selectionLayer || !this.surface.chart) return;

    this.selectionLayer.replaceChildren();
    if (!this.surface.model.selectedRef) return;
    if (
      this.surface.model.selectedRef.placement_id &&
      this.surface.model.selectedRef.placement_id !== this.surface.model.placementId
    )
      return;

    this.renderSelectedTimeCursor();

    if (this.surface.model.selectedRef.target === "limit_event") {
      const marker = this.selectedLimitMarker();
      if (marker) this.renderSelectedLimit(marker);
    }

    if (this.surface.model.selectedRef.target === "limit_definition") {
      const marker = this.selectedLimitDefinitionMarker();
      if (marker) this.renderSelectedLimitDefinition(marker);
    }

    if (this.surface.model.selectedRef.target === "mission_event") {
      const marker = this.selectedEventMarker("mission_event");
      if (marker) this.renderSelectedEvent(marker);
    }

    if (this.surface.model.selectedRef.target === "telemetry_sample") {
      const selection = this.selectedPointIndex();
      if (selection) this.renderSelectedPoint(selection);
    }
  }

  selectedPointIndex() {
    const selected = this.surface.model.selectedRef;
    if (!selected) return null;
    for (
      let seriesIndex = 0;
      seriesIndex < this.surface.model.seriesPointMeta.length;
      seriesIndex += 1
    ) {
      if (!this.surface.model.seriesVisible(this.surface.model.seriesList[seriesIndex])) continue;

      const pointIndex = this.surface.model.seriesPointMeta[seriesIndex]?.findIndex((metadata) => {
        return (
          this.selectedPointMetadataMatchesSeries(metadata) &&
          (metadata.link_id === selected.link_id || metadata.sample_id === selected.target_id)
        );
      });

      if (pointIndex !== undefined && pointIndex >= 0) return { seriesIndex, pointIndex };
    }

    return null;
  }

  selectedPointMetadataMatchesSeries(metadata: PointMetadata) {
    const selected = this.surface.model.selectedRef;
    if (!selected) return false;
    if (!metadata) return false;

    if (selected.series_role && metadata.series_role !== selected.series_role) {
      return false;
    }

    if (selected.compare_of && metadata.compare_of !== selected.compare_of) {
      return false;
    }

    if (selected.data_view && metadata.data_view && metadata.data_view !== selected.data_view) {
      return false;
    }

    return true;
  }

  selectedLimitMarker() {
    const selected = this.surface.model.selectedRef;
    if (!selected) return null;
    return this.surface.model.limitMarkers.find((marker) => {
      if (marker.marker_type === "limit_definition_interval") return false;

      return marker.link_id === selected.link_id || marker.limit_event_id === selected.target_id;
    });
  }

  selectedLimitDefinitionMarker() {
    const selected = this.surface.model.selectedRef;
    if (!selected) return null;
    return this.surface.model.limitMarkers.find((marker) => {
      if (marker.marker_type !== "limit_definition_interval") return false;

      return (
        marker.link_id === selected.link_id ||
        marker.target_id === selected.target_id ||
        marker.limit_definition_id === selected.target_id
      );
    });
  }

  selectedEventMarker(target: string) {
    const selected = this.surface.model.selectedRef;
    if (!selected) return null;
    return this.surface.model.eventMarkers.find((marker) => {
      if (marker.target !== target) return false;

      return (
        marker.link_id === selected.link_id ||
        marker.target_id === selected.target_id ||
        marker.mission_event_id === selected.target_id ||
        marker.contact_id === selected.target_id
      );
    });
  }

  renderSelectedPoint(selection: { seriesIndex: number; pointIndex: number }) {
    const selected = this.surface.model.selectedRef;
    if (!selected) return;
    const series = this.surface.model.seriesList[selection.seriesIndex];
    const x = this.surface.model.xs[selection.pointIndex];
    const y = this.surface.model.seriesYs[selection.seriesIndex]?.[selection.pointIndex];
    if (!series || x === undefined || y == null) return;

    const left = (this.surface.chart.bbox.left || 0) + this.surface.chart.valToPos(x, "x", false);
    const top =
      (this.surface.chart.bbox.top || 0) +
      this.surface.chart.valToPos(y, this.surface.model.unitScaleKey(series.unit), false);
    if (Number.isNaN(left) || Number.isNaN(top)) return;

    const marker = document.createElement("div");
    marker.dataset.chartSelectionTarget = "telemetry sample";
    marker.dataset.chartSelectionRef = selected.link_id || "";
    marker.dataset.chartSelectionSeriesRole = selected.series_role || "primary";
    Object.assign(marker.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${top}px`,
      width: "12px",
      height: "12px",
      transform: "translate(-6px, -6px)",
      border:
        selected.series_role === "compare"
          ? `2px dashed ${this.surface.themeColor("--chart-text-secondary-95")}`
          : `2px solid ${this.surface.themeColor("--chart-selection-95")}`,
      borderRadius: "999px",
      background: `${this.surface.themeColor("--chart-backfill-18")}`,
      boxShadow: `0 0 0 1px ${this.surface.themeColor("--chart-shadow-35")}, 0 0 10px ${this.surface.themeColor("--chart-selection-75")}`,
    });
    this.selectionLayer.appendChild(marker);
  }

  renderSelectedTimeCursor() {
    const selected = this.surface.model.selectedRef;
    if (!selected) return;
    const left = this.selectedTimeCursorLeft();
    if (left === null || left === undefined || Number.isNaN(left)) return;

    const cursor = document.createElement("div");
    cursor.dataset.chartSelectionTarget = "selected time";
    cursor.dataset.chartSelectionRef = selected.link_id || "";
    cursor.dataset.chartSelectionTimestampMs = `${this.selectedTimestampMs()}`;
    Object.assign(cursor.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      width: "0",
      borderLeft: `1px dashed ${this.surface.themeColor("--chart-selection-68")}`,
      boxShadow: `0 0 8px ${this.surface.themeColor("--chart-selection-42")}`,
    });
    this.selectionLayer.appendChild(cursor);
  }

  selectedTimeCursorLeft() {
    const timestampMs = this.selectedTimestampMs();
    if (timestampMs === null || this.surface.model.xs.length === 0) return null;

    const x = timestampMs / 1000;
    const first = this.surface.model.xs[0],
      last = this.surface.model.xs.at(-1);
    if (first === undefined || last === undefined || x < first || x > last) return null;

    return (this.surface.chart.bbox.left || 0) + this.surface.chart.valToPos(x, "x", false);
  }

  selectedTimestampMs(): number | null {
    const value = this.surface.model.selectedRef && this.surface.model.selectedRef.timestamp_ms;
    if (value === null || value === undefined) return null;

    const timestampMs = Number(value);
    if (!Number.isFinite(timestampMs)) return null;
    return timestampMs;
  }

  renderSelectedLimit(marker: ChartMarker) {
    const selected = this.surface.model.selectedRef;
    if (!selected) return;
    if (marker.marker_type === "limit_analysis_bucket") {
      this.renderSelectedLimitBucket(marker);
      return;
    }

    const left = this.surface.markerLeft(marker);
    if (left === null || left === undefined || Number.isNaN(left)) return;

    const selection = document.createElement("div");
    selection.dataset.chartSelectionTarget = "limit event";
    selection.dataset.chartSelectionRef = selected.link_id || "";
    Object.assign(selection.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      width: "18px",
      transform: "translateX(-9px)",
      borderLeft: `3px solid ${this.surface.markerColor(marker)}`,
      borderRight: `3px solid ${this.surface.markerColor(marker)}`,
      background: `${this.surface.themeColor("--chart-highlight-8")}`,
      boxShadow: `0 0 12px ${this.surface.markerColor(marker)}`,
    });
    this.selectionLayer.appendChild(selection);
  }

  renderSelectedLimitBucket(marker: ChartMarker) {
    const selected = this.surface.model.selectedRef;
    if (!selected) return;
    const interval = this.surface.intervalBounds(marker);
    if (!interval) return;

    const selection = document.createElement("div");
    selection.dataset.chartSelectionTarget = "limit analysis bucket";
    selection.dataset.chartSelectionRef = selected.link_id || "";
    Object.assign(selection.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      border: `2px solid ${this.surface.markerColor(marker)}`,
      background: this.surface.limitAnalysisBucketSelectionFill(marker),
      boxShadow: `0 0 12px ${this.surface.markerColor(marker)}`,
    });
    this.selectionLayer.appendChild(selection);
  }

  renderSelectedLimitDefinition(marker: ChartMarker) {
    const selected = this.surface.model.selectedRef;
    if (!selected) return;
    const interval = this.surface.intervalBounds(marker);
    if (!interval) return;

    const selection = document.createElement("div");
    selection.dataset.chartSelectionTarget = "limit definition";
    selection.dataset.chartSelectionRef = selected.link_id || "";
    Object.assign(selection.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      border: `1px solid ${this.surface.limitIntervalColor(marker)}`,
      background: `${this.surface.themeColor("--chart-caution-13")}`,
      boxShadow: `0 0 10px ${this.surface.limitIntervalColor(marker)}`,
    });
    this.selectionLayer.appendChild(selection);
  }

  renderSelectedEvent(marker: ChartMarker) {
    const selected = this.surface.model.selectedRef;
    if (!selected) return;
    const left = this.surface.markerLeft(marker);
    if (left === null || left === undefined || Number.isNaN(left)) return;

    const selection = document.createElement("div");
    selection.dataset.chartSelectionTarget = "mission event";
    selection.dataset.chartSelectionRef = selected.link_id || "";
    Object.assign(selection.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      width: "16px",
      transform: "translateX(-8px)",
      borderLeft: `2px solid ${this.surface.eventColor(marker)}`,
      borderRight: `2px solid ${this.surface.eventColor(marker)}`,
      background: `${this.surface.themeColor("--chart-highlight-6")}`,
      boxShadow: `0 0 10px ${this.surface.eventColor(marker)}`,
    });
    this.selectionLayer.appendChild(selection);
  }
}
