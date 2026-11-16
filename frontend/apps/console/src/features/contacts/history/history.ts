import type { LocationQuery } from "vue-router";
import { contactState, type ContactState } from "@/features/scheduling/index.ts";
import type { Pass } from "../api.ts";
import { isHandStarted, type HandStartedContact } from "../handStarted.ts";

/**
 * Contacts › History (§11c(C) A12, ux U78): booked passes whose window has started, newest first,
 * one ISO week at a time (Monday 00:00Z to Monday; the passes read caps a window at 7 days).
 * `?week=` is the Monday; any other date normalizes to its week. The current week runs to now.
 */
export const DAY_MS = 86_400_000;
export const WEEK_MS = 7 * DAY_MS;

export const isoDay = (t: number) => new Date(t).toISOString().slice(0, 10);
const dayStart = (t: number) => Math.floor(t / DAY_MS) * DAY_MS;
const parseDay = (v: string) => Date.parse(`${v}T00:00:00Z`);

/** The Monday 00:00Z on or before `t`. */
export function mondayOf(t: number): number {
  const d = dayStart(t);
  // getUTCDay: Sunday 0 … Saturday 6; Monday-based offset 0 … 6.
  return d - ((new Date(d).getUTCDay() + 6) % 7) * DAY_MS;
}

/**
 * U78: History lists hand-started contacts (`include=hand_started`, api's opt-in `booked: false`
 * rows; live 11-16 08:16Z). Off, it asks for booked passes only and says so in a foot line.
 */
export const HAND_STARTED_LISTED = true;

/**
 * The State filter (U78): the console's contact-state words, never raw lifecycles, each with the
 * reservation states it sends as `states=`. Unknown sends unknown + failed; Confirmed and In contact
 * both send confirmed + active, and rows are split by phase on the client (contactState).
 */
export const stateFilters = [
  { key: "requesting", word: "Requesting", states: ["requesting"] },
  { key: "requested", word: "Requested", states: ["pending"] },
  { key: "confirmed", word: "Confirmed", states: ["confirmed", "active"] },
  { key: "in_contact", word: "In contact", states: ["confirmed", "active"] },
  { key: "ended", word: "Ended · not verified", states: ["completed"] },
  { key: "rejected", word: "Rejected", states: ["rejected"] },
  { key: "unknown", word: "Unknown", states: ["unknown", "failed"] },
  { key: "canceling", word: "Canceling", states: ["canceling"] },
  { key: "canceled", word: "Canceled", states: ["canceled"] },
] as const satisfies readonly {
  key: ContactState;
  word: string;
  states: readonly Pass["state"][];
}[];

export type StateFilter = (typeof stateFilters)[number];
export type StateFilterKey = StateFilter["key"];

export type HistoryQuery = Readonly<{
  /** The week's Monday, `YYYY-MM-DD`. */
  week: string;
  spacecraftId: string | null;
  station: string | null;
  /** The chosen State words (`?state=confirmed,in_contact`), in the filter's order. */
  states: readonly StateFilter[];
  /** The pass open in the drawer (`?contact=`). */
  contact: string | null;
}>;

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

function text(v: LocationQuery[string] | undefined): string | null {
  return typeof v === "string" && v !== "" ? v : null;
}

/** A valid `YYYY-MM-DD`, else null (2026-02-30 is not a day). */
export function validDay(v: string | null): number | null {
  if (!v || !DAY_RE.test(v)) return null;
  const t = parseDay(v);
  return Number.isFinite(t) && isoDay(t) === v ? t : null;
}

export function currentWeek(now: number): string {
  return isoDay(mondayOf(now));
}

function parseWeek(v: string | null, now: number): string {
  const t = validDay(v);
  if (t === null) return currentWeek(now);
  const monday = mondayOf(t);
  // A later week has nothing that has started (Live and Plan own the future).
  return monday > mondayOf(now) ? currentWeek(now) : isoDay(monday);
}

/** `?state=` keys back to their filters; unknown keys drop. */
export function parseStateFilters(v: string | null): StateFilter[] {
  const keys = new Set(v ? v.split(",") : []);
  return stateFilters.filter((f) => keys.has(f.key));
}

/**
 * What `states=` sends for the chosen words: the union of their reservation states, or null. With
 * hand-started rows listed, Ended also sends `stopped` (a contact's own word, fe-ops' review);
 * 'Not started' (defined) has no filter option.
 */
export function apiStates(chosen: readonly StateFilter[], handStarted = HAND_STARTED_LISTED) {
  if (chosen.length === 0) return null;
  const states: string[] = chosen.flatMap((f) => f.states);
  if (handStarted && chosen.some((f) => f.key === "ended")) states.push("stopped");
  return [...new Set(states)];
}

export function parseHistoryQuery(q: LocationQuery, now: number): HistoryQuery {
  return {
    week: parseWeek(text(q.week), now),
    spacecraftId: text(q.spacecraft),
    station: text(q.station),
    states: parseStateFilters(text(q.state)),
    contact: text(q.contact),
  };
}

export type WeekSpan = Readonly<{ from: number; to: number; current: boolean }>;

/** The week's span: Monday 00:00Z to the next Monday, or to now for the current week. */
export function weekSpan(week: string, now: number): WeekSpan {
  const from = parseDay(week);
  const current = from === mondayOf(now);
  return { from, to: current ? now : from + WEEK_MS, current };
}

/** The Monday `by` weeks away, or null past the current week. */
export function stepWeek(week: string, by: number, now: number): string | null {
  const next = parseDay(week) + by * WEEK_MS;
  return next > mondayOf(now) ? null : isoDay(next);
}

/** The week's UTC days that have begun, for re-reading a truncated week a day at a time. */
export function weekDays(span: WeekSpan): { from: number; to: number }[] {
  const days: { from: number; to: number }[] = [];
  for (let t = span.from; t < span.to; t += DAY_MS) {
    days.push({ from: t, to: Math.min(t + DAY_MS, span.to) });
  }
  return days;
}

/** A History row: a reservation's pass, or a hand-started contact (U78, `booked: false`). */
export type HistoryRow = Pass | HandStartedContact;

/**
 * A hand-started contact that never went live (api's `not_started`: defined, or stopped by Cadence's
 * never-started sweep); before the key ships, state `defined` says so.
 */
export function neverLive(row: HistoryRow): boolean {
  return isHandStarted(row) && (row.not_started ?? row.state === "defined");
}

/**
 * The State word a row reads under (U78): a pass by lead's contactState; a hand-started contact by
 * its own lifecycle (active is in contact, completed and stopped have ended); one that never went
 * live has no contact word ('Not started') and matches no State filter.
 */
export function rowStateKey(row: HistoryRow): ContactState | null {
  if (!isHandStarted(row)) return contactState(row);
  if (neverLive(row)) return null;
  switch (row.state) {
    case "active":
      return "in_contact";
    case "completed":
    case "stopped":
      return "ended";
    default:
      return null;
  }
}

/**
 * The ledger's rows: those that STARTED inside the span (a pass crossing Monday 00:00Z belongs to
 * the week it started in, so it isn't listed twice), under the chosen State words, newest first.
 */
export function ledgerRows(
  rows: readonly HistoryRow[],
  span: Pick<WeekSpan, "from" | "to">,
  chosen: readonly StateFilter[],
): HistoryRow[] {
  const keys = new Set<ContactState>(chosen.map((f) => f.key));
  const seen = new Set<string>();
  const out: HistoryRow[] = [];
  for (const r of rows) {
    const start = Date.parse(r.starts_at);
    if (start < span.from || start >= span.to || seen.has(r.id)) continue;
    const key = rowStateKey(r);
    if (keys.size > 0 && (key === null || !keys.has(key))) continue;
    seen.add(r.id);
    out.push(r);
  }
  return out.sort(
    (a, b) => Date.parse(b.starts_at) - Date.parse(a.starts_at) || a.id.localeCompare(b.id),
  );
}
