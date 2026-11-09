import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { bandFor } from "./api.ts";
import type { Episode } from "./episodes.ts";

/**
 * Alarms list (OpsLists.md §Alarms) on alarm episodes (api-ops: /alarm-episodes is the list):
 * lifecycle tabs, owner, source, joined with fleet identity, and the by-point aggregate.
 */

export const ALARM_TABS = ["new", "acknowledged", "cleared"] as const;
export type AlarmTab = (typeof ALARM_TABS)[number];

export type AlarmListRow = Readonly<{
  key: string;
  episode: Episode;
  /** Fleet row for the link and identity; null for mission-scope or unknown spacecraft. */
  sc: FleetSpacecraft | null;
  limit: number | null;
  /** "ACK MIRA K. · → TOMÁS R." / "UNASSIGNED" / "CLEARED UNACKNOWLEDGED". */
  owner: string;
}>;

export function ownerText(e: Episode): string {
  if (e.status === "cleared") return e.cleared_unacknowledged ? "Cleared unacknowledged" : "—";
  const parts = [
    e.status === "acknowledged" ? `Ack ${e.acknowledged_by?.name ?? ""}`.trim() : null,
    e.assignee ? `→ ${e.assignee.name ?? "someone"}` : null,
  ].filter((p): p is string => p !== null);
  return parts.length ? parts.join(" · ") : "Unassigned";
}

const inTab = (e: Episode, tab: AlarmTab, now: number) => {
  switch (tab) {
    case "new":
      return e.status === "new";
    case "acknowledged":
      return e.status === "acknowledged";
    case "cleared":
      return (
        e.status === "cleared" &&
        e.cleared_at !== null &&
        now - Date.parse(e.cleared_at) <= 86_400_000
      );
  }
};

/** Rows for a tab, in server order (critical first, New before acknowledged, newest first). */
export function alarmRows(
  episodes: readonly Episode[],
  fleet: readonly FleetSpacecraft[],
  tab: AlarmTab,
  pointId: string | null,
  now: Date,
): AlarmListRow[] {
  const byId = new Map(fleet.map((sc) => [sc.id, sc]));
  return episodes
    .filter((e) => inTab(e, tab, now.getTime()) && (pointId === null || e.point.id === pointId))
    .map((e) => ({
      key: e.id,
      episode: e,
      sc: e.spacecraft_id ? (byId.get(e.spacecraft_id) ?? null) : null,
      limit: bandFor(e.thresholds, e.source_state),
      owner: ownerText(e),
    }));
}

export function tabCounts(
  active: readonly Episode[],
  cleared: readonly Episode[] | null,
  now: Date,
) {
  const t = now.getTime();
  return {
    new: active.filter((e) => inTab(e, "new", t)).length,
    acknowledged: active.filter((e) => inTab(e, "acknowledged", t)).length,
    cleared: cleared === null ? null : cleared.filter((e) => inTab(e, "cleared", t)).length,
  };
}

export type PointCount = Readonly<{
  pointId: string;
  name: string;
  count: number;
  critical: number;
}>;

/** Active episodes per point, most first: "is it spreading?" */
export function byPoint(episodes: readonly Episode[]): PointCount[] {
  const counts = new Map<string, { name: string; count: number; critical: number }>();
  for (const e of episodes) {
    if (e.status === "cleared") continue;
    const entry = counts.get(e.point.id) ?? { name: e.point.name, count: 0, critical: 0 };
    entry.count += 1;
    if (e.severity === "critical") entry.critical += 1;
    counts.set(e.point.id, entry);
  }
  return [...counts.entries()]
    .map(([pointId, entry]) => ({ pointId, ...entry }))
    .sort((a, b) => b.count - a.count || b.critical - a.critical || a.name.localeCompare(b.name));
}
