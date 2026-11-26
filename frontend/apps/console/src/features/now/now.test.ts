import { describe, expect, it } from "vite-plus/test";
import { stationId as stationIdReader, pointId as pointIdReader } from "@/api/index.ts";
import { fleetOf, spacecraftRow, statTiles, type RawLimitState } from "@/features/fleet/index.ts";
import { constellation } from "./constellation.ts";
import { deriveQueue, GROUP_AT, nowHeadline } from "./queue.ts";
import { freshKeys } from "./useFreshFlash.ts";
import { worstStationIssue } from "./stationMeta.ts";

const vbat = (raw: RawLimitState) =>
  ({
    point_id: pointIdReader("HK.battery_voltage"),
    point_name: "VBAT",
    value: 23.1,
    limit_state: "critical",
    raw_limit_state: raw,
    received_at: "2026-11-08T02:41:15Z",
  }) as const;

describe("deriveQueue", () => {
  it("ranks critical first, then a GO waiting on you, then stale, then setup gaps", () => {
    const fleet = fleetOf(
      [
        spacecraftRow(1, { state: "stale", stale: true }),
        spacecraftRow(2, {
          state: "critical",
          limit_state: "critical",
          worst_point: vbat("red_low"),
        }),
        spacecraftRow(3, { state: "never_heard", last_received_at: null }),
      ],
      {
        commands: { queued: 1, in_flight: 0, failed: 0, approval_pending: 1, awaiting_viewer: 1 },
        limits: { configured: false },
      },
    );
    const queue = deriveQueue(fleet);
    expect(queue.map((item) => item.key)).toEqual([
      "critical-spacecraft-earendil-002",
      "approvals",
      "stale-1",
      "limits-not-configured",
      "never-heard",
    ]);
    expect(queue[0]?.title).toBe("EARENDIL-002 · VBAT below red limit");
    expect(queue[0]?.action.label).toBe("Engage");
  });

  it("groups identical causes at the threshold", () => {
    const rows = Array.from({ length: GROUP_AT }, (_, i) =>
      spacecraftRow(i + 1, { state: "critical", worst_point: vbat("red_low") }),
    );
    const queue = deriveQueue(fleetOf(rows));
    expect(queue).toHaveLength(1);
    expect(queue[0]?.title).toBe(`${GROUP_AT} spacecraft · VBAT below red limit`);
    expect(queue[0]?.spacecraftIds).toHaveLength(GROUP_AT);
  });

  it("is empty for a fresh, nominal fleet", () => {
    expect(deriveQueue(fleetOf([spacecraftRow(1), spacecraftRow(2)]))).toEqual([]);
  });
});

describe("nowHeadline", () => {
  const headline = (rows: Parameters<typeof fleetOf>[0]) => {
    const fleet = fleetOf(rows);
    return nowHeadline(fleet, deriveQueue(fleet));
  };

  it("counts distinct spacecraft with a P1 item", () => {
    expect(
      headline([
        spacecraftRow(1, { state: "critical", worst_point: vbat("red_low") }),
        spacecraftRow(2),
      ]),
    ).toBe("1 spacecraft needs you");
  });

  it("never calls a fleet with stale members nominal", () => {
    expect(headline([spacecraftRow(1), spacecraftRow(2, { state: "stale", stale: true })])).toBe(
      "1 spacecraft to watch",
    );
  });

  it("says when nothing has been heard yet", () => {
    expect(headline([spacecraftRow(1, { state: "never_heard", last_received_at: null })])).toBe(
      "No telemetry yet",
    );
  });

  it("says all nominal only when every spacecraft is fresh and nominal", () => {
    expect(headline([spacecraftRow(1), spacecraftRow(2)])).toBe("All 2 nominal");
  });
});

describe("constellation", () => {
  it("is unavailable without plane and phase", () => {
    expect(constellation([spacecraftRow(1, { plane: null })])).toBeNull();
  });

  it("draws one orbit per plane and hides dots behind the Earth", () => {
    const rows = Array.from({ length: 50 }, (_, i) => spacecraftRow(i + 1));
    const drawing = constellation(rows);
    expect(drawing?.orbits).toHaveLength(2);
    expect(drawing?.dots.length).toBeGreaterThan(0);
    expect(drawing?.dots.length).toBeLessThanOrEqual(50);
  });
});

describe("statTiles (U13)", () => {
  const tile = (fleet: Parameters<typeof statTiles>[0], label: string) =>
    statTiles(fleet).find((t) => t.label === label);

  it("links each tile to the list behind its number (Now)", () => {
    const fleet = fleetOf([spacecraftRow(1)]);
    expect(statTiles(fleet).map((t) => [t.label, t.to])).toEqual([
      ["Nominal", { name: "ops.fleet", query: { state: "nominal" } }],
      ["Caution", { name: "ops.alarms", query: { severity: "caution" } }],
      ["Critical", { name: "ops.alarms", query: { severity: "critical" } }],
      ["Stale", { name: "ops.fleet", query: { state: "stale" } }],
      ["In contact", { name: "ops.contacts" }],
      ["Uplinks queued", { name: "ops.commands" }],
    ]);
  });

  it("shows unknown, not 0, when nothing is fresh", () => {
    const fleet = fleetOf([spacecraftRow(1, { state: "never_heard", last_received_at: null })]);
    expect(tile(fleet, "Critical")).toMatchObject({ value: null, caption: "no telemetry yet" });
    expect(tile(fleet, "Stale")).toMatchObject({ value: null, caption: "no telemetry yet" });
  });

  it("says 'no fresh telemetry' when spacecraft were heard but none is fresh", () => {
    const fleet = fleetOf([spacecraftRow(1, { state: "stale", stale: true })]);
    expect(tile(fleet, "Caution")).toMatchObject({ value: null, caption: "no fresh telemetry" });
    expect(tile(fleet, "Stale")).toMatchObject({ value: 1 });
  });

  it("lets 'limits not configured' win over missing telemetry", () => {
    const fleet = fleetOf([spacecraftRow(1, { state: "never_heard", last_received_at: null })], {
      limits: { configured: false },
    });
    expect(tile(fleet, "Critical")).toMatchObject({
      value: null,
      caption: "limits not configured",
    });
    expect(tile(fleet, "Stale")).toMatchObject({ value: null, caption: "no telemetry yet" });
  });

  it("shows unknown limit counts when ground limits aren't configured", () => {
    const fleet = fleetOf([spacecraftRow(1)], { limits: { configured: false } });
    expect(tile(fleet, "Caution")).toMatchObject({ value: null, caption: "limits not configured" });
    expect(tile(fleet, "Stale")?.value).toBe(0);
  });

  it("still counts criticals that exist without ground limits", () => {
    const fleet = fleetOf([spacecraftRow(1, { state: "critical", worst_point: vbat("red_low") })], {
      limits: { configured: false },
    });
    expect(tile(fleet, "Critical")).toMatchObject({ value: 1, state: "crit" });
  });

  it("never invents contact counts", () => {
    expect(tile(fleetOf([spacecraftRow(1)]), "In contact")).toMatchObject({
      value: null,
      caption: "not tracked yet",
    });
  });
});

describe("fresh crit flash (design-language §6)", () => {
  const row = (key: string, priority: 1 | 2 | 3, state: "crit" | "caution") => ({
    key,
    priority,
    state,
    title: key,
    titleTo: null,
    sentence: "",
    meta: null,
    action: { label: "Open", to: "/" },
    spacecraftIds: [],
  });
  it("flashes only crit P1 rows that weren't there on the last read", () => {
    const items = [
      row("a", 1, "crit"),
      row("b", 1, "crit"),
      row("c", 2, "caution"),
      row("d", 1, "caution"),
    ];
    expect(freshKeys(null, items)).toEqual([]);
    expect(freshKeys(new Set(["a"]), items)).toEqual(["b"]);
  });
});

describe("Now header: worst station issue (L49)", () => {
  const st = (id: string, state: "up" | "degraded" | "down", since: string | null) => ({
    ground_station_id: stationIdReader(id),
    state,
    since,
    eta: null,
    basis: null,
    windows: [],
  });
  const code = (id: string) => id.toUpperCase();
  const now = new Date("2026-11-13T02:00:00Z");
  it("names down before degraded, then the longest-running, with the count of others", () => {
    const a = {
      at: "2026-11-13T02:00:00Z",
      stations: [
        st("kir", "degraded", "2026-11-12T20:00:00Z"),
        st("sva", "down", "2026-11-13T01:10:00Z"),
        st("fbk", "up", null),
      ],
    };
    expect(worstStationIssue(a, code, now)).toEqual({
      line: "SVA down since 01:10Z · 1 more station issue",
      all: ["SVA down since 01:10Z", "KIR degraded since 11-12 20:00Z"],
    });
    expect(worstStationIssue({ ...a, stations: [st("fbk", "up", null)] }, code, now)).toBeNull();
  });
});
