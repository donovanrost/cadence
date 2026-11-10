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
 * One row: an event, a run of consecutive identical events (× count, first–last), or a fan-out:
 * more than FANOUT_AT events of one kind in one minute (`members`, expandable, with a kind-level
 * `label`; ux Timeline review 6/7).
 */
export type LogRow = Readonly<{
  key: string;
  event: MissionEvent;
  count: number;
  firstAt: string;
  members: readonly MissionEvent[];
  /** Fan-out rows: the kind in words ("Realized contact interval"); null otherwise. */
  label: string | null;
}>;

/** More than this many events of one kind in one minute fold into one row. */
export const FANOUT_AT = 3;

const RANK: Readonly<Record<EventSeverity, number>> = {
  critical: 3,
  caution: 2,
  nominal: 1,
  info: 0,
};
/**
 * Fold labels in operator words (ux timeline 11). "Ended (not verified)": a contact's end is the
 * booking's, not proof of a flown pass (S9). Unknown kinds fall back to the sentence-case key.
 */
const FOLD_WORDS: Readonly<Record<string, string>> = {
  realized_contact_interval: "Contacts ended (not verified)",
  scheduled_contact_interval: "Contacts scheduled",
  scheduled_contact_canceled: "Contacts canceled by the provider",
  limit_violation: "Limit violations",
  binding_set_activated: "Configurations activated",
  source_watermark_advanced: "Data sources caught up",
  catalog_revision_registered: "Catalog revisions registered",
  dashboard_published: "Dashboards published",
};
export function kindLabel(e: MissionEvent): string {
  const key = e.raw_kind ?? e.kind;
  const known = FOLD_WORDS[key];
  if (known) return known;
  const w = key.replaceAll("_", " ");
  return w.charAt(0).toUpperCase() + w.slice(1);
}

/**
 * Fan-out folds on (raw kind, minute), independent of the sentence: server sentences name each
 * spacecraft, so the text differs per row (ux review 7). The row takes its worst severity's mark.
 */
function foldFanOut(rows: LogRow[]): LogRow[] {
  const keyOf = (r: LogRow) => `${r.event.raw_kind ?? r.event.kind}|${r.event.at.slice(0, 16)}`;
  const groups = new Map<string, LogRow[]>();
  for (const row of rows) groups.set(keyOf(row), [...(groups.get(keyOf(row)) ?? []), row]);
  const out: LogRow[] = [];
  const emitted = new Set<string>();
  for (const row of rows) {
    const key = keyOf(row);
    const group = groups.get(key) ?? [row];
    if (group.reduce((n, r) => n + r.count, 0) <= FANOUT_AT) {
      out.push(row);
      continue;
    }
    if (emitted.has(key)) continue;
    emitted.add(key);
    const worst = group.reduce((a, b) => (RANK[b.event.severity] > RANK[a.event.severity] ? b : a));
    out.push({
      key: `fanout:${row.key}`,
      event: worst.event,
      count: group.reduce((n, r) => n + r.count, 0),
      firstAt: group.at(-1)?.firstAt ?? row.firstAt,
      members: group.map((r) => r.event),
      label: kindLabel(row.event),
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
      label: string | null;
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
    } else
      group.rows.push({
        key: event.id,
        event,
        count: 1,
        firstAt: event.at,
        members: [],
        label: null,
      });
  }
  return groups.map((g) => ({ hour: g.hour, rows: foldFanOut(g.rows) }));
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

/**
 * Timeline scope from the URL (backlog §2): `?sc=<scid>` one spacecraft, else the whole fleet.
 * The scid resolves through the fleet read to the id the events read filters on; an unknown scid
 * falls back to the fleet so nothing is silently hidden. The events read has no plane filter
 * (ops.md §events), so planes aren't offered.
 */
export type TimelineScope =
  | Readonly<{ kind: "fleet" }>
  | Readonly<{ kind: "spacecraft"; id: string; scid: number; name: string }>;

type ScopeFleet = readonly Readonly<{ id: string; scid: number; name: string }>[];

export function timelineScope(
  query: Readonly<Record<string, unknown>>,
  fleet: ScopeFleet,
): TimelineScope {
  const scid = typeof query.sc === "string" ? Number(query.sc) : NaN;
  const sc = Number.isInteger(scid) ? fleet.find((s) => s.scid === scid) : undefined;
  return sc ? { kind: "spacecraft", id: sc.id, scid: sc.scid, name: sc.name } : { kind: "fleet" };
}

/** ApSelect value for a scope: "fleet" or "sc:4". */
export const scopeValue = (s: TimelineScope) => (s.kind === "fleet" ? "fleet" : `sc:${s.scid}`);

/** Options: the fleet, and the current spacecraft when one is chosen (so it can be cleared). */
export function scopeOptions(current: TimelineScope) {
  return [
    { value: "fleet", label: "Whole fleet" },
    ...(current.kind === "spacecraft" ? [{ value: scopeValue(current), label: current.name }] : []),
  ];
}

/** URL query for a chosen scope value. */
export const scopeQuery = (value: string): Record<string, string | undefined> => ({
  sc: value.startsWith("sc:") ? value.slice(3) : undefined,
});
