import { describe, expect, it } from "vite-plus/test";
import { postureChips } from "./posture.ts";

const fleet = (
  critical: number,
  caution: number,
  stale: number,
  configured = true,
  unheard = 0,
) => ({
  counts: { critical, caution, stale, never_heard: unheard, total: 500 },
  limits: { configured },
});
const keys = (f: ReturnType<typeof fleet>) => postureChips(f).map((c) => c.key);

describe("fleet posture chips (ux IA §Top bar, ca31e877a)", () => {
  it("shows only non-zero states, worst first, with words in the accessible name", () => {
    expect(keys(fleet(2, 1, 3))).toEqual(["crit", "caution", "stale"]);
    expect(keys(fleet(0, 1, 0))).toEqual(["caution"]);
    expect(postureChips(fleet(2, 0, 0))[0]).toMatchObject({
      count: 2,
      word: "crit",
      label: "2 spacecraft critical",
      state: "crit",
    });
  });
  it("links crit and caution to Alarms, stale to Fleet ?state=stale, nominal to Now", () => {
    const [crit, caution, stale] = postureChips(fleet(1, 1, 1));
    expect(crit?.to).toEqual({ name: "ops.alarms" });
    expect(caution?.to).toEqual({ name: "ops.alarms" });
    expect(stale?.to).toEqual({ name: "ops.fleet", query: { state: "stale" } });
    expect(postureChips(fleet(0, 0, 0))).toEqual([
      expect.objectContaining({ key: "nominal", word: "Fleet nominal", to: { name: "ops.now" } }),
    ]);
  });
  it("is never nominal while anything is stale", () => {
    expect(keys(fleet(0, 0, 4))).toEqual(["stale"]);
  });
  it("never claims nominal while spacecraft are unheard; all unheard is 'No telemetry yet' (U20, U9)", () => {
    expect(keys(fleet(0, 0, 0, true, 6))).toEqual(["never-heard"]);
    expect(postureChips(fleet(0, 0, 0, true, 6))[0]).toMatchObject({
      state: "off",
      count: 6,
      word: "not heard yet",
      label: "6 spacecraft not heard yet",
      to: { name: "ops.fleet", query: { state: "never_heard" } },
    });
    expect(keys(fleet(1, 0, 2, true, 6))).toEqual(["crit", "stale", "never-heard"]);
    expect(postureChips(fleet(0, 0, 0, true, 500))[0]).toMatchObject({
      count: null,
      word: "No telemetry yet",
    });
  });
  it("shows nothing for an empty mission, and reads caution as 'in caution' (ux)", () => {
    expect(
      postureChips({ ...fleet(0, 0, 0), counts: { ...fleet(0, 0, 0).counts, total: 0 } }),
    ).toEqual([]);
    expect(postureChips(fleet(0, 2, 0))[0]?.label).toBe("2 spacecraft in caution");
  });
  it("says Ground limits off instead of crit and caution when limits aren't installed; stale still counts", () => {
    expect(keys(fleet(2, 1, 3, false))).toEqual(["limits-off", "stale"]);
    expect(keys(fleet(0, 0, 0, false))).toEqual(["limits-off"]);
    expect(postureChips(fleet(0, 0, 0, false))[0]).toMatchObject({
      state: "off",
      word: "Ground limits off",
      to: { name: "setup.apps" },
    });
  });
});

describe("telemetry degraded (ux fb5e5ded0)", () => {
  it("merges stale and never heard into one stale-marked chip; crit and caution unaffected", () => {
    const chips = postureChips({
      counts: { critical: 1, caution: 0, stale: 3, never_heard: 6, total: 500 },
      limits: { configured: true },
      telemetry: "degraded",
    });
    expect(chips.map((c) => c.key)).toEqual(["crit", "unheard-recently"]);
    expect(chips[1]).toMatchObject({
      state: "stale",
      count: 9,
      word: "not heard recently",
      to: { name: "ops.fleet", query: { state: "stale,never_heard" } },
    });
  });
});
