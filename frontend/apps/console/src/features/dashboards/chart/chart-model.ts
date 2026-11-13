import { record } from "./record.ts";
import { readMarkers, type ChartMarker, type ChartSeries } from "./chart-input.ts";
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

  appendMarkerPayload(payload: unknown) {
    const markerAppends = Array.isArray(payload)
      ? readMarkers(payload)
      : record(payload)
        ? {
            limit_markers: readMarkers(payload.limit_markers),
            event_markers: readMarkers(payload.event_markers),
            annotations: readMarkers(payload.annotations),
          }
        : null;
    if (Array.isArray(markerAppends) && markerAppends.length > 0) {
      this.limitMarkers = this.dedupeMarkers(this.limitMarkers.concat(markerAppends));
      return true;
    }

    if (!markerAppends || Array.isArray(markerAppends)) return false;

    const limitMarkerAppends = markerAppends.limit_markers || [];
    const eventMarkerAppends = markerAppends.event_markers || [];
    const annotationAppends = markerAppends.annotations || [];
    let appended = false;

    if (limitMarkerAppends.length > 0) {
      this.limitMarkers = this.dedupeMarkers(this.limitMarkers.concat(limitMarkerAppends));
      appended = true;
    }

    if (eventMarkerAppends.length > 0) {
      this.eventMarkers = this.dedupeMarkers(this.eventMarkers.concat(eventMarkerAppends));
      appended = true;
    }

    if (annotationAppends.length > 0) {
      this.annotations = this.dedupeMarkers(this.annotations.concat(annotationAppends));
      appended = true;
    }

    return appended;
  }

  eventMarkerOverlapsWindow(marker: ChartMarker, cutoff: number) {
    if (marker.starts_at_ms) return this.intervalMarkerOverlapsWindow(marker, cutoff);
    if (!marker.timestamp_ms) return false;
    return marker.timestamp_ms / 1000 >= cutoff;
  }

  limitMarkerOverlapsWindow(marker: ChartMarker, cutoff: number) {
    if (
      marker.marker_type === "limit_definition_interval" ||
      marker.marker_type === "limit_analysis_bucket"
    ) {
      return this.intervalMarkerOverlapsWindow(marker, cutoff);
    }

    if (!marker.timestamp_ms) return false;
    return marker.timestamp_ms / 1000 >= cutoff;
  }

  intervalMarkerOverlapsWindow(marker: ChartMarker, cutoff: number) {
    const start = marker.starts_at_ms && marker.starts_at_ms / 1000;
    const end = marker.ends_at_ms ? marker.ends_at_ms / 1000 : this.chartWindowEnd();
    if (!start) return false;
    return end !== null && end >= cutoff;
  }

  annotationOverlapsWindow(annotation: ChartMarker, cutoff: number) {
    if (annotation.geometry === "interval") {
      return this.intervalMarkerOverlapsWindow(annotation, cutoff);
    }

    const timestampMs = Number(annotation.timestamp_ms || annotation.starts_at_ms);
    return Number.isFinite(timestampMs) && timestampMs / 1000 >= cutoff;
  }

  chartWindowEnd(): number | null {
    if (this.liveMode() && Number.isFinite(this.liveWindowEnd)) return this.liveWindowEnd;
    if (this.xs.length === 0) return null;
    return this.xs.at(-1) ?? null;
  }

  dedupeMarkers(markers: ChartMarker[]) {
    const seen = new Set();
    return markers.filter((marker) => {
      const key =
        marker.annotation_id ||
        marker.link_id ||
        marker.marker_id ||
        `${marker.marker_type || "limit_event"}:${marker.limit_event_id || marker.limit_definition_id}:${marker.timestamp_ms || marker.starts_at_ms}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
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

  markerXValues(markers: ChartMarker[]) {
    if (!Array.isArray(markers)) return [];

    return markers.flatMap((marker) =>
      (["timestamp_ms", "starts_at_ms", "ends_at_ms"] as const)
        .map((key) => {
          const value = Number(marker[key]);
          return Number.isFinite(value) ? value / 1000 : null;
        })
        .filter((value) => value !== null),
    );
  }
}
