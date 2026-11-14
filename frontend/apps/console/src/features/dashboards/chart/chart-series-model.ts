import type uPlot from "uplot";
import {
  normalizePoints,
  normalizeEnvelope,
  type ChartEnvelope,
  type PointMetadata,
} from "./chart-points.ts";
import { record } from "./record.ts";
import { textValue, type ChartSeries, type PlotSeries } from "./chart-input.ts";
import type { ChartAnnotation, EventMarker, LimitMarker } from "./chart-markers.ts";
import type {
  ChartAxisMode,
  ChartLegendMode,
  ChartLineWidth,
  TelemetryChartProps,
} from "./chart-props.ts";

/**
 * Series half of the chart model: admitted samples, aligned plot data, gaps and the live window.
 * No DOM or timers. ChartModel adds markers, visibility, units and ranges (split for size).
 */
export abstract class ChartSeriesModel {
  seriesList: ChartSeries[] = [];
  xs: number[] = [];
  seriesYs: (number | null)[][] = [];
  seriesPointMeta: PointMetadata[][] = [];
  plotSeries: PlotSeries[] = [];
  hiddenSeriesIds = new Set<string>();
  liveWindowEnd: number | null = null;
  limitMarkers: readonly LimitMarker[];
  eventMarkers: readonly EventMarker[];
  annotations: readonly ChartAnnotation[];
  axisMode: ChartAxisMode;
  readonly widgetId: string;
  readonly placementId: string;
  readonly windowSeconds: number;
  readonly legendMode: ChartLegendMode;
  readonly lineWidth: ChartLineWidth;
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
    this.limitMarkers = input.limit_markers ?? [];
    this.eventMarkers = input.event_markers ?? [];
    this.annotations = input.annotations ?? [];
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
}
