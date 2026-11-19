import { describe, expect, it } from "vite-plus/test";
import { spacecraftId as spacecraftIdReader, decode } from "@/api/index.ts";
import { fleetOf, spacecraftRow } from "./fixtures.ts";
import { applyFleetPush, fleetPushReader, type FleetPush } from "./live.ts";

const snapshot = fleetOf([spacecraftRow(1), spacecraftRow(2), spacecraftRow(3)]);

function push(seq: number, overrides: Partial<FleetPush> = {}): FleetPush {
  return {
    ...snapshot,
    seq,
    full: seq === 1,
    heard: {},
    removed: [],
    spacecraft: seq === 1 ? snapshot.spacecraft : [],
    ...overrides,
  };
}

describe("fleet push", () => {
  it("decodes a delta with partial rows, heard and removed", () => {
    const body = { ...push(2), heard: { "spacecraft-earendil-001": "2026-11-08T02:41:20Z" } };
    expect(decode(fleetPushReader, body).ok).toBe(true);
    expect(decode(fleetPushReader, { ...body, heard: { x: "not a time" } }).ok).toBe(false);
  });

  it("takes a full snapshot, then applies material rows and heard times", () => {
    const first = applyFleetPush(null, 0, push(1));
    expect(first.ok && first.fleet.spacecraft).toHaveLength(3);
    if (!first.ok) return;
    const critical = spacecraftRow(2, { state: "critical", limit_state: "critical" });
    const counts = { ...snapshot.counts, nominal: 2, critical: 1 };
    const next = applyFleetPush(
      first.fleet,
      1,
      push(2, {
        counts,
        spacecraft: [critical],
        heard: { "spacecraft-earendil-003": "2026-11-08T03:00:00Z" },
      }),
    );
    expect(next.ok).toBe(true);
    if (!next.ok) return;
    expect(next.fleet.spacecraft.map((sc) => sc.state)).toEqual(["nominal", "critical", "nominal"]);
    expect(next.fleet.spacecraft[2]?.last_received_at).toBe("2026-11-08T03:00:00Z");
    expect(next.seq).toBe(2);
  });

  it("drops removed rows and keeps server order for new ones", () => {
    const counts = { ...snapshot.counts, total: 3, nominal: 3 };
    const result = applyFleetPush(
      snapshot,
      1,
      push(2, {
        counts,
        removed: [spacecraftIdReader("spacecraft-earendil-002")],
        spacecraft: [spacecraftRow(26)],
      }),
    );
    expect(result.ok && result.fleet.spacecraft.map((sc) => sc.scid)).toEqual([1, 3, 26]);
  });

  it("asks to resubscribe on a seq gap or inconsistent counts", () => {
    expect(applyFleetPush(snapshot, 1, push(3))).toEqual({ ok: false, reason: "gap" });
    expect(applyFleetPush(null, 0, push(2))).toEqual({ ok: false, reason: "gap" });
    const wrong = applyFleetPush(
      snapshot,
      1,
      push(2, { removed: [spacecraftIdReader("spacecraft-earendil-001")] }),
    );
    expect(wrong).toEqual({ ok: false, reason: "inconsistent" });
  });
});
