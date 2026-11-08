/**
 * Public API of the investigate feature used by other ops screens (Telemetry explore). The chart
 * moves to @cadence/apogee-ui as ApTimeSeries when lead promotes it.
 */
export { fetchHistory, fetchLimitIntervals, type History, type HistoryWindow } from "./api.ts";
export { default as TrendChart } from "./chart/TrendChart.vue";
export type { ComparisonSeries, LimitSegment, SeriesPoint, TimeWindow } from "./chart/scale.ts";
export { limitSegments, RANGES, rangeWindow, toSeries, type RangeKey } from "./model.ts";
