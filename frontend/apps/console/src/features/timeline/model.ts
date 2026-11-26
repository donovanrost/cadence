import type { RouteLocationRaw } from "vue-router";
import type { Scid } from "@/api/index.ts";
import { formatHourMinute, type OpState } from "@/ui";
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
    // The Contacts drawer selects on the pass row id (api dc68a1cb4).
    case "pass":
      return { name: "ops.contacts", query: { contact: s.id } };
    case "dashboard":
      return { name: "ops.dashboard", params: { dashboardId: s.id } };
    case "catalog_revision":
      return { name: "setup.catalog" };
    // api 8d: applied / rolled-back configuration revisions (id is the revision number). Setup has
    // no per-revision page yet, so the list (ux U39).
    case "config_revision":
      return { name: "setup.revisions" };
    case "activation":
    case "unrecognized":
      return null;
  }
}

/**
 * The event's craft as a link, or null when it has none or the server couldn't name it (api 11-16:
 * an id outside the mission's name context). Never the id in its place.
 */
export function namedCraft(e: MissionEvent): { id: string; name: string; scid: Scid } | null {
  const sc = e.spacecraft;
  if (!sc || sc.name === null || sc.scid === null) return null;
  return { id: sc.id, name: sc.name, scid: sc.scid };
}
export function craftLink(e: MissionEvent): { label: string; to: RouteLocationRaw } | null {
  const sc = namedCraft(e);
  return sc ? { label: sc.name, to: { name: "ops.spacecraft", params: { scId: sc.scid } } } : null;
}

/** The server sentence names the spacecraft itself now; only prefix it when it doesn't. */
export const needsSpacecraftPrefix = (event: MissionEvent) => {
  const name = event.spacecraft?.name ?? null;
  return name !== null && !event.text.includes(name);
};

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
const foldKinds = [
  "realized_contact_interval",
  "scheduled_contact_interval",
  "scheduled_contact_canceled",
  "realized_contact_ended_early",
  "limit_violation",
  "binding_set_activated",
  "source_watermark_advanced",
  "source_watermark_settled",
  "source_watermark_caught_up",
  "source_watermark_retreated",
  "catalog_revision_registered",
  "dashboard_published",
  // U81 §2 (domain, api e27f68540): most of a contact's frames carried another SCID.
  "contact_scid_mismatch",
] as const;
const FOLD_WORDS: Readonly<Record<(typeof foldKinds)[number], string>> = {
  realized_contact_interval: "Contacts ended (not verified)",
  scheduled_contact_interval: "Contacts scheduled",
  // U55 (api): one kind for every cancel, by an operator, by Cadence (U56) or by the provider.
  scheduled_contact_canceled: "Contacts canceled",
  realized_contact_ended_early: "Contacts ended early",
  limit_violation: "Limit violations",
  binding_set_activated: "Configurations activated",
  source_watermark_advanced: "Data sources caught up",
  // U60 (api 1bc887596): state changes only; old `advanced` rows keep their label until they age out.
  source_watermark_settled: "Telemetry stored",
  source_watermark_caught_up: "Telemetry caught up",
  source_watermark_retreated: "Telemetry moved back",
  catalog_revision_registered: "Catalog revisions registered",
  dashboard_published: "Dashboards published",
  contact_scid_mismatch: "Frames with another SCID",
};
export function kindLabel(e: MissionEvent): string {
  return rawKindLabel(e.raw_kind ?? e.kind);
}
/** A raw kind in the fold words ('Contacts canceled'), else sentence-cased (U71 A9b options). */
export function rawKindLabel(key: string): string {
  const known = foldKinds.find((k) => k === key);
  if (known) return FOLD_WORDS[known];
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
 * Timeline scope from the URL (backlog §2): `?sc=<scid>` one spacecraft, `?plane=<n>` one orbital
 * plane (api: events and density take plane), else the whole fleet. The scid resolves through the
 * fleet read to the id the events read filters on; an unknown scid falls back to the fleet so
 * nothing is silently hidden.
 */
export type TimelineScope =
  | Readonly<{ kind: "fleet" }>
  | Readonly<{ kind: "spacecraft"; id: string; scid: number; name: string }>
  | Readonly<{ kind: "plane"; plane: number }>;

type ScopeFleet = readonly Readonly<{
  id: string;
  scid: number;
  name: string;
  plane: number | null;
}>[];

export function timelineScope(
  query: Readonly<Record<string, unknown>>,
  fleet: ScopeFleet,
): TimelineScope {
  const scid = typeof query.sc === "string" ? Number(query.sc) : NaN;
  const sc = Number.isInteger(scid) ? fleet.find((s) => s.scid === scid) : undefined;
  if (sc) return { kind: "spacecraft", id: sc.id, scid: sc.scid, name: sc.name };
  const plane = typeof query.plane === "string" && query.plane !== "" ? Number(query.plane) : NaN;
  return Number.isInteger(plane) ? { kind: "plane", plane } : { kind: "fleet" };
}

/** ApSelect value for a scope: "fleet", "plane:3", "sc:4". */
export const scopeValue = (s: TimelineScope) =>
  s.kind === "fleet" ? "fleet" : s.kind === "plane" ? `plane:${s.plane}` : `sc:${s.scid}`;

/** Options: the fleet, the current spacecraft when one is chosen, and each plane in the fleet. */
export function scopeOptions(fleet: ScopeFleet, current: TimelineScope) {
  const planes = [
    ...new Set(fleet.map((s) => s.plane).filter((p): p is number => p !== null)),
  ].sort((a, b) => a - b);
  return [
    { value: "fleet", label: "Whole fleet" },
    ...(current.kind === "spacecraft" ? [{ value: scopeValue(current), label: current.name }] : []),
    ...planes.map((p) => ({ value: `plane:${p}`, label: `Plane ${p}` })),
  ];
}

/** URL query for a chosen scope value. */
export function scopeQuery(value: string): Record<string, string | undefined> {
  if (value.startsWith("sc:")) return { sc: value.slice(3), plane: undefined };
  if (value.startsWith("plane:")) return { plane: value.slice(6), sc: undefined };
  return { sc: undefined, plane: undefined };
}

/**
 * ux (Timeline default view): routine data events stay hidden by default, but a caution or
 * critical one shows whatever its kind (a source going down, a credential failing). Merged newest
 * first, without duplicates.
 */
export function withAlertingData<T extends { id: string; at: string; severity: string }>(
  main: readonly T[],
  data: readonly T[],
): T[] {
  const seen = new Set(main.map((e) => e.id));
  const alerting = data.filter(
    (e) => !seen.has(e.id) && (e.severity === "caution" || e.severity === "critical"),
  );
  return [...main, ...alerting].sort((a, b) => Date.parse(b.at) - Date.parse(a.at));
}

/**
 * E1 brush: a drag from fraction `a` to `b` of the strip as a window; null under 1% of the
 * strip (a click, not a brush).
 */
export function brushRange(
  window: Readonly<{ from: number; to: number }>,
  a: number,
  b: number,
): { from: number; to: number } | null {
  if (Math.abs(b - a) < 0.01) return null;
  const span = window.to - window.from;
  const t = (f: number) => Math.round(window.from + Math.min(1, Math.max(0, f)) * span);
  return { from: t(Math.min(a, b)), to: t(Math.max(a, b)) };
}

/**
 * A failed live refresh keeps the log but says how old it is (U72): nothing else on the Timeline
 * refreshes it, so a log that stopped moving must not look current. Null while refreshes succeed.
 */
export const staleLine = (refreshFailed: boolean, receivedAt: Date): string | null =>
  refreshFailed ? `Couldn't refresh. Showing events as of ${formatHourMinute(receivedAt)}.` : null;
