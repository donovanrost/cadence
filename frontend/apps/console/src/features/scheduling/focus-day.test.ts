import { describe, expect, it } from "vite-plus/test";
import { focusDay, gapText } from "./focus-day.ts";

const day = { from: Date.parse("2026-11-13T00:00:00Z"), to: Date.parse("2026-11-14T00:00:00Z") };
const station = { ref: "svb", id: "gs_svb", code: "SVB", name: "Svalbard" };
const pass = (id: string, sc: string, from: string, to: string) => ({
  snapshot_id: id,
  spacecraft_id: sc,
  station,
  starts_at: `2026-11-13T${from}:00Z`,
  ends_at: `2026-11-13T${to}:00Z`,
  synthetic: false,
  locked: false,
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
      { spacecraft_id: "sc1", rule_met: false, contacts: { have: 3, need: 4 }, reasons: [] },
    ],
    rules: [],
  },
};

describe("K1 C · focused spacecraft day", () => {
  it("places only its passes in time order and measures the gaps between them", () => {
    const f = focusDay(plan, "sc1", day);
    expect(f.passes.map((p) => p.id)).toEqual(["p1", "p2", "p3"]);
    expect(f.passes[0]?.text).toBe("SVB 00:30–00:40Z");
    expect(f.gaps.map((g) => [g.text, g.longest])).toEqual([
      ["6h00", false],
      ["11h10", true],
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
      passes: [],
      gaps: [],
      longestGapSeconds: null,
    });
  });

  it("writes short gaps in minutes", () => {
    expect(gapText(45 * 60)).toBe("45m");
    expect(gapText(10 * 3600 + 5 * 60)).toBe("10h05");
  });
});
