import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";

const member = (scid: number, extra: Record<string, unknown> = {}) => ({
  id: `spacecraft-earendil-${String(scid).padStart(3, "0")}`,
  name: `EARENDIL-${String(scid).padStart(3, "0")}`,
  scid,
  plane: 13,
  stale: false,
  last_received_at: null,
  violating_points: 1,
  value: 23.1,
  first_crossed_at: "2026-11-08T02:35:02Z",
  episode_id: null,
  status: null,
  assignee: null,
  acknowledged_by: null,
  ...extra,
});
const item = (overrides: Record<string, unknown>) => ({
  id: "x",
  priority: 1,
  kind: "alarm",
  state: "critical",
  source: null,
  acknowledged: null,
  since: null,
  due_at: null,
  count: 1,
  spacecraft: [],
  point: null,
  condition: null,
  plane: null,
  command: null,
  outcome: null,
  command_requests: [],
  finding: null,
  ...overrides,
});
const body = (items: unknown[]) => ({
  observed_at: "2026-11-08T02:41:17Z",
  stale_after_s: 900,
  failure_lookback_s: 86400,
  counts: { p1: 1, p2: 0, p3: 0, spacecraft_p1: 1 },
  items,
});
const present = (items: unknown[]) => {
  const result = decode(actionQueueReader, body(items));
  if (!result.ok) throw result.error;
  return presentQueue(result.value);
};
const vbat = {
  point: { id: "EPS.VBAT", name: "VBAT", subsystem: "EPS", unit: "V" },
  condition: "red_low",
};

describe("action queue (M6)", () => {
  it("expands small alarm groups into Engage rows and keeps big ones grouped", () => {
    const small = present([
      item({ id: "alarm:a", ...vbat, spacecraft: [member(312), member(47, { stale: true })] }),
    ]);
    expect(small.map((r) => [r.title, r.action.label, r.meta])).toEqual([
      ["EARENDIL-312 · VBAT below red limit", "Engage", null],
      ["EARENDIL-047 · VBAT below red limit", "Engage", "LAST KNOWN · TELEMETRY STALE"],
    ]);
    const owned = present([
      item({
        id: "alarm:c",
        ...vbat,
        acknowledged: 1,
        spacecraft: [
          member(9, {
            status: "acknowledged",
            acknowledged_by: { kind: "user", id: "u1", name: "Mira K." },
            assignee: { id: "u2", name: "Tomás R." },
          }),
        ],
      }),
    ]);
    expect(owned[0]?.meta).toBe("ACK MIRA K. · → TOMÁS R.");
    expect(owned[0]?.action.label).toBe("Open");
    expect(owned[0]?.acknowledged).toBe(true);
    expect(
      present([
        item({
          id: "alarm:d",
          ...vbat,
          acknowledged: 2,
          spacecraft: [member(1), member(2), member(3)],
        }),
      ])[0]?.meta,
    ).toBe("2 OF 3 ACKNOWLEDGED");
    const big = present([
      item({ id: "alarm:b", ...vbat, spacecraft: [member(1), member(2), member(3)] }),
    ]);
    expect(big).toHaveLength(1);
    expect(big[0]).toMatchObject({
      title: "3 spacecraft · VBAT below red limit",
      sentence: "EARENDIL-001, EARENDIL-002, EARENDIL-003",
    });
    expect(big[0]?.action.to).toEqual({ name: "ops.alarms", query: { point: "EPS.VBAT" } });
  });

  it("keeps server order and maps every kind", () => {
    const rows = present([
      item({
        id: "c",
        kind: "command_failed",
        command: { id: "c1", name: "SET_POWER_MODE" },
        outcome: "failed",
        spacecraft: [member(9)],
      }),
      item({
        id: "a",
        priority: 2,
        kind: "approval",
        state: "caution",
        command_requests: [
          {
            id: "r",
            command_name: "HEATER_SET",
            target: { id: "t", name: "EARENDIL-140" },
            requested_by: "Ana P.",
            status: "approval_pending",
          },
        ],
      }),
      item({
        id: "s",
        priority: 2,
        kind: "stale",
        state: "stale",
        plane: 3,
        spacecraft: [member(72)],
      }),
      item({ id: "l", priority: 3, kind: "limits_not_configured", state: "off" }),
    ]);
    expect(rows.map((r) => r.title)).toEqual([
      "SET_POWER_MODE failed · 1 spacecraft",
      "1 command request awaits your GO",
      "1 in plane 3 stale",
      "Ground limits not configured",
    ]);
    expect(rows[1]?.sentence).toBe("HEATER_SET · EARENDIL-140 · by Ana P.");
  });

  it("rejects an unknown kind or priority", () => {
    expect(decode(actionQueueReader, body([item({ kind: "mystery" })])).ok).toBe(false);
    expect(decode(actionQueueReader, body([item({ priority: 4 })])).ok).toBe(false);
  });
});
