import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { bandFor } from "./api.ts";
import { formatValue, withUnit } from "./format.ts";
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
  /**
   * A group header (OpsLists §Alarms: identical point + condition across GROUP_AT or more
   * spacecraft): `episode` is its first (most severe) member's; the members follow when expanded.
   */
  group?: Readonly<{
    size: number;
    where: string;
    expanded: boolean;
    unassigned: number;
    /** Members' value range when numeric with one unit ("23.1–23.6 V"), else null (blank). */
    range: string | null;
    /** The earliest member opening. */
    openedAt: string;
    /** The member the operator acts on first: in contact, else the soonest booked AOS. */
    soonest: FleetSpacecraft | null;
  }>;
  /** A row shown under its expanded group. */
  member?: boolean;
}>;

export const GROUP_AT = 3;

/** "plane 07", "planes 03, 07", or "" when no member has a plane. */
function planesOf(rows: readonly AlarmListRow[]): string {
  const planes = [...new Set(rows.flatMap((r) => (r.sc?.plane == null ? [] : [r.sc.plane])))]
    .sort((a, b) => a - b)
    .map((p) => String(p).padStart(2, "0"));
  if (planes.length === 0) return "";
  return planes.length === 1 ? `plane ${planes[0]}` : `planes ${planes.join(", ")}`;
}

function valueRange(members: readonly AlarmListRow[]): string | null {
  const units = new Set(members.map((m) => m.episode.point.unit));
  const values = members.map((m) => m.episode.last_value);
  if (units.size !== 1 || !values.every((v): v is number => typeof v === "number")) return null;
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  const unit = members[0]?.episode.point.unit ?? null;
  const text = lo === hi ? formatValue(lo) : `${formatValue(lo)}–${formatValue(hi)}`;
  return withUnit(text, unit);
}

function soonestOf(members: readonly AlarmListRow[]): FleetSpacecraft | null {
  const scs = members.flatMap((m) => (m.sc ? [m.sc] : []));
  return (
    scs.find((sc) => sc.in_contact) ??
    scs
      .filter((sc) => sc.next_aos_at !== null)
      .sort((a, b) => Date.parse(a.next_aos_at ?? "") - Date.parse(b.next_aos_at ?? ""))[0] ??
    null
  );
}

/**
 * Folds rows with the same point and condition (GROUP_AT or more) into a header row where the
 * first of them was, members after it when `expanded` has its key. Order is otherwise kept.
 */
export function groupAlarmRows(
  rows: readonly AlarmListRow[],
  expanded: ReadonlySet<string>,
): AlarmListRow[] {
  const keyOf = (r: AlarmListRow) => `group:${r.episode.point.id}|${r.episode.source_state ?? ""}`;
  const groups = new Map<string, AlarmListRow[]>();
  for (const r of rows) groups.set(keyOf(r), [...(groups.get(keyOf(r)) ?? []), r]);
  const done = new Set<string>();
  return rows.flatMap((r) => {
    const key = keyOf(r);
    const members = groups.get(key) ?? [r];
    if (members.length < GROUP_AT) return [r];
    if (done.has(key)) return [];
    done.add(key);
    const open = expanded.has(key);
    const where = planesOf(members);
    const header: AlarmListRow = {
      ...r,
      key,
      group: {
        size: members.length,
        where: `${members.length} spacecraft${where ? ` in ${where}` : ""}`,
        expanded: open,
        unassigned: members.filter((m) => m.owner === "Unassigned").length,
        range: valueRange(members),
        openedAt: members.reduce(
          (min, m) => (m.episode.opened_at < min ? m.episode.opened_at : min),
          r.episode.opened_at,
        ),
        soonest: soonestOf(members),
      },
    };
    return open ? [header, ...members.map((m) => ({ ...m, member: true }))] : [header];
  });
}

/** Empty New tab (OpsLists §Alarms): "Last cleared 01:12Z on EARENDIL-047.", or null. */
export function lastClearedLine(cleared: readonly Episode[], now: Date): string | null {
  let last: Episode | null = null;
  for (const e of cleared)
    if (e.cleared_at && (!last?.cleared_at || e.cleared_at > last.cleared_at)) last = e;
  if (!last?.cleared_at) return null;
  const iso = last.cleared_at;
  const today = iso.slice(0, 10) === now.toISOString().slice(0, 10);
  const when = `${today ? "" : `${iso.slice(5, 10)} `}${iso.slice(11, 16)}Z`;
  const on = last.spacecraft ? (last.spacecraft.name ?? "an unknown spacecraft") : "the mission";
  return `Last cleared ${when} on ${on}.`;
}

/** A row's spacecraft label: its name, "Unknown spacecraft" when it has none, "Mission" for a
 * mission-level alarm (ux, #190: never "Mission" for a craft's alarm). */
export const craftOrMission = (e: Pick<Episode, "spacecraft">) =>
  e.spacecraft ? (e.spacecraft.name ?? "Unknown spacecraft") : "Mission";

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

/** ux U71 A12: what happened, as a clause: 'a new alarm on X', '… became critical', 'eased to caution'. */
function changeClause(kind: Readonly<{ unrecognized: string }> | string, on: string): string {
  if (kind === "raised") return `a new alarm ${on}`;
  if (kind === "escalated") return `an alarm ${on} became critical`;
  if (kind === "deescalated") return `an alarm ${on} eased to caution`;
  if (kind === "cleared") return `an alarm ${on} cleared`;
  return `an alarm ${on} changed`;
}

/**
 * ux U71 A12: the Alarms header's sentence, 'Last change 02:51Z: a new alarm on EARENDIL-047.'
 * (the date when not today; 'on the mission' without a spacecraft), or null when there's none.
 */
export function lastChangeLine(
  change:
    | Readonly<{
        at: string;
        kind:
          | Readonly<{ unrecognized: string }>
          | "raised"
          | "escalated"
          | "deescalated"
          | "cleared";
        spacecraft_id: string | null;
      }>
    | null
    | undefined,
  /** The craft mid-sentence (craftInSentence); null while the fleet read loads, so the line waits. */
  nameOf: (id: string) => string | null,
  now: Date,
): string | null {
  if (!change) return null;
  const iso = change.at;
  const today = iso.slice(0, 10) === now.toISOString().slice(0, 10);
  const when = `${today ? "" : `${iso.slice(5, 10)} `}${iso.slice(11, 16)}Z`;
  if (change.spacecraft_id === null)
    return `Last change ${when}: ${changeClause(change.kind, "on the mission")}.`;
  // A craft's change never reads "on the mission"; until it can be named, the line waits (#652).
  const name = nameOf(change.spacecraft_id);
  return name === null ? null : `Last change ${when}: ${changeClause(change.kind, `on ${name}`)}.`;
}
