import type uPlot from "uplot";
import {
  normalizePoints,
  normalizeEnvelope,
  type ChartEnvelope,
  type PointMetadata,
} from "./chart-points";
import { record } from "@cadence/plugin-sdk/admission";
import {
  readMarkers,
  readSelection,
  textValue,
  type ChartMarker,
  type ChartSeries,
  type PlotSeries,
} from "./chart-input";
import type { TelemetryChartProps } from "./chart-props";

/** Owns admitted samples, aligned series, marker history, visibility and time windows. No DOM or timers. */
export class ChartModel {
  seriesList: ChartSeries[] = [];
  xs: number[] = [];
  seriesYs: (number | null)[][] = [];
  seriesPointMeta: PointMetadata[][] = [];
  plotSeries: PlotSeries[] = [];
  hiddenSeriesIds = new Set<string>();
  liveWindowEnd: number | null = null;
  limitMarkers: ChartMarker[];
  eventMarkers: ChartMarker[];
  annotations: ChartMarker[];
  selectedRef: ChartMarker | null;
  axisMode: "unit" | "shared";
  readonly widgetId: string;
  readonly placementId: string;
  readonly windowSeconds: number;
  readonly legendMode: string;
  readonly lineWidth: string;
  readonly fillOpacity: number;
  readonly spanGaps: boolean;
  readonly showPoints: boolean;
  readonly showMinMaxBand: boolean;
  readonly sharedTooltip: boolean;
  constructor(readonly input: Readonly<TelemetryChartProps>) {
    this.widgetId = input.widget_id;
    this.placementId = input.placement_id;
    this.windowSeconds = input.window_seconds || 300;
    this.axisMode = input.axis_mode === "shared" ? "shared" : "unit";
    this.legendMode = input.legend_mode ?? "auto";
    this.lineWidth = input.line_width ?? "normal";
    this.fillOpacity = Math.max(0, Math.min(30, input.fill_opacity ?? 8));
    this.spanGaps = input.span_gaps ?? false;
    this.showPoints = input.show_points ?? false;
    this.showMinMaxBand = input.show_min_max_band ?? true;
    this.sharedTooltip = input.shared_tooltip ?? true;
    this.seriesList = this.normalizeSeriesPayload(input.backfill).concat(
      this.normalizeCompareSeriesPayload(input.compare_backfill),
    );
    this.limitMarkers = readMarkers(input.limit_markers);
    this.eventMarkers = this.collapseSourceWatermarkMarkers(readMarkers(input.event_markers));
    this.annotations = readMarkers(input.annotations);
    this.selectedRef = readSelection(input.selected_ref);
    if (this.liveMode()) this.advanceLiveWindow(Date.now());
    this.rebuildPlotData();
  }
  get pointCount() {
    return this.seriesList.reduce((count, series) => count + series.points.length, 0);
  }
  get latestTimestampMs() {
    return this.seriesList
      .flatMap((series) => series.points.map(([time]) => time))
      .reduce<number | null>(
        (latest, time) => (latest === null ? time : Math.max(latest, time)),
        null,
      );
  }
  normalizeSeriesPayload(payload: unknown): ChartSeries[] {
    if (Array.isArray(payload)) {
      return [this.normalizeSeries({ points: payload })].filter(
        (series) => series.points.length > 0,
      );
    }

    if (record(payload) && Array.isArray(payload.series)) {
      return payload.series
        .filter(record)
        .map((series) => this.normalizeSeries(series))
        .filter((series) => series.points.length > 0);
    }

    if (record(payload) && Array.isArray(payload.points)) {
      return [this.normalizeSeries(payload)].filter((series) => series.points.length > 0);
    }

    return [];
  }

  normalizeCompareSeriesPayload(payload: unknown): ChartSeries[] {
    return this.normalizeSeriesPayload(payload).map((series) => {
      const primaryId = series.compare_of || series.id || this.widgetId;
      const compareId = `${primaryId}`.startsWith("compare:")
        ? `${primaryId}`
        : `compare:${primaryId}`;

      return {
        ...series,
        id: compareId,
        label: `${series.label || primaryId} compare`,
        role: "compare",
        compare_of: primaryId,
      };
    });
  }

  normalizeSeries(series: Record<string, unknown>): ChartSeries {
    const fallback = this.seriesList[0];
    const id =
      textValue(series.id) ||
      textValue(series.observable_id) ||
      (fallback && fallback.id) ||
      this.widgetId;
    const label =
      textValue(series.label) ||
      textValue(series.observable_id) ||
      (fallback && fallback.label) ||
      this.input.label ||
      id;

    return {
      id,
      label,
      observable_id:
        textValue(series.observable_id) || (fallback && fallback.observable_id) || null,
      unit: textValue(series.unit) || (fallback && fallback.unit) || this.input.unit || null,
      source: series.source || (fallback && fallback.source) || null,
      frame_id: textValue(series.frame_id) || (fallback && fallback.frame_id) || null,
      field: textValue(series.field) || (fallback && fallback.field) || null,
      time_axis: textValue(series.time_axis) || (fallback && fallback.time_axis) || null,
      sampling: series.sampling || (fallback && fallback.sampling) || null,
      decimation: series.decimation || (fallback && fallback.decimation) || null,
      data_source_id:
        textValue(series.data_source_id) || (fallback && fallback.data_source_id) || null,
      source_binding_id:
        textValue(series.source_binding_id) || (fallback && fallback.source_binding_id) || null,
      role: textValue(series.role) || (fallback && fallback.role) || "primary",
      compare_of: textValue(series.compare_of) || (fallback && fallback.compare_of) || null,
      envelope: normalizeEnvelope(series.envelope || (fallback && fallback.envelope) || null),
      points: normalizePoints(series.points || []),
    };
  }

  appendSeriesPayload(payload: unknown) {
    const incoming = this.normalizeSeriesPayload(payload);
    if (incoming.length === 0) return false;

    incoming.forEach((series) => {
      const index = this.seriesList.findIndex((existing) => existing.id === series.id);

      const previous = this.seriesList[index];
      if (previous) {
        this.seriesList[index] = {
          ...previous,
          ...series,
          points: previous.points.concat(series.points),
          envelope: this.mergeEnvelope(previous.envelope, series.envelope),
        };
      } else {
        this.seriesList.push(series);
      }
    });

    this.rebuildPlotData();
    return true;
  }

  seriesPayloadPointCount(payload: unknown) {
    return this.normalizeSeriesPayload(payload).reduce(
      (count, series) => count + series.points.length,
      0,
    );
  }

  seriesPayloadLatestTimestampMs(payload: unknown) {
    const timestamps = this.normalizeSeriesPayload(payload).flatMap((series) =>
      series.points.map(([timestampMs]) => Number(timestampMs)),
    );
    const valid = timestamps.filter((timestampMs) => Number.isFinite(timestampMs));

    return valid.length > 0 ? Math.max(...valid) : null;
  }

  mergeEnvelope(previous: ChartEnvelope | null, incoming: ChartEnvelope | null) {
    if (!previous) return incoming;
    if (!incoming) return previous;

    return {
      ...previous,
      ...incoming,
      points: previous.points.concat(incoming.points),
    };
  }

  rebuildPlotData() {
    const xs = Array.from(
      new Set(
        this.seriesList.flatMap((series) => {
          const pointTimes = series.points.map(([timestampMs]) => timestampMs / 1000);
          const envelopeTimes = series.envelope
            ? series.envelope.points.map(([timestampMs]) => timestampMs / 1000)
            : [];

          return pointTimes.concat(envelopeTimes);
        }),
      ),
    ).sort((a, b) => a - b);

    this.xs = xs;
    this.seriesYs = [];
    this.seriesPointMeta = [];
    this.plotSeries = [];

    this.seriesList.forEach((series, seriesIndex) => {
      const pointsByTime = new Map(
        series.points.map(([timestampMs, value, metadata]) => [
          timestampMs / 1000,
          {
            value,
            metadata: {
              ...metadata,
              series_id: series.id,
              series_label: series.label,
              observable_id: series.observable_id,
              series_index: seriesIndex,
              series_role: series.role || "primary",
              compare_of: series.compare_of || null,
              data_source_id: series.data_source_id || this.input.data_source_id || null,
              source_binding_id: series.source_binding_id || this.input.source_binding_id || null,
              time_axis: series.time_axis || this.input.time_axis || null,
              data_view:
                series.role === "compare"
                  ? this.input.compare_data_view || null
                  : this.input.data_view || null,
            },
          },
        ]),
      );

      this.seriesYs.push(xs.map((x) => pointsByTime.get(x)?.value ?? null));
      this.seriesPointMeta.push(xs.map((x) => pointsByTime.get(x)?.metadata ?? {}));
      this.plotSeries.push({ kind: "line", seriesIndex });

      if (series.envelope && this.showMinMaxBand) {
        const envelopeByTime = new Map(
          series.envelope.points.map(([timestampMs, min, max]) => [
            timestampMs / 1000,
            { min, max },
          ]),
        );

        this.plotSeries.push({
          kind: "envelope_low",
          seriesIndex,
          values: xs.map((x) => envelopeByTime.get(x)?.min ?? null),
        });
        this.plotSeries.push({
          kind: "envelope_high",
          seriesIndex,
          values: xs.map((x) => envelopeByTime.get(x)?.max ?? null),
        });
      }
    });
  }

  plotData(): uPlot.AlignedData {
    const series = this.plotSeries.map((entry) => {
      if (entry.kind === "line") return this.seriesYs[entry.seriesIndex] ?? [];
      return entry.values;
    });

    return [this.xs, ...series];
  }

  seriesGaps(
    plot: uPlot,
    uPlotSeriesIndex: number,
    idx0: number,
    idx1: number,
    nullGaps: [number, number][] = [],
  ) {
    const entry = this.plotSeries[uPlotSeriesIndex - 1];
    if (!entry) return nullGaps;

    const xs = (plot.data && plot.data[0]) || this.xs || [];
    const ys =
      (plot.data && plot.data[uPlotSeriesIndex]) ||
      (entry.kind === "line" ? this.seriesYs[entry.seriesIndex] : entry.values) ||
      [];
    const observed = [];
    const fromIndex = Math.max(0, idx0);
    const toIndex = Math.min(idx1, xs.length - 1, ys.length - 1);

    for (let index = fromIndex; index <= toIndex; index += 1) {
      const x = Number(xs[index]);
      const y = ys[index];
      if (Number.isFinite(x) && y !== null && y !== undefined && Number.isFinite(Number(y))) {
        observed.push(x);
      }
    }

    const threshold = this.inferredGapThreshold(observed);
    if (threshold === null || !Number.isFinite(threshold)) return nullGaps;

    const inferredGaps: [number, number][] = [];

    for (let index = 1; index < observed.length; index += 1) {
      const previous = observed[index - 1];
      const current = observed[index];
      if (current === undefined || previous === undefined || current - previous <= threshold)
        continue;

      const from = plot.valToPos(previous, "x", true);
      const to = plot.valToPos(current, "x", true);
      if (Number.isFinite(from) && Number.isFinite(to)) inferredGaps.push([from, to]);
    }

    return this.mergePixelGaps(nullGaps.concat(inferredGaps));
  }

  inferredGapThreshold(observed: number[]) {
    const intervals = observed
      .slice(1)
      .flatMap((value, index) => {
        const previous = observed[index];
        return previous === undefined ? [] : [value - previous];
      })
      .filter((value) => Number.isFinite(value) && value > 0);

    if (intervals.length < 3) return null;

    const sorted = intervals.slice().sort((left, right) => left - right);
    const middle = Math.floor(sorted.length / 2);
    const upper = sorted[middle];
    const lower = sorted[middle - 1];
    if (upper === undefined || lower === undefined) return null;
    const median = sorted.length % 2 === 0 ? (lower + upper) / 2 : upper;

    return Math.max(median * 3, 5);
  }

  mergePixelGaps(gaps: [number, number][]): [number, number][] {
    return gaps
      .map(([from, to]): [number, number] => [Math.min(from, to), Math.max(from, to)])
      .filter(([from, to]) => Number.isFinite(from) && Number.isFinite(to) && to > from)
      .sort((left, right) => left[0] - right[0])
      .reduce<[number, number][]>((merged, gap) => {
        const previous = merged[merged.length - 1];
        if (previous && gap[0] <= previous[1]) previous[1] = Math.max(previous[1], gap[1]);
        else merged.push(gap);
        return merged;
      }, []);
  }

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
      this.eventMarkers = this.collapseSourceWatermarkMarkers(
        this.dedupeMarkers(this.eventMarkers.concat(eventMarkerAppends)),
      );
      appended = true;
    }

    if (annotationAppends.length > 0) {
      this.annotations = this.dedupeMarkers(this.annotations.concat(annotationAppends));
      appended = true;
    }

    return appended;
  }

  collapseSourceWatermarkMarkers(markers: ChartMarker[]) {
    if (!Array.isArray(markers)) return [];

    const latestCursors = this.latestSourceWatermarkMarkers(
      markers.filter((marker) => marker.marker_type === "source_watermark_cursor"),
    );
    const cursorIdentities = new Set(
      latestCursors.map((marker) => this.sourceWatermarkIdentity(marker)),
    );
    const fallbackEvents = this.latestSourceWatermarkMarkers(
      markers.filter((marker) => marker.marker_type === "source_watermark_event"),
    ).filter((marker) => !cursorIdentities.has(this.sourceWatermarkIdentity(marker)));

    return markers
      .filter(
        (marker) =>
          marker.marker_type !== "source_watermark_cursor" &&
          marker.marker_type !== "source_watermark_event",
      )
      .concat(latestCursors, fallbackEvents);
  }

  latestSourceWatermarkMarkers(markers: ChartMarker[]) {
    const latest = new Map<string, ChartMarker>();

    markers.forEach((marker) => {
      const identity = this.sourceWatermarkIdentity(marker);
      const current = latest.get(identity);
      if (
        !current ||
        this.sourceWatermarkTimestamp(marker) >= this.sourceWatermarkTimestamp(current)
      ) {
        latest.set(identity, marker);
      }
    });

    return Array.from(latest.values());
  }

  sourceWatermarkIdentity(marker: ChartMarker) {
    return [
      marker.logical_source || "",
      marker.data_source_id || "",
      marker.source_binding_id || "",
      marker.dataset || "",
      marker.realm || "",
      marker.replay_run_id || "",
    ].join(":");
  }

  sourceWatermarkTimestamp(marker: ChartMarker) {
    return Number(marker.timestamp_ms || marker.complete_through_ms || marker.observed_at_ms || 0);
  }

  eventMarkerOverlapsWindow(marker: ChartMarker, cutoff: number) {
    if (
      marker.marker_type === "source_binding_interval" ||
      marker.marker_type === "retention_gap" ||
      marker.marker_type === "telemetry_revision_range" ||
      (marker.marker_type === "telemetry_backfill_lifecycle" && marker.starts_at_ms)
    ) {
      return this.intervalMarkerOverlapsWindow(marker, cutoff);
    }

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

  liveMode() {
    return this.input.time_mode === "live";
  }

  advanceLiveWindow(windowEndMs: unknown) {
    if (!this.liveMode()) return false;

    const windowEnd = Number(windowEndMs) / 1000;
    if (!Number.isFinite(windowEnd) || windowEnd <= 0) return false;

    this.liveWindowEnd = windowEnd;
    return true;
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
