import { describe, expect, it } from "vite-plus/test";
import { spacecraftRow } from "@/features/fleet/index.ts";
import { bandFor, conditionWords } from "./api.ts";
import type { Episode } from "./episodes.ts";
import {
  alarmRows,
  byPoint,
  groupAlarmRows,
  lastClearedLine,
  ownerText,
  tabCounts,
} from "./list.ts";

const now = new Date("2026-11-09T02:00:00Z");
function ep(id: string, overrides: Partial<Episode> = {}): Episode {
  return {
    id,
    source: "ground_limit",
    status: "new",
    cleared_unacknowledged: false,
    severity: "critical",
    peak_severity: "critical",
    source_state: "red_low",
    spacecraft_id: "spacecraft-earendil-001",
    spacecraft: { id: "spacecraft-earendil-001", name: "EARENDIL-001", scid: 1 },
    point: { id: "EPS.VBAT", name: "VBAT", unit: "V" },
    thresholds: { red_low: 24, yellow_low: 25, yellow_high: 33, red_high: 34 },
    opened_at: "2026-11-09T01:00:00Z",
    cleared_at: null,
    first_value: 23.4,
    last_value: 23.1,
    last_observed_at: null,
    last_evaluated_at: null,
    acknowledged_at: null,
    acknowledged_by: null,
    assignee: null,
    assigned_at: null,
    ...overrides,
  };
}

describe("alarm list on episodes", () => {
  const fleet = [spacecraftRow(1), spacecraftRow(2)];
  const acked = ep("b", {
    status: "acknowledged",
    acknowledged_by: { kind: "user", id: "u", name: "Mira K." },
  });
  const clearedRecent = ep("c", { status: "cleared", cleared_at: "2026-11-09T01:30:00Z" });
  const clearedOld = ep("d", { status: "cleared", cleared_at: "2026-11-07T01:00:00Z" });

  it("splits tabs: New, Acknowledged, Cleared within 24 h", () => {
    const all = [ep("a"), acked, clearedRecent, clearedOld];
    expect(alarmRows(all, fleet, "new", null, now).map((r) => r.key)).toEqual(["a"]);
    expect(alarmRows(all, fleet, "acknowledged", null, now).map((r) => r.key)).toEqual(["b"]);
    expect(alarmRows(all, fleet, "cleared", null, now).map((r) => r.key)).toEqual(["c"]);
    expect(tabCounts([ep("a"), acked], [clearedRecent, clearedOld], now)).toEqual({
      new: 1,
      acknowledged: 1,
      cleared: 1,
    });
    expect(tabCounts([ep("a")], null, now).cleared).toBeNull();
  });

  it("joins fleet identity, finds the limit and words the owner", () => {
    const [row] = alarmRows(
      [ep("a", { assignee: { id: "t", name: "Tomás R." } })],
      fleet,
      "new",
      null,
      now,
    );
    expect(row?.sc?.name).toBe("EARENDIL-001");
    expect(row?.limit).toBe(24);
    expect(row?.owner).toBe("→ Tomás R.");
    expect(ownerText(acked)).toBe("Ack Mira K.");
    expect(ownerText(ep("x"))).toBe("Unassigned");
    expect(ownerText(ep("y", { status: "cleared", cleared_unacknowledged: true }))).toBe(
      "Cleared unacknowledged",
    );
  });

  it("filters by point and counts active episodes per point", () => {
    const other = ep("o", { point: { id: "P2", name: "P2", unit: null } });
    expect(alarmRows([ep("a"), other], fleet, "new", "P2", now).map((r) => r.key)).toEqual(["o"]);
    expect(byPoint([ep("a"), ep("b", { severity: "caution" }), other, clearedRecent])).toEqual([
      { pointId: "EPS.VBAT", name: "VBAT", count: 2, critical: 1 },
      { pointId: "P2", name: "P2", count: 1, critical: 1 },
    ]);
  });

  it("words conditions and finds bands", () => {
    expect(conditionWords("red_high")).toBe("above red limit");
    expect(conditionWords("weird")).toBeNull();
    expect(
      bandFor({ red_low: 24, yellow_low: 25, yellow_high: 33, red_high: 34 }, "red_high"),
    ).toBe(34);
    expect(bandFor(null, "red_low")).toBeNull();
  });
});

describe("alarm grouping and the empty state (OpsLists §Alarms)", () => {
  const at = (n: number) => ({
    spacecraft_id: `spacecraft-earendil-00${n}`,
    spacecraft: { id: `spacecraft-earendil-00${n}`, name: `EARENDIL-00${n}`, scid: n },
  });
  const fleet = [1, 2, 3, 4].map((n) => spacecraftRow(n, { plane: 7 }));
  const eps = [
    ep("a", at(1)),
    ep("x", { ...at(4), point: { id: "P2", name: "TEMP", unit: "°C" } }),
    ep("b", at(2)),
    ep("c", at(3)),
  ];

  it("folds 3+ identical point + condition into one header; expanding lists them", () => {
    const rows = alarmRows(eps, fleet, "new", null, now);
    const closed = groupAlarmRows(rows, new Set());
    expect(closed.map((r) => [r.key, r.group?.where ?? null])).toEqual([
      ["group:EPS.VBAT|red_low", "3 spacecraft in plane 07"],
      ["x", null],
    ]);
    expect(closed[0]?.group?.unassigned).toBe(3);
    // ux: the members' range when they share a unit; the earliest opening; the soonest contact.
    expect(closed[0]?.group?.range).toBe("23.1 V");
    const spread = groupAlarmRows(
      alarmRows(
        [
          ep("a", { ...at(1), last_value: 23.6 }),
          ep("b", { ...at(2), opened_at: "2026-11-09T00:10:00Z" }),
          ep("c", at(3)),
        ],
        [
          spacecraftRow(1, { plane: 7 }),
          spacecraftRow(2, { plane: 7, next_aos_at: "2026-11-09T03:00:00Z" }),
          spacecraftRow(3, { plane: 7, next_aos_at: "2026-11-09T02:30:00Z" }),
        ],
        "new",
        null,
        now,
      ),
      new Set(),
    )[0]?.group;
    expect([spread?.range, spread?.openedAt, spread?.soonest?.scid]).toEqual([
      "23.1–23.6 V",
      "2026-11-09T00:10:00Z",
      3,
    ]);
    const open = groupAlarmRows(rows, new Set(["group:EPS.VBAT|red_low"]));
    expect(open.map((r) => [r.key, r.member ?? false])).toEqual([
      ["group:EPS.VBAT|red_low", false],
      ["a", true],
      ["b", true],
      ["c", true],
      ["x", false],
    ]);
  });

  it("names the last clear", () => {
    const cleared = [
      ep("c1", { ...at(2), status: "cleared", cleared_at: "2026-11-09T01:12:00Z" }),
      ep("c2", { ...at(3), status: "cleared", cleared_at: "2026-11-08T23:00:00Z" }),
    ];
    expect(lastClearedLine(cleared, now)).toBe("Last cleared 01:12Z on EARENDIL-002.");
    expect(lastClearedLine([], now)).toBeNull();
  });
});
