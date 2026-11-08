import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { crossedLimit, type Alarm } from "./api.ts";

/** Alarms list (OpsLists.md §Alarms): rows joined with fleet identity, and the by-point aggregate. */

export type AlarmListRow = Readonly<{
  alarm: Alarm;
  /** Null when the alarm's spacecraft isn't in the fleet snapshot (mission-scope point). */
  sc: FleetSpacecraft | null;
  limit: number | null;
}>;

const rank = (alarm: Alarm) =>
  alarm.severity === "critical" ? 0 : alarm.severity === "caution" ? 1 : 2;
const crossed = (alarm: Alarm) =>
  alarm.first_crossed_at === null ? Infinity : Date.parse(alarm.first_crossed_at);

/** Severity first, then the longest-standing (oldest first crossing) first. */
export function alarmRows(
  alarms: readonly Alarm[],
  fleet: readonly FleetSpacecraft[],
  pointId: string | null,
): AlarmListRow[] {
  const byId = new Map(fleet.map((sc) => [sc.id, sc]));
  return alarms
    .filter((alarm) => pointId === null || alarm.point.id === pointId)
    .map((alarm) => ({
      alarm,
      sc: alarm.spacecraft_id ? (byId.get(alarm.spacecraft_id) ?? null) : null,
      limit: crossedLimit(alarm),
    }))
    .sort((a, b) => rank(a.alarm) - rank(b.alarm) || crossed(a.alarm) - crossed(b.alarm));
}

export type PointCount = Readonly<{
  pointId: string;
  name: string;
  count: number;
  critical: number;
}>;

/** Active alarms per point, most first: "is it spreading?" */
export function byPoint(alarms: readonly Alarm[]): PointCount[] {
  const counts = new Map<string, { name: string; count: number; critical: number }>();
  for (const alarm of alarms) {
    if (!alarm.active) continue;
    const entry = counts.get(alarm.point.id) ?? { name: alarm.point.name, count: 0, critical: 0 };
    entry.count += 1;
    if (alarm.severity === "critical") entry.critical += 1;
    counts.set(alarm.point.id, entry);
  }
  return [...counts.entries()]
    .map(([pointId, entry]) => ({ pointId, ...entry }))
    .sort((a, b) => b.count - a.count || b.critical - a.critical || a.name.localeCompare(b.name));
}
