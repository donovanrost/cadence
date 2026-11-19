/**
 * Public API of the investigate feature used by other ops screens (Telemetry explore, Mobile J6). The chart
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
export {
  DEFAULT_RANGE,
  formatRate,
  limitSegments,
  pickAlarm,
  RANGES,
  rangeWindow,
  ratePerHour,
  sisters,
  toSeries,
  trendSentence,
  type RangeKey,
} from "./model.ts";
export {
  useEpisodeDetail,
  usePointAlarms,
  usePointTrend,
  useSpacecraftAlarms,
  useSpacecraftEpisodes,
} from "./useInvestigate.ts";
export { default as EpisodeBar } from "./EpisodeBar.vue";
export { default as TrendBlock } from "./TrendBlock.vue";
