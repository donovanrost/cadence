import { describe, expect, it } from "vite-plus/test";
import { changedFleet, isJson, median, scaleFleet, type Json } from "./scale-fleet.ts";

const STATES = ["critical", "caution", "stale", "nominal", "never_heard"] as const;

/** A seeded fleet of three, shaped like GET /fleet's data. */
function seeded(): Json {
  const row = (n: number, state: (typeof STATES)[number]) => ({
    id: `spacecraft-earendil-00${n}`,
    name: `Earendil ${n}`,
    scid: 100 + n,
    plane: 1,
    slot: n,
    state,
    stale: state === "stale",
    in_contact: false,
    last_received_at: "2026-11-26T00:00:00Z",
    limit_state: "nominal",
    violating_points: 0,
    worst_point: { point_id: "p", point_name: "P", value: 1, limit_state: "nominal" },
  });
  return {
    observed_at: "2026-11-26T00:00:00Z",
    counts: { total: 3, critical: 1, caution: 0, stale: 1, nominal: 1, never_heard: 0, fresh: 2 },
    spacecraft: [row(1, "critical"), row(2, "stale"), row(3, "nominal")],
  };
}

const rows = (data: Json) =>
  Array.isArray(data["spacecraft"]) ? data["spacecraft"].filter(isJson) : [];
const counts = (data: Json) => (isJson(data["counts"]) ? data["counts"] : {});

/** fleetReader's invariant: the state counts partition the rows. */
function partitions(data: Json): boolean {
  const c = counts(data);
  const sum = STATES.reduce((n, s) => n + (typeof c[s] === "number" ? c[s] : 0), 0);
  return c["total"] === rows(data).length && sum === c["total"];
}

describe("scaleFleet (#176)", () => {
  it("grows the seeded fleet to the size, seeded rows first and unchanged", () => {
    const data = seeded();
    const scaled = scaleFleet(data, 10);
    expect(rows(scaled)).toHaveLength(10);
    expect(rows(scaled).slice(0, 3)).toEqual(rows(data));
    expect(partitions(scaled)).toBe(true);
  });

  it("gives every clone its own id, SCID, name and plane slot", () => {
    const scaled = rows(scaleFleet(seeded(), 1_000));
    const unique = (key: string) => new Set(scaled.map((r) => r[key])).size;
    expect(unique("id")).toBe(1_000);
    expect(unique("scid")).toBe(1_000);
    expect(unique("name")).toBe(1_000);
    expect(new Set(scaled.map((r) => `${String(r["plane"])}/${String(r["slot"])}`)).size).toBe(
      1_000,
    );
  });

  it("keeps the seeded fleet when the size is at or below it", () => {
    expect(rows(scaleFleet(seeded(), 2))).toHaveLength(3);
  });
});

describe("changedFleet (#176)", () => {
  it("changes every row and still partitions the counts", () => {
    const data = scaleFleet(seeded(), 50);
    const changed = changedFleet(data, 1);
    const before = rows(data);
    expect(rows(changed).every((row, i) => JSON.stringify(row) !== JSON.stringify(before[i]))).toBe(
      true,
    );
    expect(partitions(changed)).toBe(true);
  });
});

describe("median", () => {
  it("takes the middle of an odd list and the mean of the middle two of an even one", () => {
    expect(median([300, 100, 200])).toBe(200);
    expect(median([4, 1, 3, 2])).toBe(2.5);
    expect(median([])).toBeNaN();
  });
});
