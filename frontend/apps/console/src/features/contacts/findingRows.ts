import type { RouteLocationRaw } from "vue-router";
import { plural } from "@/ui";
import { findingTitle, type Finding } from "./findings.ts";

/**
 * D4 rows (ux §7 review, 83ee8a26): coverage gaps of the same length from the same moment fold into
 * one row the way U37 does ("500 spacecraft have no pass in the next 6 h." + Show all + one Open in
 * Plan). Conflicts stay one row each: each is its own decision. Durations read "6 h" (§4).
 */
export type FindingRow = Readonly<{
  key: string;
  state: "crit" | "caution";
  title: string;
  sentence: string;
  /** Plan day for Open in Plan. */
  day: string;
  /** The folded members, for the Show all sheet; null on a single row. */
  members: readonly FindingMember[] | null;
  /** A single coverage gap: Book a pass prefilled with its spacecraft and window (L15). */
  book: Readonly<{ spacecraftId: string; from: number; to: number }> | null;
}>;
export type FindingMember = Readonly<{
  key: string;
  text: string;
  detail: string | null;
  to: RouteLocationRaw | null;
}>;

const FOLD_AT = 3;
const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;
const day = (iso: string | null, now: Date) => (iso ?? now.toISOString()).slice(0, 10);

/** `6 h`, `1.5 h`, `40 min`. */
export function duration(seconds: number): string {
  if (seconds < 3_600) return `${Math.max(1, Math.round(seconds / 60))} min`;
  const h = seconds / 3_600;
  return `${Number.isInteger(h) ? h : h.toFixed(1)} h`;
}

const state = (f: Finding) => (f.severity === "critical" ? "crit" : "caution");
const gapOf = (f: Finding) => (f.kind === "coverage_gap" && f.gap && f.spacecraft ? f.gap : null);
const scName = (f: Finding) => f.spacecraft?.name ?? "Unknown spacecraft";

/** Within a minute of now reads "in the next 6 h"; later reads "for 6 h from 03:20Z". */
function span(gap: NonNullable<Finding["gap"]>, now: Date): string {
  const soon = Date.parse(gap.from) - now.getTime() <= 60_000;
  return soon
    ? `in the next ${duration(gap.seconds)}`
    : `for ${duration(gap.seconds)} from ${hhmm(gap.from)}`;
}

function single(f: Finding, now: Date): FindingRow {
  const gap = gapOf(f);
  return {
    key: f.id,
    state: state(f),
    title: findingTitle(f),
    sentence: gap ? `${scName(f)} has no pass ${span(gap, now)}.` : f.message,
    day: day(f.at, now),
    members: null,
    book:
      gap && f.spacecraft
        ? { spacecraftId: f.spacecraft.id, from: Date.parse(gap.from), to: Date.parse(gap.to) }
        : null,
  };
}

function member(f: Finding): FindingMember {
  const scid = f.spacecraft?.scid;
  return {
    key: f.id,
    text: scName(f),
    detail: f.gap ? `no pass ${hhmm(f.gap.from)}–${hhmm(f.gap.to)}` : null,
    to:
      scid == null ? null : { name: "ops.spacecraft", params: { scId: scid, tab: "investigate" } },
  };
}

export function findingRows(findings: readonly Finding[], now: Date = new Date()): FindingRow[] {
  const groups = new Map<string, Finding[]>();
  const order: (Finding | string)[] = [];
  for (const f of findings) {
    const gap = gapOf(f);
    if (!gap) {
      order.push(f);
      continue;
    }
    const key = `gap:${gap.from}:${gap.seconds}`;
    const g = groups.get(key);
    if (g) g.push(f);
    else {
      groups.set(key, [f]);
      order.push(key);
    }
  }
  return order.flatMap((o): FindingRow[] => {
    if (typeof o !== "string") return [single(o, now)];
    const g = groups.get(o) ?? [];
    const first = g[0];
    if (!first) return [];
    if (g.length < FOLD_AT) return g.map((f) => single(f, now));
    const gap = gapOf(first);
    return [
      {
        key: o,
        state: g.some((f) => f.severity === "critical") ? "crit" : "caution",
        title: findingTitle(first),
        sentence: `${plural(g.length, "spacecraft", "spacecraft")} have no pass ${gap ? span(gap, now) : ""}.`,
        day: day(first.at, now),
        members: g.map(member),
        book: null,
      },
    ];
  });
}
