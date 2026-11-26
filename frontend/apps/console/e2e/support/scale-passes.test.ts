import { describe, expect, it } from "vite-plus/test";
import {
  clonesBySource,
  countsOf,
  PASSES_PER_DAY,
  passPage,
  scalePasses,
  schedulePasses,
} from "./scale-passes.ts";

const fleet = [
  { id: "sc-1", name: "EARENDIL-001", scid: 1 },
  { id: "sc-2", name: "EARENDIL-002", scid: 2 },
  { id: "sc-1-scale-0001", name: "Scale 0001", scid: 501 },
  { id: "sc-1-scale-0003", name: "Scale 0003", scid: 503 },
];
const pass = (id: string, craft: string | null) => ({
  id,
  spacecraft_id: craft,
  spacecraft: craft === null ? null : { id: craft, name: "x", scid: 0 },
  starts_at: "2026-11-26T00:00:00Z",
});

/** #909: the passes scale with the fleet's clones and come back in the server's pages. */
describe("scale-passes", () => {
  it("finds each clone's seeded craft", () => {
    expect([...clonesBySource(fleet).entries()].map(([k, v]) => [k, v.length])).toEqual([
      ["sc-1", 2],
    ]);
  });

  it("gives every clone its seeded craft's passes, under its own identity and a unique id", () => {
    const grown = scalePasses([pass("p1", "sc-1"), pass("p2", "sc-2"), pass("p3", null)], fleet);
    expect(grown.map((p) => p["id"])).toEqual(["p1", "p2", "p3", "p1-scale-0001", "p1-scale-0003"]);
    expect(grown[3]).toMatchObject({
      spacecraft_id: "sc-1-scale-0001",
      spacecraft: { id: "sc-1-scale-0001", name: "Scale 0001", scid: 501 },
    });
  });

  it("books every craft about PASSES_PER_DAY passes a day, with states by time and unique ids", () => {
    const day = Date.parse("2026-11-26T00:00:00Z");
    const now = day + 12 * 3_600_000;
    const passes = schedulePasses(fleet, day, day + 24 * 3_600_000, now);
    for (const craft of fleet) {
      const own = passes.filter((p) => p["spacecraft_id"] === craft.id);
      expect(Math.abs(own.length - PASSES_PER_DAY)).toBeLessThanOrEqual(1);
    }
    expect(new Set(passes.map((p) => p["id"])).size).toBe(passes.length);
    const at = (p: Record<string, unknown>) => Date.parse(String(p["starts_at"]));
    expect(passes.every((p) => at(p) >= day && at(p) < day + 24 * 3_600_000)).toBe(true);
    expect(passes.filter((p) => at(p) > now).every((p) => p["state"] === "confirmed")).toBe(true);
    expect(
      passes.filter((p) => at(p) + 9 * 60_000 <= now).every((p) => p["state"] === "completed"),
    ).toBe(true);
  });

  it("counts the window as the server does", () => {
    const now = Date.parse("2026-11-26T12:00:00Z");
    const row = (craft: string, state: string, starts: string, ends: string, booked = true) => ({
      spacecraft_id: craft,
      state,
      booked,
      starts_at: starts,
      ends_at: ends,
      source: { synthetic: false },
    });
    expect(
      countsOf(
        [
          row("a", "active", "2026-11-26T11:55:00Z", "2026-11-26T12:04:00Z"),
          row("a", "confirmed", "2026-11-26T13:00:00Z", "2026-11-26T13:09:00Z"),
          row("b", "completed", "2026-11-26T10:00:00Z", "2026-11-26T10:09:00Z", false),
        ],
        now,
      ),
    ).toEqual({ total: 3, booked: 2, hand_started: 1, in_contact: 1, upcoming: 1, synthetic: 0 });
  });

  it("serves pages of at most 500 with an offset cursor, and none after the last", () => {
    const passes = Array.from({ length: 1_200 }, (_, i) => pass(`p${i}`, "sc-1"));
    const window = { from: "a", to: "b", counts: { total: 1_200 }, passes };
    const first = passPage(window, null);
    expect(first).toMatchObject({ meta: { next_cursor: "scale:500" } });
    const last = passPage(window, "scale:1000");
    expect(last).toMatchObject({ meta: { next_cursor: null } });
    const data = last["data"] as { passes: unknown[] };
    expect(data.passes).toHaveLength(200);
    expect(passPage(window, null, 9_999)["meta"]).toEqual({ next_cursor: "scale:500" });
  });
});
