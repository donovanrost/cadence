import { describe, expect, it } from "vite-plus/test";
import { spacecraftRow } from "@/features/fleet/index.ts";
import {
  grouped,
  groupJump,
  parseQuery,
  PER_GROUP,
  rowsOf,
  search,
  type PageEntry,
} from "./results.ts";
import type { TelemetryPoint } from "@/features/telemetry/index.ts";
import { pointItems, telemetryQuery } from "./telemetry.ts";

const fleet = Array.from({ length: 500 }, (_, i) => spacecraftRow(i + 1));
const pages: PageEntry[] = [
  { name: "ops.now", title: "Now", mode: "ops" },
  { name: "ops.contacts", title: "Contacts", mode: "ops" },
];

describe("palette search", () => {
  it("puts the exact SCID first for numeric queries", () => {
    const items = search("312", fleet, pages, true);
    expect(items[0]?.title).toBe("EARENDIL-312");
    expect(items[0]?.hint).toBe("SCID 312");
    expect(items[0]?.commandTo).toEqual({
      name: "ops.commands.new",
      query: { targets: "sc:spacecraft-earendil-312" },
    });
  });

  it("offers no command entries without command access (DECISIONS #38)", () => {
    const items = search("312", fleet, pages, false);
    expect(items[0]?.commandTo).toBeNull();
    expect(items.filter((i) => i.group === "Actions")).toEqual([]);
  });

  it("offers 'Command …' for a narrow spacecraft match", () => {
    const actions = search("312", fleet, pages, true).filter((i) => i.group === "Actions");
    expect(actions.map((a) => a.title)).toEqual(["Command EARENDIL-312…"]);
  });

  it("shows pages (not spacecraft) for an empty query", () => {
    expect(search("", fleet, pages, true).map((i) => i.group)).toEqual(["Pages", "Pages"]);
  });

  it("honours prefixes and finds pages by title", () => {
    expect(parseQuery("# 31")).toEqual({ text: "31", only: "spacecraft" });
    expect(search("#contacts", fleet, pages, true)).toEqual([]);
    expect(search(">set_", fleet, pages, true)).toEqual([]);
    expect(search("cont", fleet, pages, true).map((i) => i.title)).toEqual(["Contacts"]);
  });

  it("caps groups at five rows unless expanded", () => {
    const items = search("earendil", fleet, pages, true);
    const [first] = grouped(items, new Set());
    expect(first?.items).toHaveLength(PER_GROUP);
    expect(first?.more).toBe(500 - PER_GROUP);
    expect(grouped(items, new Set(["Spacecraft"]))[0]?.items).toHaveLength(500);
  });
});

describe("palette rows (qa #12, #13)", () => {
  it("adds a 'show all' option per capped group and jumps between groups", () => {
    const rows = rowsOf(grouped(search("earendil", fleet, pages, true), new Set()));
    expect(rows.find((r) => r.kind === "more")).toMatchObject({
      key: "more-Spacecraft",
      total: 500,
    });
    const mixed = rowsOf(grouped(search("3", fleet, pages, true), new Set()));
    const firstAction = mixed.findIndex((r) => r.group !== "Spacecraft");
    expect(groupJump(mixed, 0, false)).toBe(firstAction === -1 ? 0 : firstAction);
    expect(groupJump(mixed, 0, true)).toBe(mixed.findIndex((r) => r.group === mixed.at(-1)?.group));
  });
});

describe("palette telemetry (M23)", () => {
  const point = (id: string, latest: TelemetryPoint["latest"] = null): TelemetryPoint => ({
    id,
    name: id.split(".").at(-1) ?? id,
    description: null,
    has_limits: undefined,
    unit: "V",
    subsystem: "EPS",
    type: "numeric",
    latest,
  });

  it("scopes `312 vbat` to the spacecraft and needs 2+ characters otherwise", () => {
    expect(telemetryQuery("312 vbat", fleet)?.spacecraft?.scid).toBe(312);
    expect(telemetryQuery("312 vbat", fleet)?.q).toBe("vbat");
    expect(telemetryQuery("vbat", fleet)).toEqual({ q: "vbat", spacecraft: null });
    expect(telemetryQuery("v", fleet)).toBeNull();
  });

  it("writes `312 › VBAT` rows with the latest value and plots on ↵", () => {
    const sc = fleet.find((s) => s.scid === 312) ?? null;
    const [row] = pointItems(
      [
        point("EPS.VBAT", {
          value: 23.1,
          received_at: null,
          limit_state: "critical",
          source: undefined,
        }),
      ],
      sc,
    );
    expect(row).toMatchObject({
      group: "Telemetry",
      title: "312 › VBAT",
      subtitle: "23.1 V · EPS · EPS.VBAT",
      state: "crit",
      to: { name: "ops.telemetry", query: { sc: "312", p: "EPS.VBAT" } },
    });
    expect(pointItems([point("EPS.VBAT")], null)[0]?.subtitle).toBe("EPS · EPS.VBAT");
  });
});
