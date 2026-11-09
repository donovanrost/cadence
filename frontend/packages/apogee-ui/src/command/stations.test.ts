import { describe, expect, it } from "vite-plus/test";
import { stationItems } from "./stations.ts";

const STEPS = ["Compose", "Check", "Approve", "Release", "Radiate", "Acknowledge", "Verify"];

describe("stationItems", () => {
  it("Approve: two done, one current, one future, three folded", () => {
    const items = stationItems(STEPS, [2], { collapseFutureFrom: 4 });
    expect(items.map((i) => [i.text, i.state])).toEqual([
      ["01 Compose", "done"],
      ["02 Check", "done"],
      ["03 Approve", "current"],
      ["04 Release", "future"],
      ["05 · 06 · 07", "future"],
    ]);
  });

  it("Uplink: 01–04 folded as done, 05–07 all current", () => {
    const items = stationItems(STEPS, [4, 5, 6], { collapseDoneBefore: 4, collapseFutureFrom: 4 });
    expect(items.map((i) => [i.text, i.state])).toEqual([
      ["01–04", "done"],
      ["05 Radiate", "current"],
      ["06 Acknowledge", "current"],
      ["07 Verify", "current"],
    ]);
  });

  it("does not fold stations that are not all in the folded state", () => {
    const items = stationItems(STEPS, [5], { collapseFutureFrom: 4 });
    expect(items.some((i) => i.collapsed)).toBe(false);
  });
});
