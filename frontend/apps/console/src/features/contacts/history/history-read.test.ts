import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api/index.ts";
import { fetchWeekLedger } from "./api.ts";
import { weekSpan } from "./history.ts";
import { row } from "./testRows.ts";
import {
  announceText,
  countText,
  drawerTitle,
  emptyText,
  filterLine,
  shortDayCallout,
  shortDayRow,
  stateView,
  weekLabel,
  windowText,
} from "./words.ts";

const NOW = Date.parse("2026-11-16T10:30:00Z");
const span = weekSpan("2026-11-09", NOW);
const pass = (id: string, starts_at: string) => ({
  id,
  kind: "contact",
  state: "completed",
  pass_phase: null,
  delivery_state: null,
  spacecraft_id: null,
  spacecraft: null,
  station: { ref: "FBK", id: null, code: "FBK", name: "Fairbanks" },
  antenna: null,
  starts_at,
  ends_at: starts_at,
  uplink_capable: null,
  source: { provider: "p", provider_name: "Simulator", synthetic: true },
  max_elevation_deg: null,
  plan: null,
});

afterEach(() => vi.unstubAllGlobals());

describe("History's week read (U78 truncation)", () => {
  it("re-reads a truncated week a UTC day at a time and names the days still cut", async () => {
    const urls: string[] = [];
    vi.stubGlobal("fetch", (input: string) => {
      urls.push(input);
      const from = new URL(input, "http://x").searchParams.get("from") ?? "";
      const day = from.slice(0, 10);
      const truncated = urls.length === 1 || day === "2026-11-12";
      const passes = urls.length === 1 ? [] : [pass(`p-${day}`, `${day}T18:40:00.000Z`)];
      return Promise.resolve(
        new Response(JSON.stringify({ data: { from, to: from, truncated, passes } })),
      );
    });
    const r = await fetchWeekLedger(missionId("m-1"), span, {
      spacecraftId: "sc-312",
      station: null,
      states: ["completed"],
    });
    if (!r.ok) throw new Error("read failed");
    expect(urls).toHaveLength(8);
    expect(urls[0]).toContain("spacecraft_id=sc-312");
    expect(urls[0]).toContain("states=completed");
    expect(urls[0]).not.toContain("include=");
    expect(r.value.passes).toHaveLength(7);
    expect(r.value.truncated).toBe(true);
    expect(r.value.shortDays).toEqual([
      { day: "2026-11-12", through: Date.parse("2026-11-12T18:40:00Z") },
    ]);
  });

  it("an untruncated week is one read", async () => {
    const fetch = vi.fn(() =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            data: {
              from: "2026-11-09T00:00:00Z",
              to: "2026-11-16T00:00:00Z",
              truncated: false,
              passes: [],
            },
          }),
        ),
      ),
    );
    vi.stubGlobal("fetch", fetch);
    const r = await fetchWeekLedger(missionId("m-1"), span, {
      spacecraftId: null,
      station: null,
      states: null,
    });
    expect(r.ok && r.value.shortDays).toEqual([]);
    expect(fetch).toHaveBeenCalledTimes(1);
  });
});

describe("History words (U78)", () => {
  it("windows carry the date, name a crossed midnight, an unrecorded end, a never-live contact", () => {
    const w = (o: Record<string, unknown>) => windowText(row({ id: "r", ...o }));
    expect(w({ starts_at: "2026-11-14T02:59:40Z", ends_at: "2026-11-14T03:08:52Z" })).toBe(
      "11-14 02:59:40 – 03:08:52Z",
    );
    expect(w({ starts_at: "2026-11-14T23:59:40Z", ends_at: "2026-11-15T00:08:52Z" })).toBe(
      "11-14 23:59:40 – 11-15 00:08:52Z",
    );
    const hand = { booked: false, starts_at: "2026-11-16T02:59:40Z", ends_at: null };
    expect(w({ ...hand, state: "active" })).toBe("11-16 02:59:40Z – no end yet");
    expect(w({ ...hand, state: "defined" })).toBe("11-16 02:59:40Z");
  });

  it("sheet titles name their subject", () => {
    expect(drawerTitle("pass", "EARENDIL-312", "Fairbanks")).toBe(
      "Pass · EARENDIL-312 · Fairbanks",
    );
    expect(drawerTitle("record", "EARENDIL-312", null)).toBe("Contact record · EARENDIL-312");
    expect(drawerTitle("pass", null, null)).toBe("Pass");
  });

  it("week labels, with the year off this year", () => {
    expect(weekLabel(span, NOW)).toBe("11-09 – 11-15");
    expect(weekLabel(weekSpan("2026-11-16", NOW), NOW)).toBe("11-16 – now");
    expect(weekLabel(weekSpan("2025-12-29", NOW), NOW)).toBe("2025-12-29 – 2026-01-04");
  });

  it("counts, the announcement, the filter line and the empty lines", () => {
    const c = { passes: 1284, handStarted: 3 };
    expect(countText(c, false)).toBe("1,284 passes and 3 hand-started contacts");
    expect(announceText(span, NOW, { passes: 1284, handStarted: 0 }, false)).toBe(
      "Week of 11-09 to 11-15, 1,284 passes.",
    );
    const names = {
      states: [{ key: "canceled", word: "Canceled", states: ["canceled"] }] as const,
      spacecraft: "EARENDIL-312",
      station: "Fairbanks",
    };
    expect(filterLine({ passes: 212, handStarted: 0 }, false, names)).toBe(
      "212 passes · Canceled · EARENDIL-312 · Fairbanks",
    );
    expect(emptyText(span, NOW, names)).toBe(
      "No passes match: Canceled · EARENDIL-312 · Fairbanks · 11-09 – 11-15.",
    );
    const none = { states: [], spacecraft: null, station: null };
    expect(emptyText(span, NOW, none)).toBe("No passes between 11-09 and 11-15.");
    expect(emptyText(weekSpan("2026-11-16", NOW), NOW, none)).toBe(
      "No passes have started this week.",
    );
  });

  it("a cut day's callout and row", () => {
    const d = { day: "2026-11-12", through: Date.parse("2026-11-12T18:40:00Z") };
    expect(shortDayCallout(d)).toBe(
      "11-12 has more than 500 passes, and only the earliest 500 are shown, through 18:40Z. Pick a spacecraft to see the rest.",
    );
    expect(shortDayRow(d)).toBe("Passes on 11-12 after 18:40Z aren't shown.");
  });

  it("a hand-started contact reads its real state word", () => {
    const live = row({
      id: "rc-1",
      booked: false,
      starts_at: "2026-11-16T02:00:00Z",
      state: "active",
    });
    expect(stateView(live).word).toBe("In contact");
    const done = row({ id: "rc-2", booked: false, starts_at: "2026-11-16T02:00:00Z" });
    expect(stateView(done).word).toBe("Ended · not verified");
    const never = row({
      id: "rc-3",
      booked: false,
      starts_at: "2026-11-16T02:00:00Z",
      state: "defined",
    });
    expect(stateView(never)).toEqual({ word: "Not started", state: "off" });
  });
});
