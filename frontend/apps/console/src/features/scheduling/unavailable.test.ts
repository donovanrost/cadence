import { describe, expect, it } from "vite-plus/test";
import type { Availability } from "./api.ts";
import { stationHits, unavailablePasses } from "./unavailable.ts";

const pass = (id: string, station: string, from: string, to: string) => ({
  snapshot_id: id,
  spacecraft_id: "sc1",
  station: { ref: station, id: station, code: null, name: null },
  starts_at: from,
  ends_at: to,
  synthetic: true,
  locked: false,
});
const window = (
  kind: "outage" | "maintenance" | "degraded",
  from: string,
  to: string | null,
  cleared: string | null = null,
) => ({
  id: `w-${kind}`,
  ground_station_id: "gs-sva",
  kind,
  from,
  to,
  eta: null,
  source: "operator",
  reported_at: null,
  reason: null,
  cleared_at: cleared,
});
const availability = (windows: ReturnType<typeof window>[]) => ({
  status: "ready" as const,
  receivedAt: new Date(0),
  value: {
    at: "2026-11-10T00:00:00Z",
    stations: [
      {
        ground_station_id: "gs-sva",
        state: "up" as const,
        since: null,
        eta: null,
        basis: null,
        windows,
      },
    ],
  } satisfies Availability,
});

describe("unavailablePasses (ux K1 #10)", () => {
  const plan = {
    passes: [
      pass("in", "gs-sva", "2026-11-11T06:30:00Z", "2026-11-11T06:38:00Z"),
      pass("after", "gs-sva", "2026-11-11T09:00:00Z", "2026-11-11T09:08:00Z"),
      pass("elsewhere", "gs-fai", "2026-11-11T06:30:00Z", "2026-11-11T06:38:00Z"),
    ],
  };

  it("flags passes inside an outage or maintenance window on their station only", () => {
    const hits = unavailablePasses(
      plan,
      availability([window("outage", "2026-11-11T04:00:00Z", "2026-11-11T08:00:00Z")]),
    );
    expect(hits.map((h) => h.snapshotId)).toEqual(["in"]);
  });

  it("ignores degraded and cleared windows; an open-ended outage covers everything after it", () => {
    expect(
      unavailablePasses(
        plan,
        availability([window("degraded", "2026-11-11T04:00:00Z", "2026-11-11T08:00:00Z")]),
      ),
    ).toEqual([]);
    expect(
      unavailablePasses(
        plan,
        availability([
          window("outage", "2026-11-11T04:00:00Z", "2026-11-11T08:00:00Z", "2026-11-11T05:00:00Z"),
        ]),
      ),
    ).toEqual([]);
    expect(
      unavailablePasses(plan, availability([window("outage", "2026-11-11T08:30:00Z", null)])).map(
        (h) => h.snapshotId,
      ),
    ).toEqual(["after"]);
  });
});

describe("stationHits (ux U26)", () => {
  it("puts degraded windows in atRisk, never blocking", () => {
    const plan = { passes: [pass("in", "gs-sva", "2026-11-11T06:30:00Z", "2026-11-11T06:38:00Z")] };
    const r = stationHits(
      plan,
      availability([window("degraded", "2026-11-11T04:00:00Z", "2026-11-11T08:00:00Z")]),
    );
    expect(r.blocking).toEqual([]);
    expect(r.atRisk.map((h) => h.snapshotId)).toEqual(["in"]);
  });
});
