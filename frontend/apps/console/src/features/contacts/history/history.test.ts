import { describe, expect, it } from "vite-plus/test";
import {
  apiStates,
  ledgerRows,
  mondayOf,
  parseHistoryQuery,
  stepWeek,
  weekDays,
  weekSpan,
} from "./history.ts";
import { ledgerItems } from "./useHistory.ts";
import { row } from "./testRows.ts";

/** Monday 2026-11-16 10:30Z: this week is 11-16 – now. */
const NOW = Date.parse("2026-11-16T10:30:00Z");

describe("History weeks (U78)", () => {
  it("weeks are ISO, Monday 00:00Z; ?week= normalizes and a future or bad one is this week", () => {
    expect(new Date(mondayOf(Date.parse("2026-11-15T23:59:59Z"))).toISOString()).toBe(
      "2026-11-09T00:00:00.000Z",
    );
    const week = (v: string | undefined) => parseHistoryQuery(v ? { week: v } : {}, NOW).week;
    expect(week(undefined)).toBe("2026-11-16");
    expect(week("2026-11-12")).toBe("2026-11-09");
    expect(week("2026-11-30")).toBe("2026-11-16");
    expect(week("2026-02-30")).toBe("2026-11-16");
    expect(week("nonsense")).toBe("2026-11-16");
  });

  it("this week runs to now; Newer stops at it; a cut week re-reads its begun days", () => {
    const span = weekSpan("2026-11-16", NOW);
    expect(span).toEqual({ from: Date.parse("2026-11-16T00:00:00Z"), to: NOW, current: true });
    expect(weekSpan("2026-11-09", NOW).current).toBe(false);
    expect(stepWeek("2026-11-16", 1, NOW)).toBeNull();
    expect(stepWeek("2026-11-09", 1, NOW)).toBe("2026-11-16");
    expect(stepWeek("2026-11-16", -1, NOW)).toBe("2026-11-09");
    expect(weekDays(span)).toEqual([{ from: span.from, to: NOW }]);
    expect(weekDays(weekSpan("2026-11-09", NOW))).toHaveLength(7);
  });

  it("State words go in ?state= and send the union of their reservation states", () => {
    const q = parseHistoryQuery({ state: "in_contact,unknown,bogus" }, NOW);
    expect(q.states.map((f) => f.key)).toEqual(["in_contact", "unknown"]);
    expect(apiStates(q.states)).toEqual(["confirmed", "active", "unknown", "failed"]);
    expect(apiStates([])).toBeNull();
    const ended = parseHistoryQuery({ state: "ended" }, NOW).states;
    expect(apiStates(ended, false)).toEqual(["completed"]);
    expect(apiStates(ended)).toEqual(["completed", "stopped"]);
    expect(apiStates(ended, true)).toEqual(["completed", "stopped"]);
  });
});

describe("History rows (U78)", () => {
  const span = weekSpan("2026-11-09", NOW);
  const rows = [
    row({ id: "old", starts_at: "2026-11-08T23:55:00Z", ends_at: "2026-11-09T00:05:00Z" }),
    row({ id: "a", starts_at: "2026-11-12T02:59:40Z" }),
    row({ id: "b", starts_at: "2026-11-14T02:59:40Z", state: "confirmed", pass_phase: "pass" }),
    row({ id: "c", starts_at: "2026-11-13T01:00:00Z", state: "confirmed" }),
    row({ id: "rc-1", booked: false, starts_at: "2026-11-13T05:00:00Z", state: "active" }),
    row({ id: "a", starts_at: "2026-11-12T02:59:40Z" }),
  ];

  it("lists rows that started in the week, once each, newest first", () => {
    expect(ledgerRows(rows, span, []).map((r) => r.id)).toEqual(["b", "rc-1", "c", "a"]);
  });

  it("splits Confirmed from In contact by phase; a live hand-started contact is In contact", () => {
    const q = (state: string) => parseHistoryQuery({ state }, NOW).states;
    expect(ledgerRows(rows, span, q("confirmed")).map((r) => r.id)).toEqual(["c"]);
    expect(ledgerRows(rows, span, q("in_contact")).map((r) => r.id)).toEqual(["b", "rc-1"]);
    expect(ledgerRows(rows, span, q("ended")).map((r) => r.id)).toEqual(["a"]);
  });

  it("a contact Cadence closed before it went live matches no State, not even Ended (api not_started)", () => {
    const swept = row({
      id: "rc-9",
      booked: false,
      state: "stopped",
      not_started: true,
      starts_at: "2026-11-13T02:59:40Z",
      ends_at: "2026-11-13T03:59:40Z",
    });
    const ended = parseHistoryQuery({ state: "ended" }, NOW).states;
    expect(ledgerRows([swept], span, ended)).toEqual([]);
    expect(ledgerRows([swept], span, []).map((r) => r.id)).toEqual(["rc-9"]);
  });

  it("puts a cut day's row below that day's oldest shown row (the read keeps the newest 500)", () => {
    const shown = ledgerRows(rows, span, []);
    const keys = ledgerItems(shown, [
      { day: "2026-11-13", back: Date.parse("2026-11-13T01:00:00Z") },
      { day: "2026-11-10", back: Date.parse("2026-11-11T00:00:00Z") },
    ]).map((i) => i.key);
    expect(keys).toEqual(["b", "rc-1", "c", "gap-2026-11-13", "a", "gap-2026-11-10"]);
  });
});
