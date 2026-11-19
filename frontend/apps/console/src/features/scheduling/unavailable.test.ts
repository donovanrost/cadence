import { describe, expect, it } from "vite-plus/test";
import { stationId as stationIdReader } from "@/api/index.ts";
import type { Availability, PlanIssue } from "./api.ts";
import { stationHits } from "./unavailable.ts";

const issue = (code: PlanIssue["code"], ids: string[], kind?: PlanIssue["kind"]): PlanIssue => ({
  code,
  snapshot_ids: ids,
  spacecraft_id: undefined,
  ground_station_id: stationIdReader("gs-sva"),
  window_id: "w1",
  kind,
});
const availability = {
  status: "ready" as const,
  receivedAt: new Date(0),
  value: {
    at: "2026-11-10T00:00:00Z",
    stations: [
      {
        ground_station_id: stationIdReader("gs-sva"),
        state: "up" as const,
        since: null,
        eta: null,
        basis: null,
        windows: [
          {
            id: "w1",
            ground_station_id: stationIdReader("gs-sva"),
            kind: "outage" as const,
            from: "2026-11-11T04:00:00Z",
            to: "2026-11-11T08:00:00Z",
            eta: null,
            source: "operator",
            reported_at: "2026-11-10T10:32:00Z",
            reason: null,
            cleared_at: null,
          },
        ],
      },
    ],
  } satisfies Availability,
};

describe("stationHits (server U26)", () => {
  it("takes blocking passes from station_unavailable conflicts only, at-risk from at_risk", () => {
    const hits = stationHits(
      {
        conflicts: [
          issue("selected_contacts_overlap", ["a", "b"]),
          issue("station_unavailable", ["c"], "outage"),
        ],
        at_risk: [issue("station_degraded", ["d"], "degraded")],
      },
      availability,
    );
    expect(hits.blocking.map((h) => [h.snapshotId, h.kind, h.window?.from])).toEqual([
      ["c", "outage", "2026-11-11T04:00:00Z"],
    ]);
    expect(hits.atRisk.map((h) => h.snapshotId)).toEqual(["d"]);
  });

  it("still reports the conflict when the window isn't in the availability read", () => {
    const hits = stationHits(
      { conflicts: [issue("station_unavailable", ["c"], "maintenance")], at_risk: [] },
      null,
    );
    expect(hits.blocking).toEqual([
      { snapshotId: "c", windowId: "w1", kind: "maintenance", window: null },
    ]);
  });
});
