import { describe, expect, it } from "vite-plus/test";
import { stationId } from "@/api";
import type { CommandSummary } from "@/features/commands/index.ts";
import type { Station } from "@/features/stations/index.ts";
import { grouped } from "./results.ts";
import { catalogQuery, commandItems, stationItems } from "./sources.ts";

const command = (name: string, extra: Partial<CommandSummary> = {}): CommandSummary => ({
  id: `cmd-${name.toLowerCase()}`,
  name,
  display_name: null,
  description: null,
  subsystem: null,
  group: null,
  significance: null,
  critical: false,
  hazardous: false,
  second_go_required: false,
  argument_count: 0,
  ...extra,
});

const station = (code: string | null, name: string, extra: Partial<Station> = {}): Station => ({
  id: stationId(`gs-${name.toLowerCase()}`),
  display_name: name,
  code,
  suggested_code: null,
  provider: null,
  region: null,
  lifecycle_state: "active",
  transport_count: null,
  routing_rule_count: null,
  health: null,
  ...extra,
});

describe("palette Commands group", () => {
  it("asks the catalog for `>` alone, 2+ characters unprefixed, never under another prefix", () => {
    expect(catalogQuery("", "commands")).toBe("");
    expect(catalogQuery("s", null)).toBeNull();
    expect(catalogQuery("set_", null)).toBe("set_");
    expect(catalogQuery("fbk", "stations")).toBeNull();
  });

  it("ranks a name prefix ahead of other matches and opens a new request with the command", () => {
    const items = commandItems(
      [
        command("RESET_ADCS", { subsystem: "ADCS" }),
        command("SET_ADCS_MODE", {
          display_name: "Set ADCS mode",
          subsystem: "ADCS",
          argument_count: 2,
        }),
      ],
      "set_",
    );
    expect(items.map((i) => i.title)).toEqual(["SET_ADCS_MODE", "RESET_ADCS"]);
    expect(items[0]).toMatchObject({
      group: "Commands",
      subtitle: "Set ADCS mode · ADCS · 2 arguments",
      hint: "CATALOG",
      to: { name: "ops.commands.new", query: { command: "cmd-set_adcs_mode" } },
      commandTo: { name: "ops.commands.new", query: { command: "cmd-set_adcs_mode" } },
    });
  });

  it("says a hazardous command in words, not only by its mark", () => {
    const [item] = commandItems([command("FIRE_THRUSTER", { hazardous: true })], "fire");
    expect(item?.subtitle).toBe("Hazardous · no arguments");
    expect(item?.state).toBe("caution");
  });
});

describe("palette Stations group", () => {
  const stations = [
    station("SVB", "Svalbard", {
      health: { status: "degraded", since: "2026-11-12T01:52:00Z" },
      provider: "KSAT",
    }),
    station("FBK", "Fairbanks"),
    station(null, "Old Site", { lifecycle_state: "archived" }),
  ];

  it("matches the code first and says a degraded station in words", () => {
    const items = stationItems(stations, "svb");
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({
      title: "SVB · Svalbard",
      subtitle: "Degraded since 01:52Z · KSAT",
      state: "caution",
      to: { name: "ops.contacts", query: { view: "station", station: "gs-svalbard" } },
    });
    expect(stationItems(stations, "fbk")[0]?.title).toBe("FBK · Fairbanks");
  });

  it("lists every active station for `@` alone, by name", () => {
    expect(stationItems(stations, "").map((i) => i.title)).toEqual([
      "FBK · Fairbanks",
      "SVB · Svalbard",
    ]);
  });

  it("sits between Commands and Profiles in the spec's group order", () => {
    const items = [...stationItems(stations, ""), ...commandItems([command("SET_MODE")], "")];
    expect(grouped(items, new Set()).map((g) => g.group)).toEqual(["Commands", "Stations"]);
  });
});
