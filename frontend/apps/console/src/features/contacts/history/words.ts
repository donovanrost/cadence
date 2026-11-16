import { formatCount, plural, type OpState } from "@/ui";
import { contactOpState, contactStateWord } from "@/features/scheduling/index.ts";
import type { Pass } from "../api.ts";
import { DAY_MS, isoDay, type StateFilter, type WeekSpan } from "./history.ts";
import { isHandStarted } from "../handStarted.ts";
import { neverLive, rowStateKey, type HistoryRow } from "./history.ts";
import type { ShortDay } from "./api.ts";

/** ux U78 (6404f0dbd, 55e57636a, 64706b98b): Contacts › History words. */

const md = (t: number) => isoDay(t).slice(5);
const hms = (t: number) => new Date(t).toISOString().slice(11, 19);
const hm = (t: number) => new Date(t).toISOString().slice(11, 16);

/** '11-14 02:59:40Z' (the phone's Start column; the callout's times). */
export const dayTime = (t: number) => `${md(t)} ${hms(t)}Z`;

/**
 * Window: the date always. '11-14 02:59:40 – 03:08:52Z'; across midnight the end names its day;
 * an end never recorded reads 'no end yet' (U20: claims neither still going nor ended).
 */
export function windowText(row: HistoryRow): string {
  const start = Date.parse(row.starts_at);
  // Defined, never live: one time (api: its realized_at), shown as 'Created …' by the table (U78).
  if (neverLive(row)) return dayTime(start);
  const p = row;
  if (p.ends_at === null) return `${dayTime(start)} – no end yet`;
  const end = Date.parse(p.ends_at);
  const sameDay = isoDay(start) === isoDay(end);
  return `${md(start)} ${hms(start)} – ${sameDay ? "" : `${md(end)} `}${hms(end)}Z`;
}

/**
 * The stepper's middle and the announcement: '11-09 – 11-15', this week '11-16 – now'; §4 adds the
 * year when the week isn't in this year ('2025-12-29 – 2026-01-04').
 */
export function weekLabel(span: WeekSpan, now: number): string {
  const last = span.to - DAY_MS;
  const thisYear = isoDay(now).slice(0, 4);
  const other = isoDay(span.from).slice(0, 4) !== thisYear || isoDay(last).slice(0, 4) !== thisYear;
  const day = (t: number) => (other ? isoDay(t) : md(t));
  return `${day(span.from)} – ${span.current ? "now" : day(last)}`;
}

export type HistoryNames = Readonly<{
  states: readonly StateFilter[];
  spacecraft: string | null;
  station: string | null;
}>;

/** 'Canceled, Rejected · EARENDIL-312 · Fairbanks' (the chosen filters, in the filter line's order). */
export function filterWords(n: HistoryNames): string[] {
  const states = n.states.length ? n.states.map((f) => f.word).join(", ") : null;
  return [states, n.spacecraft, n.station].filter((w): w is string => w !== null);
}

export type RowCounts = Readonly<{ passes: number; handStarted: number }>;

export function rowCounts(rows: readonly HistoryRow[]): RowCounts {
  const handStarted = rows.filter(isHandStarted).length;
  return { passes: rows.length - handStarted, handStarted };
}

/** '1,284 passes', '1,284 passes and 3 hand-started contacts' (U78), 'more than 500 passes'. */
export function countText(c: RowCounts, short: boolean): string {
  const passes = short ? "more than 500 passes" : plural(c.passes, "pass", "passes");
  return c.handStarted ? `${passes} and ${plural(c.handStarted, "hand-started contact")}` : passes;
}

/** Meta: '1,284 PASSES', '500+ PASSES' when a day is still cut. */
export function countMeta(count: number, short: boolean): string {
  return short ? "500+ PASSES" : `${formatCount(count)} ${count === 1 ? "PASS" : "PASSES"}`;
}

/** Polite: 'Week of 11-09 to 11-15, 1,284 passes.' */
export function announceText(span: WeekSpan, now: number, c: RowCounts, short: boolean): string {
  return `Week of ${weekLabel(span, now).replace(" – ", " to ")}, ${countText(c, short)}.`;
}

/** Filter line: '212 passes · Canceled · EARENDIL-312 · Fairbanks'. */
export function filterLine(c: RowCounts, short: boolean, n: HistoryNames): string {
  return [countText(c, short), ...filterWords(n)].join(" · ");
}

export function emptyText(span: WeekSpan, now: number, n: HistoryNames): string {
  const words = filterWords(n);
  if (words.length > 0) return `No passes match: ${[...words, weekLabel(span, now)].join(" · ")}.`;
  return span.current
    ? "No passes have started this week."
    : `No passes between ${md(span.from)} and ${md(span.to - DAY_MS)}.`;
}

/** The per-day callout (U78); spacecraft and state narrow in SQL before the cut, station doesn't (api). */
export function shortDayCallout(d: ShortDay): string {
  return `${md(Date.parse(`${d.day}T00:00:00Z`))} has more than 500 passes, and only the newest 500 are shown, back to ${hm(d.back)}Z. Pick a spacecraft or state to see the rest.`;
}

/** The text-3 row where the missing passes belong. */
export function shortDayRow(d: ShortDay): string {
  return `Passes on ${md(Date.parse(`${d.day}T00:00:00Z`))} before ${hm(d.back)}Z aren't shown.`;
}

/** 'Fairbanks' (the station's name, else its ref); the code shows beside it in mono. */
export function stationName(s: Pass["station"]): string {
  return s.name ?? s.ref ?? "—";
}

/**
 * The State cell: mark + the contact-state word. A hand-started contact reads its real word (U78:
 * never "Hand-started"); one defined but never live reads '○ Not started' (U78 5d52c9eb2).
 */
export function stateView(row: HistoryRow): Readonly<{ word: string; state: OpState }> {
  const key = rowStateKey(row);
  return key
    ? { word: contactStateWord[key], state: contactOpState(key) }
    : { word: "Not started", state: "off" };
}

/**
 * The drawer sheet's title, which names it for assistive tech (U78 5d52c9eb2):
 * 'Pass · EARENDIL-312 · Fairbanks', or 'Contact record · EARENDIL-312' for a hand-started one.
 */
export function drawerTitle(
  kind: "pass" | "record",
  spacecraft: string | null,
  station: string | null,
): string {
  const head = kind === "pass" ? "Pass" : "Contact record";
  return [head, spacecraft, kind === "pass" ? station : null]
    .filter((w): w is string => w !== null && w !== "")
    .join(" · ");
}
