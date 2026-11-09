/** Public API of the alarms feature: the M9 read, shared by Investigate and the Alarms list. */
export {
  alarmSeverities,
  conditionWords,
  crossedCondition,
  crossedLimit,
  engineeringValue,
  fetchAlarms,
  thresholdsReader,
  type Alarm,
  type AlarmQuery,
  type Alarms,
  type AlarmSeverity,
  type Thresholds,
} from "./api.ts";
export { formatLimitLike, formatValue, withUnit } from "./format.ts";
