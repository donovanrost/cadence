import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { effectScope, ref } from "vue";
import type { MissionId } from "@/api/index.ts";

const hints = vi.hoisted(() => new Map<string, () => void>());
const reads = vi.hoisted(() => ({ count: 0 }));
vi.mock("@/live/index.ts", async (original) => ({
  ...(await original<typeof import("@/live/index.ts")>()),
  // Live: offline, useFleet polls every 30 s instead, which isn't what this measures.
  useConnection: () => ref("live"),
  useMissionInvalidation: (_id: unknown, resources: readonly string[], run: () => void) => {
    for (const r of resources) hints.set(r, run);
  },
}));
vi.mock("./api.ts", async (original) => ({
  ...(await original<typeof import("./api.ts")>()),
  fetchFleet: () => {
    reads.count += 1;
    return Promise.resolve({
      ok: false,
      error: { kind: "unavailable", status: 0, message: "stub" },
    });
  },
}));
const { FLEET_TELEMETRY_GAP_MS, useFleet } = await import("./useFleet.ts");

afterEach(() => {
  vi.useRealTimers();
  hints.clear();
  reads.count = 0;
});

/** Telemetry hints every 500 ms for `ms`; how many reads did they cause after the first paint? */
async function telemetryReads(options: Parameters<typeof useFleet>[1], ms: number) {
  vi.useFakeTimers();
  const scope = effectScope();
  scope.run(() => useFleet(ref("m1" as MissionId), options));
  const first = reads.count;
  for (let t = 0; t < ms; t += 500) {
    hints.get("telemetry")?.();
    await vi.advanceTimersByTimeAsync(500);
  }
  scope.stop();
  return reads.count - first;
}

describe("useFleet freshness gap (lead 11-16: posture)", () => {
  it("lets a counts-only reader space telemetry refetches out to its own gap", async () => {
    // 55 s of hints every 500 ms: a read per 10 s by default (6), one for the posture (its next
    // would be at 60 s).
    const normal = await telemetryReads({ live: false }, 55_000);
    const posture = await telemetryReads({ live: false, freshnessGapMs: 60_000 }, 55_000);
    expect(FLEET_TELEMETRY_GAP_MS).toBe(10_000);
    expect(normal).toBeGreaterThanOrEqual(5);
    expect(posture).toBe(1);
  });
});
