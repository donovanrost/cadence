import type { RouteLocationRaw } from "vue-router";
import {
  decoders as d,
  isKnown,
  vocabularyText,
  type Decoded,
  type Scid,
  type SpacecraftId,
  stationRef,
  type Unrecognized,
} from "@/api/index.ts";
import { plural, type OpState } from "@/ui";
import { GROUP_AT, type QueueItem } from "./queue.ts";

/**
 * Queue sources `missed_pass` and `station` (ops.md b7008dd6, ux U11/U35). Missed passes group
 * client-side when 3 or more share a station and cause; the group takes its members' highest
 * priority. Words only; the server ranks.
 */

/** Missed-pass causes the console words; anything else is the provider's own reason. */
const missedCauses = [
  "no_acquisition",
  "station_unavailable",
  "provider_canceled",
  "provider_rejected",
  "not_ingested",
] as const;
type MissedCause = (typeof missedCauses)[number];

export const missedPassReader = d.object({
  reservation_id: d.token,
  station: stationRef,
  planned_aos: d.timestamp,
  outcome: d.knownText(["missed", "failed"] as const),
  /** A key the console words (CAUSES), else the provider's own reason. */
  cause: d.nullable(d.knownText(missedCauses)),
  owner: d.nullable(d.knownText(["provider", "us", "weather", "unknown"] as const)),
});
export const nextContactReader = d.object({
  reservation_id: d.token,
  station: stationRef,
  aos: d.timestamp,
});
export const stationIssueReader = d.object({
  station: stationRef,
  window: d.object({
    id: d.token,
    kind: d.knownText(["outage", "maintenance", "degraded"] as const),
    starts_at: d.timestamp,
    ends_at: d.nullable(d.timestamp),
    // free-text: who reported the window (a provider or operator note)
    source: d.nullable(d.string),
  }),
  affected: d.array(
    d.object({ reservation_id: d.token, spacecraft_id: d.token, aos: d.timestamp }),
    1_000,
  ),
});
type MissedPass = Decoded<typeof missedPassReader>;
type NextContact = Decoded<typeof nextContactReader>;
type StationIssue = Decoded<typeof stationIssueReader>;

const CAUSES: Readonly<Record<MissedCause, string>> = {
  no_acquisition: "no acquisition",
  station_unavailable: "station unavailable",
  provider_canceled: "canceled by the provider",
  provider_rejected: "rejected by the provider",
  not_ingested: "no data ingested",
};
/** A known key in words; the provider's own reason in sentence case. */
/** The cause as text for a grouping key: its key, or the provider's own words. */
const causeKey = (cause: MissedCause | Unrecognized | null): string =>
  cause === null ? "" : isKnown(cause) ? cause : cause.unrecognized;
export function causeWords(cause: MissedCause | Unrecognized | null): string {
  if (!cause) return "cause unknown";
  if (isKnown(cause)) return CAUSES[cause];
  const w = cause.unrecognized.replaceAll("_", " ").trim();
  return w.charAt(0).toLowerCase() + w.slice(1);
}
const OWNER: Readonly<Record<"provider" | "us" | "weather" | "unknown", string | null>> = {
  provider: "the provider's side",
  us: "our side",
  weather: "weather",
  unknown: null,
};
const WINDOW: Readonly<Record<"outage" | "maintenance" | "degraded", string>> = {
  outage: "outage",
  maintenance: "maintenance",
  degraded: "degraded",
};

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;
const code = (s: MissedPass["station"]) => s.code ?? s.name ?? "a station";

export type MissedItem = Readonly<{
  id: string;
  priority: 1 | 2 | 3;
  state: OpState;
  scName: string;
  spacecraftId: SpacecraftId;
  scid: Scid;
  missed: readonly MissedPass[];
  next: NextContact | null;
}>;

/** Where Review goes: the pass review for the day of the (latest) missed pass. */
const reviewTo = (aos: string): RouteLocationRaw => ({
  name: "ops.contacts.review",
  query: { day: aos.slice(0, 10) },
});

/** One spacecraft's row: "EARENDIL-004 · missed pass at SVB-1 · antenna fault". */
function oneRow(m: MissedItem, horizonH: number): QueueItem {
  const last = m.missed[0];
  const where = last ? ` at ${code(last.station)} · ${causeWords(last.cause)}` : "";
  const owner = last?.owner && isKnown(last.owner) ? OWNER[last.owner] : null;
  const next = m.next
    ? `Next booked contact at ${code(m.next.station)}.`
    : `No booked contact in the next ${horizonH} h.`;
  return {
    key: m.id,
    priority: m.priority,
    state: m.state,
    title: `${m.scName} · ${plural(m.missed.length, "missed pass", "missed passes")}${where}`,
    titleTo: { name: "ops.spacecraft", params: { scId: m.scid, tab: "investigate" } },
    sentence: `${last ? `${last.outcome === "failed" ? "Failed" : "Missed"} at ${hhmm(last.planned_aos)}${owner ? ` (${owner})` : ""}. ` : ""}${next}`,
    meta: null,
    ...(m.next ? { due: { label: "AOS", at: m.next.aos } } : {}),
    action: { label: "Review", to: reviewTo(last?.planned_aos ?? new Date().toISOString()) },
    spacecraftIds: [m.spacecraftId],
  } satisfies QueueItem;
}

/**
 * Missed-pass rows (U35): 3 or more spacecraft whose latest miss shares a station and cause become
 * one row, "4 missed passes at SVB-1 · antenna fault", with "EARENDIL-004, -011, -019 and 1 more ·
 * 2 have no contact in the next 6 h".
 */
export function missedPassRows(items: readonly MissedItem[], horizonS: number): QueueItem[] {
  const horizonH = Math.round(horizonS / 3600);
  const groups = new Map<string, MissedItem[]>();
  for (const m of items) {
    const last = m.missed[0];
    const k = last
      ? `${last.station.id ?? last.station.ref ?? code(last.station)}|${causeKey(last.cause)}`
      : m.id;
    groups.set(k, [...(groups.get(k) ?? []), m]);
  }
  return [...groups.values()].flatMap((g) => {
    const first = g[0];
    if (!first) return [];
    if (g.length < GROUP_AT) return g.map((m) => oneRow(m, horizonH));
    const last = first.missed[0];
    const top = g.reduce((p, m) => (m.priority < p.priority ? m : p), first);
    const names = g.map((m, i) =>
      i === 0 ? m.scName : `-${m.scName.split("-").pop() ?? m.scName}`,
    );
    const shown = names.slice(0, 3).join(", ");
    const more = g.length > 3 ? ` and ${g.length - 3} more` : "";
    const uncovered = g.filter((m) => m.next === null).length;
    const total = g.reduce((n, m) => n + m.missed.length, 0);
    return [
      {
        key: `missed:${first.id}`,
        priority: top.priority,
        state: top.state,
        title: `${plural(total, "missed pass", "missed passes")}${last ? ` at ${code(last.station)} · ${causeWords(last.cause)}` : ""}`,
        titleTo: null,
        sentence: `${shown}${more}${uncovered ? ` · ${uncovered} ${uncovered === 1 ? "has" : "have"} no contact in the next ${horizonH} h` : ""}`,
        meta: null,
        action: { label: "Review", to: reviewTo(last?.planned_aos ?? new Date().toISOString()) },
        spacecraftIds: g.map((m) => m.spacecraftId),
      } satisfies QueueItem,
    ];
  });
}

/** A station issue: "SVB-1 · outage overlaps 3 booked passes", Re-plan for that station. */
export function stationRow(
  id: string,
  issue: StationIssue,
  base: Omit<QueueItem, "key" | "title" | "titleTo" | "sentence" | "action" | "meta">,
): QueueItem {
  const st = issue.station.code ?? issue.station.name ?? "A station";
  const w = issue.window;
  const kind = vocabularyText(w.kind, WINDOW).replaceAll("_", " ");
  const until = w.ends_at ? ` until ${hhmm(w.ends_at)}` : " · no end reported";
  const n = issue.affected.length;
  const first = [...issue.affected].sort((a, b) => Date.parse(a.aos) - Date.parse(b.aos))[0];
  return {
    ...base,
    key: id,
    title: `${st} · ${kind} overlaps ${plural(n, "booked pass", "booked passes")}`,
    titleTo: null,
    sentence: `${kind.charAt(0).toUpperCase()}${kind.slice(1)} from ${hhmm(w.starts_at)}${until}${w.source ? ` (${w.source})` : ""}.`,
    meta: null,
    ...(first ? { due: { label: "AOS", at: first.aos } } : {}),
    action: {
      label: "Re-plan",
      to: issue.station.id
        ? { name: "ops.contacts.replan.station", params: { stationId: issue.station.id } }
        : { name: "ops.contacts.replan" },
    },
  };
}
