import { describe, expect, it } from "vite-plus/test";
import { spacecraftRow } from "@/features/fleet/index.ts";
import type { Alarm } from "./api.ts";
import { conditionWords, crossedLimit } from "./api.ts";
import { alarmRows, byPoint } from "./list.ts";

const thresholds = { red_low: 24, yellow_low: 25, yellow_high: 33, red_high: 34 };
function alarm(id: string, sc: string | null, overrides: Partial<Alarm> = {}): Alarm {
  return {
    id,
    spacecraft_id: sc,
    point: { id: "EPS.VBAT", name: "VBAT", subsystem: "EPS" },
    severity: "critical",
    active: true,
    condition: "red_low",
    value: 23.1,
    limit_set_name: "DEFAULT",
    thresholds,
    first_crossed_at: "2026-11-08T02:35:00Z",
    generation_time: null,
    received_at: null,
    ...overrides,
  };
}

describe("alarm rows", () => {
  const fleet = [spacecraftRow(1), spacecraftRow(2)];

  it("sorts by severity, then oldest crossing first, and joins spacecraft names", () => {
    const rows = alarmRows(
      [
        alarm("caution", fleet[0]?.id ?? null, { severity: "caution", condition: "yellow_low" }),
        alarm("newer", fleet[0]?.id ?? null, { first_crossed_at: "2026-11-08T03:00:00Z" }),
        alarm("older", fleet[1]?.id ?? null),
      ],
      fleet,
      null,
    );
    expect(rows.map((r) => r.alarm.id)).toEqual(["older", "newer", "caution"]);
    expect(rows[0]?.sc?.name).toBe("EARENDIL-002");
    expect(rows[2]?.limit).toBe(25);
  });

  it("filters by point and keeps mission-scope alarms without a spacecraft", () => {
    const other = alarm("x", null, { point: { id: "GND.LINK", name: "LINK", subsystem: null } });
    const rows = alarmRows([alarm("a", null), other], fleet, "GND.LINK");
    expect(rows.map((r) => [r.alarm.id, r.sc])).toEqual([["x", null]]);
  });

  it("counts active alarms per point, most first", () => {
    const counts = byPoint([
      alarm("a", "1"),
      alarm("b", "2", { severity: "caution" }),
      alarm("c", "3", { point: { id: "P2", name: "P2", subsystem: null } }),
      alarm("d", "4", { active: false }),
    ]);
    expect(counts).toEqual([
      { pointId: "EPS.VBAT", name: "VBAT", count: 2, critical: 1 },
      { pointId: "P2", name: "P2", count: 1, critical: 1 },
    ]);
  });

  it("words conditions and finds the crossed band", () => {
    expect(conditionWords("red_high")).toBe("above red limit");
    expect(conditionWords("weird")).toBeNull();
    expect(crossedLimit(alarm("a", null, { condition: "red_high" }))).toBe(34);
    expect(crossedLimit(alarm("a", null, { thresholds: null }))).toBeNull();
    // No condition from the server: inferred from value vs bands, worst band first.
    expect(crossedLimit(alarm("a", null, { condition: null, value: 23.1 }))).toBe(24);
    expect(crossedLimit(alarm("a", null, { condition: null, value: 24.5 }))).toBe(25);
    expect(crossedLimit(alarm("a", null, { condition: null, value: 30 }))).toBeNull();
  });
});
