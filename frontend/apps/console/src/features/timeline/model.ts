import type { RouteLocationRaw } from "vue-router";
import type { OpState } from "@/ui";
import type { Density, EventKind, EventSeverity, MissionEvent } from "./api.ts";

/** Timeline (OpsLists §Timeline): pure helpers. */

export function severityState(severity: EventSeverity): OpState {
  switch (severity) {
    case "critical":
      return "crit";
    case "caution":
      return "caution";
    case "nominal":
      return "nominal";
    case "info":
      return "neutral";
  }
}

/**
 * Where an event's subject lives. Kinds without a page of their own (e.g. `activation`) stay plain
 * text rather than linking somewhere vague.
 */
export function subjectLink(event: MissionEvent): RouteLocationRaw | null {
  const s = event.refs.subject;
  if (!s) return null;
  switch (s.kind) {
    case "data_source":
      return { name: "setup.data-sources", params: { sourceId: s.id } };
    case "contact":
      return { name: "ops.contacts", query: { contact: s.id } };
    case "dashboard":
      return { name: "ops.dashboards", params: { dashboardId: s.id } };
    case "catalog_revision":
      return { name: "setup.catalog" };
    default:
      return null;
  }
}

/** The server sentence names the spacecraft itself now; only prefix it when it doesn't. */
export const needsSpacecraftPrefix = (event: MissionEvent) =>
  event.spacecraft !== null && !event.text.includes(event.spacecraft.name);

export const KIND_WORDS: Readonly<Record<EventKind, string>> = {
  limit: "Limits",
  flight_event: "Flight events",
  contact: "Contacts",
  command: "Commands",
  config: "Configuration",
  operator: "Operators",
  data: "Data pipeline",
};

/**
 * One row: an event, a run of consecutive identical events (× count, first–last), or the same
 * event across many spacecraft in one minute (`members`, expandable; ux Timeline review 6).
 */
export type LogRow = Readonly<{
  key: string;
  event: MissionEvent;
  count: number;
  firstAt: string;
  members: readonly MissionEvent[];
}>;

/** More than this many spacecraft with the same event in one minute fold into one row. */
export const FANOUT_AT = 3;

function foldAcrossSpacecraft(rows: LogRow[]): LogRow[] {
  const keyOf = (r: LogRow) => `${r.event.kind}|${r.event.text}|${r.event.at.slice(0, 16)}`;
  const groups = new Map<string, LogRow[]>();
  for (const row of rows) {
    if (!row.event.spacecraft) continue;
    groups.set(keyOf(row), [...(groups.get(keyOf(row)) ?? []), row]);
  }
  const out: LogRow[] = [];
  const emitted = new Set<string>();
  for (const row of rows) {
    const key = keyOf(row);
    const group = row.event.spacecraft ? groups.get(key) : undefined;
    const distinct = new Set(group?.map((r) => r.event.spacecraft?.id)).size;
    if (!group || distinct <= FANOUT_AT) {
      out.push(row);
      continue;
    }
    if (emitted.has(key)) continue;
    emitted.add(key);
    out.push({
      key: `fanout:${row.key}`,
      event: row.event,
      count: group.reduce((n, r) => n + r.count, 0),
      firstAt: group.at(-1)?.firstAt ?? row.firstAt,
      members: group.map((r) => r.event),
    });
  }
  return out;
}
export type HourGroup = Readonly<{ hour: string; rows: readonly LogRow[] }>;

const same = (a: MissionEvent, b: MissionEvent) =>
  a.kind === b.kind &&
  a.text === b.text &&
  a.severity === b.severity &&
  a.spacecraft?.id === b.spacecraft?.id;

/**
 * Newest first under UTC hour headers ("2026-11-08 02:00Z"); consecutive identical events
 * collapse into one row (ux Timeline review 2: "× 214", with the time span).
 */
export function byHour(events: readonly MissionEvent[]): HourGroup[] {
  const sorted = [...events].sort((a, b) => Date.parse(b.at) - Date.parse(a.at));
  const groups: {
    hour: string;
    rows: {
      key: string;
      event: MissionEvent;
      count: number;
      firstAt: string;
      members: MissionEvent[];
    }[];
  }[] = [];
  for (const event of sorted) {
    const hour = `${event.at.slice(0, 10)} ${event.at.slice(11, 13)}:00Z`;
    let group = groups.at(-1);
    if (!group || group.hour !== hour) {
      group = { hour, rows: [] };
      groups.push(group);
    }
    const last = group.rows.at(-1);
    if (last && same(last.event, event)) {
      last.count += 1;
      last.firstAt = event.at;
    } else group.rows.push({ key: event.id, event, count: 1, firstAt: event.at, members: [] });
  }
  return groups.map((g) => ({ hour: g.hour, rows: foldAcrossSpacecraft(g.rows) }));
}

/** Bucket size giving at most ~96 bars over the window (15 min over 24 h). */
export function densityBucketS(windowMs: number): number {
  const steps = [60, 300, 900, 1800, 3600];
  return steps.find((s) => windowMs / (s * 1000) <= 96) ?? 3600;
}

export type Bar = Readonly<{
  t: number;
  /** Stacked from the bottom: critical, caution, nominal, info (heights as fractions of max). */
  stack: readonly { severity: EventSeverity; from: number; to: number }[];
  total: number;
}>;

export function densityBars(density: Density): { bars: Bar[]; max: number } {
  const order = ["critical", "caution", "nominal", "info"] as const;
  const totals = density.buckets.map((b) => b.critical + b.caution + b.nominal + b.info);
  const max = Math.max(1, ...totals);
  const bars = density.buckets.map((b, i) => {
    let at = 0;
    const stack = order.map((severity) => {
      const from = at;
      at += b[severity] / max;
      return { severity, from, to: at };
    });
    return { t: Date.parse(b.t), stack: stack.filter((s) => s.to > s.from), total: totals[i] ?? 0 };
  });
  return { bars, max };
}
