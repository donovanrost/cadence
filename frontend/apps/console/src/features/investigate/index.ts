/**
 * Public API of the investigate feature used by other ops screens (Telemetry explore). The chart
 * now lives in @cadence/apogee-ui as ApTimeSeries; TrendChart stays as an alias for existing callers.
 */
export {
  fetchHistory,
  fetchLimitIntervals,
  type History,
  type HistoryWindow,
  type LimitIntervals,
} from "./api.ts";
export {
  ApTimeSeries as TrendChart,
  type ComparisonSeries,
  type LimitSegment,
  type SeriesPoint,
  type TimeWindow,
} from "@/ui";
export { limitSegments, RANGES, rangeWindow, toSeries, type RangeKey } from "./model.ts";
