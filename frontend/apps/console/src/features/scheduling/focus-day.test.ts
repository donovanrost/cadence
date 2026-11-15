import { describe, expect, it } from "vite-plus/test";
import { focusDay, gapEffect, gapSentence, gapText } from "./focus-day.ts";
import { station } from "./fixtures.ts";

const day = { from: Date.parse("2026-11-13T00:00:00Z"), to: Date.parse("2026-11-14T00:00:00Z") };
const svb = station({ ref: "svb", id: "gs_svb", code: "SVB", name: "Svalbard" });
const pass = (id: string, sc: string, from: string, to: string) => ({
  snapshot_id: id,
  spacecraft_id: sc,
  station: svb,
  starts_at: `2026-11-13T${from}:00Z`,
  ends_at: `2026-11-13T${to}:00Z`,
  synthetic: false,
  locked: false,
  expires_at: null,
  booking: null,
});
const plan = {
  passes: [
    pass("p3", "sc1", "18:00", "18:10"),
    pass("p1", "sc1", "00:30", "00:40"),
    pass("x", "sc2", "03:00", "03:10"),
    pass("p2", "sc1", "06:40", "06:50"),
  ],
  demand: {
    rule_met: 0,
    rule_total: 1,
    spacecraft: [
      {
        spacecraft_id: "sc1",
        rule_met: false,
        contacts: { have: 3, need: 4 },
        reasons: [],
        longest_gap: null,
        uplink_passes: null,
      },
    ],
    rules: [],
  },
};

describe("K1 C · focused spacecraft day", () => {
  it("places only its passes in time order and measures the gaps between them", () => {
    const f = focusDay(plan, "sc1", day);
    expect(f.passes.map((p) => p.id)).toEqual(["p1", "p2", "p3"]);
    expect(f.passes[0]?.text).toBe("SVB 00:30–00:40Z");
    // The day's edges count (domain c38bb5de): 00:00Z → first AOS and last LOS → 24:00Z.
    expect(f.gaps.map((g) => [g.text, g.longest])).toEqual([
      ["30m", false],
      ["6h00", false],
      ["11h10", true],
      ["5h50", false],
    ]);
    expect(f.longestGapSeconds).toBe(11 * 3600 + 600);
    expect(f.ruleMet).toBe(false);
    expect(f.contacts).toEqual({ have: 3, need: 4 });
    expect(f.passes[0]?.from).toBeCloseTo(30 / 1440);
  });

  it("says nothing it doesn't know: no demand row, no passes, no gaps", () => {
    const f = focusDay(plan, "sc9", day);
    expect(f).toEqual({
      ruleMet: null,
      contacts: null,
      uplink: null,
      gapLimitSeconds: null,
      passes: [],
      gaps: [],
      longestGapSeconds: null,
    });
  });

  it("takes the server's longest gap, limit and uplink passes when it sends them", () => {
    const served = {
      ...plan,
      demand: {
        ...plan.demand,
        spacecraft: [
          {
            spacecraft_id: "sc1",
            rule_met: false,
            contacts: { have: 3, need: 4 },
            reasons: [],
            longest_gap: {
              seconds: 21_000,
              limit_seconds: 36_000,
              from: "2026-11-13T18:10:00Z",
              to: "2026-11-14T00:00:00Z",
            },
            uplink_passes: { have: 1, need: null },
          },
        ],
      },
    };
    const f = focusDay(served, "sc1", day);
    expect(f.longestGapSeconds).toBe(21_000);
    expect(f.gapLimitSeconds).toBe(36_000);
    expect(f.gaps.filter((g) => g.longest).map((g) => g.text)).toEqual(["5h50"]);
    expect(f.uplink).toEqual({ have: 1, need: null });
  });

  it("says how a window shortens the longest gap, and nothing when it doesn't or isn't known", () => {
    expect(gapEffect(22_200, 11_100)).toBe("Longest gap 6h10 → 3h05");
    expect(gapEffect(11_100, 11_100)).toBeNull();
    expect(gapEffect(undefined, 3_600)).toBeNull();
    expect(gapEffect(3_600, null)).toBeNull();
  });

  it("says a gap over the limit as ux's sentence, with a date prefix off the plan's day (#74)", () => {
    const gap = (from: string, to: string) => ({
      seconds: 40_800,
      limit_seconds: 36_000,
      from,
      to,
    });
    expect(gapSentence(gap("2026-11-13T03:10:00Z", "2026-11-13T14:30:00Z"), "2026-11-13")).toBe(
      "No contact for 11h20, 03:10Z–14:30Z. The rule allows 10h00.",
    );
    expect(gapSentence(gap("2026-11-13T18:00:00Z", "2026-11-14T05:20:00Z"), "2026-11-13")).toBe(
      "No contact for 11h20, 18:00Z–11-14 05:20Z. The rule allows 10h00.",
    );
    expect(gapSentence({ ...gap("a", "b"), limit_seconds: null }, "2026-11-13")).toBeNull();
  });

  it("marks the longest gap over the limit, and only then", () => {
    const over = focusDay(
      {
        ...plan,
        demand: {
          ...plan.demand,
          spacecraft: [
            {
              spacecraft_id: "sc1",
              rule_met: false,
              contacts: { have: 3, need: 4 },
              reasons: [],
              longest_gap: {
                seconds: 40_200,
                limit_seconds: 36_000,
                from: "2026-11-13T06:50:00Z",
                to: "2026-11-13T18:00:00Z",
              },
              uplink_passes: null,
            },
          ],
        },
      },
      "sc1",
      day,
    );
    expect(over.gaps.filter((g) => g.over).map((g) => g.text)).toEqual(["11h10"]);
    expect(focusDay(plan, "sc1", day).gaps.some((g) => g.over)).toBe(false);
  });

  it("writes short gaps in minutes", () => {
    expect(gapText(45 * 60)).toBe("45m");
    expect(gapText(10 * 3600 + 5 * 60)).toBe("10h05");
  });
});
