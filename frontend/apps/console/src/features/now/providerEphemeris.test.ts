import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import {
  ephemerisReasonWords,
  failedReasons,
  notReadyReasons,
} from "@/features/stations/ephemerisReasons.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";

/**
 * provider_ephemeris (#972; ops.md at 2304b988c). Synthetic fixtures: the queue item's shape as the
 * contract describes it, not captured from a server.
 */
const NOW = new Date("2026-11-27T12:00:00Z");
const member = (n: number) => ({
  id: `spacecraft-earendil-00${n}`,
  name: `EARENDIL-00${n}`,
  scid: n,
  plane: null,
  stale: false,
  last_received_at: null,
  violating_points: null,
  value: null,
  first_crossed_at: null,
  episode_id: null,
  status: null,
  assignee: null,
  acknowledged_by: null,
});
const item = (conflict: string, o: Record<string, unknown> = {}) => ({
  id: `attention:provider_ephemeris:prov_1:${conflict}`,
  priority: 2,
  kind: "attention",
  state: "caution",
  source: "provider_ephemeris",
  acknowledged: null,
  since: "2026-11-25T09:30:00Z",
  due_at: null,
  count: 1,
  spacecraft: [member(1), member(2)],
  point: null,
  condition: null,
  plane: null,
  command: null,
  outcome: null,
  command_requests: [],
  finding: null,
  attention: {
    id: `prov_1:${conflict}`,
    source: "provider_ephemeris",
    conflict,
    state: "open",
    acknowledged_by: null,
    contact_id: null,
    reservation_id: null,
    station: null,
    provider: { id: "prov_1", name: "Northlight" },
    starts_at: null,
    // ops.md names the item's since; raised_at differs here so the test shows which is read.
    raised_at: "2026-11-27T11:00:00Z",
    provider_message: null,
    resolution: null,
    uplink: null,
    release: null,
    spacecraft_count: 37,
    reason: null,
    next_retry_at: null,
    ...o,
  },
});
const rowOf = (conflict: string, o: Record<string, unknown> = {}) => {
  const r = decode(actionQueueReader, {
    observed_at: NOW.toISOString(),
    counts: { p1: 0, p2: 1, p3: 0, spacecraft_p1: 0 },
    items: [item(conflict, o)],
  });
  if (!r.ok) throw new Error(r.error.message);
  const row = presentQueue(r.value, NOW, "EARENDIL")[0];
  if (!row) throw new Error("no row");
  return row;
};

describe("provider_ephemeris on Now (#972)", () => {
  it("names the provider and the whole group's count, never a sampled spacecraft", () => {
    const row = rowOf("norad_id_missing");
    expect(row.title).toBe("Northlight · 37 spacecraft without a NORAD id");
    expect(row.title).not.toContain("EARENDIL");
    expect(row.sentence).toBe(
      "Their current element sets carry no NORAD id, so the provider can't look their orbits up.",
    );
    expect(row.state).toBe("caution");
    expect(row.meta).toBe("SINCE 11-25 09:30Z");
    expect(row.due).toBeUndefined();
    expect(row.acknowledged).toBeUndefined();
    expect(row.command).toBeUndefined();
    expect(row.action).toEqual({
      label: "Review",
      to: {
        name: "setup.stations.providers",
        params: { providerId: "prov_1" },
        query: { cause: "norad_id_missing" },
      },
    });
  });

  it("a failing upload: the reason in words, the next retry as a countdown, deep-linked", () => {
    const row = rowOf("failed:provider_timeout", {
      conflict: "failed",
      reason: "provider_timeout",
      next_retry_at: "2026-11-27T12:15:00Z",
    });
    expect(row.title).toBe("Northlight · 37 spacecraft whose orbit upload is failing");
    expect(row.sentence).toBe("The provider didn't answer in time.");
    expect(row.due).toEqual({ label: "Retry", at: "2026-11-27T12:15:00Z" });
    expect(row.action.to).toEqual({
      name: "setup.stations.providers",
      params: { providerId: "prov_1" },
      query: { cause: "failed", reason: "provider_timeout" },
    });
  });

  it("no ready route: re-checked, not retried", () => {
    const row = rowOf("not_ready:mission_provider_not_validated", {
      conflict: "not_ready",
      reason: "mission_provider_not_validated",
      next_retry_at: "2026-11-27T13:00:00Z",
      spacecraft_count: 1,
    });
    expect(row.title).toBe("Northlight · 1 spacecraft with no ready route");
    expect(row.sentence).toBe("The provider version hasn't validated.");
    expect(row.due).toEqual({ label: "Re-check", at: "2026-11-27T13:00:00Z" });
  });

  it("an unknown reason or cause reads as not recognized", () => {
    const reason = rowOf("failed:quota", { conflict: "failed", reason: "quota" });
    expect(reason.sentence).toBe("Reason not recognized (quota).");
    expect(reason.action.to).toMatchObject({ query: { cause: "failed", reason: "quota" } });
    // A not_ready code under failed isn't failed's: not recognized either.
    expect(ephemerisReasonWords("failed", "no_ready_route")).toBe(
      "Reason not recognized (no_ready_route).",
    );
    const cause = rowOf("stale_orbit", { conflict: "stale_orbit" });
    expect(cause.title).toBe("Northlight · 37 spacecraft whose orbits it can't use");
    expect(cause.sentence).toBe("Cause not recognized (stale_orbit).");
  });

  it("words every closed code", () => {
    for (const r of failedReasons)
      expect(ephemerisReasonWords("failed", r)).not.toMatch(/not recognized/);
    for (const r of notReadyReasons)
      expect(ephemerisReasonWords("not_ready", r)).not.toMatch(/not recognized/);
    // setup.md's closed lists, with #983's missing_downlink_path and #986's mission_provider_archived.
    expect([failedReasons.length, notReadyReasons.length]).toEqual([16, 25]);
    expect(ephemerisReasonWords("not_ready", "missing_downlink_path")).toBe(
      "The route has no downlink path set up.",
    );
    expect(ephemerisReasonWords("not_ready", "mission_provider_archived")).toBe(
      "The provider is archived.",
    );
  });
});
