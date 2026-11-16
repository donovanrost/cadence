import { describe, expect, it } from "vite-plus/test";
import { postureChips } from "./posture.ts";

const fleet = (critical: number, caution: number, stale: number, configured = true) => ({
  counts: { critical, caution, stale },
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
