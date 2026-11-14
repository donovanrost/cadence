import type { ChartSeries } from "./chart-input.ts";
import {
  markerTimes,
  type ChartAnnotation,
  type ChartInterval,
  type EventMarker,
  type LimitMarker,
} from "./chart-markers.ts";
import { ChartSeriesModel } from "./chart-series-model.ts";

/** Owns admitted samples, aligned series, marker history, visibility and time windows. No DOM or timers. */
export class ChartModel extends ChartSeriesModel {
  trimToWindow() {
    const windowEnd = this.chartWindowEnd();
    if (windowEnd === null || !Number.isFinite(windowEnd)) return;

    const cutoff = windowEnd - this.windowSeconds;
    this.seriesList = this.seriesList.map((series) => ({
      ...series,
      points: series.points.filter(([timestampMs]) => timestampMs / 1000 >= cutoff),
      envelope: series.envelope
        ? {
            ...series.envelope,
            points: series.envelope.points.filter(([timestampMs]) => timestampMs / 1000 >= cutoff),
          }
        : null,
    }));
    this.rebuildPlotData();
    this.limitMarkers = this.limitMarkers.filter((marker) =>
      this.limitMarkerOverlapsWindow(marker, cutoff),
    );
    this.eventMarkers = this.eventMarkers.filter((marker) =>
      this.eventMarkerOverlapsWindow(marker, cutoff),
    );
    this.annotations = this.annotations.filter((annotation) =>
      this.annotationOverlapsWindow(annotation, cutoff),
    );
  }

  eventMarkerOverlapsWindow(marker: EventMarker, cutoff: number) {
    switch (marker.marker_type) {
      case "contact_interval":
        return this.intervalMarkerOverlapsWindow(marker, cutoff);
      case "mission_event":
        return this.instantOverlapsWindow(marker.timestamp_ms, cutoff);
    }
  }

  limitMarkerOverlapsWindow(marker: LimitMarker, cutoff: number) {
    switch (marker.marker_type) {
      case "limit_definition_interval":
        return this.intervalMarkerOverlapsWindow(marker, cutoff);
      case "limit_event":
        return this.instantOverlapsWindow(marker.timestamp_ms, cutoff);
    }
  }

  /** A zero start or timestamp is "unset" (the chart never draws marks at the epoch). */
  instantOverlapsWindow(timestampMs: number, cutoff: number) {
    return timestampMs !== 0 && timestampMs / 1000 >= cutoff;
  }

  intervalMarkerOverlapsWindow(marker: ChartInterval, cutoff: number) {
    const end = marker.ends_at_ms ? marker.ends_at_ms / 1000 : this.chartWindowEnd();
    if (marker.starts_at_ms === 0) return false;
    return end !== null && end >= cutoff;
  }

  annotationOverlapsWindow(annotation: ChartAnnotation, cutoff: number) {
    if (annotation.geometry === "interval") {
      return this.intervalMarkerOverlapsWindow(annotation, cutoff);
    }

    return annotation.starts_at_ms / 1000 >= cutoff;
  }

  chartWindowEnd(): number | null {
    if (this.liveMode() && Number.isFinite(this.liveWindowEnd)) return this.liveWindowEnd;
    if (this.xs.length === 0) return null;
    return this.xs.at(-1) ?? null;
  }

  visibleSeriesCount() {
    return this.seriesList.filter((series) => this.seriesVisible(series)).length;
  }

  legendVisible() {
    if (this.legendMode === "hidden") return false;
    if (this.legendMode === "always") return this.seriesList.length > 0;

    return this.seriesList.length > 1 || this.sourceUnitGroups().length > 1;
  }

  legendHeight() {
    return this.legendVisible() ? 28 : 0;
  }

  seriesVisible(series: ChartSeries | undefined) {
    return !series || !series.id || !this.hiddenSeriesIds.has(series.id);
  }

  unitGroups() {
    if (this.axisMode === "shared") return [""];

    const units = this.seriesList
      .filter((series) => this.seriesVisible(series))
      .map((series) => series.unit || "")
      .filter((unit) => unit !== "");

    if (units.length === 0) return [""];
    return Array.from(new Set(units));
  }

  sourceUnitGroups() {
    const units = this.seriesList.map((series) => series.unit || "").filter((unit) => unit !== "");

    if (units.length === 0) return [""];
    return Array.from(new Set(units));
  }

  unitScaleKey(unit: string | null | undefined) {
    if (this.axisMode === "shared") return "y";

    const units = this.unitGroups();
    const index = Math.max(units.indexOf(unit || ""), 0);
    return index === 0 ? "y" : `y${index}`;
  }

  chartXRange(dataMin: number, dataMax: number): [number, number] {
    const liveWindowEnd = this.liveMode() ? this.chartWindowEnd() : null;

    if (liveWindowEnd !== null && Number.isFinite(liveWindowEnd)) {
      return [liveWindowEnd - this.windowSeconds, liveWindowEnd];
    }

    const requestedRange = this.requestedTimeRange();
    if (requestedRange) return requestedRange;

    const values = [dataMin, dataMax]
      .concat(this.markerXValues(this.limitMarkers))
      .concat(this.markerXValues(this.eventMarkers))
      .filter((value) => Number.isFinite(value));

    if (values.length === 0) return [dataMin, dataMax];

    const min = Math.min(...values);
    const max = Math.max(...values);

    if (min === max) return [min - 30, max + 30];

    return [min, max];
  }

  requestedTimeRange(): [number, number] | null {
    const fromMs = Date.parse(this.input.time_from || "");
    const toMs = Date.parse(this.input.time_to || "");

    if (!Number.isFinite(fromMs) || !Number.isFinite(toMs) || fromMs >= toMs) return null;
    return [fromMs / 1000, toMs / 1000];
  }

  /** Marker times in seconds, for the x range. */
  markerXValues(markers: readonly (LimitMarker | EventMarker)[]) {
    return markers.flatMap((marker) => markerTimes(marker).map((ms) => ms / 1000));
  }
}
