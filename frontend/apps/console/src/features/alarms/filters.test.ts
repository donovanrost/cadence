import { describe, expect, it } from "vite-plus/test";
import { spacecraftId } from "@/api/index.ts";
import { scid as scidReader } from "@/api/index.ts";
import {
  craftInSentence,
  craftStandalone,
  filtered,
  filteredEmpty,
  filtersOf,
  matches,
  shownLine,
  spacecraftOptions,
  withFilter,
  type FleetNames,
} from "./filters.ts";
import { episodeFixture } from "./fixtures.ts";

const names: Record<string, string> = {
  // keyed-by-text: a test lookup of fixture spacecraft names.
  "sc-312": "EARENDIL-312",
  "sc-047": "EARENDIL-047",
};
const nameOf = (id: string) => names[id] ?? null;
const ready: FleetNames = { state: "ready", names: new Map(Object.entries(names)) };

describe("Alarms filters (ux U69 A6)", () => {
  it("reads ?sc= and ?severity= from the URL; both severities is none", () => {
    expect(filtersOf({})).toEqual({ spacecraftId: null, severities: [] });
    expect(filtersOf({ sc: "sc-047", severity: "critical" })).toEqual({
      spacecraftId: "sc-047",
      severities: ["critical"],
    });
    expect(filtersOf({ severity: "caution,critical,bogus" }).severities).toEqual([]);
    expect(filtered(filtersOf({ severity: "critical,caution" }))).toBe(false);
  });
  it("matches spacecraft and severity together", () => {
    const e = episodeFixture({ severity: "caution" });
    expect(matches(e, { spacecraftId: "sc-312", severities: ["caution"] })).toBe(true);
    expect(matches(e, { spacecraftId: null, severities: ["critical"] })).toBe(false);
    expect(matches(e, { spacecraftId: "sc-047", severities: [] })).toBe(false);
  });
  it("lists only spacecraft with alarms, with counts; the selected one stays", () => {
    const b = spacecraftId("sc-047");
    const list = [
      episodeFixture(),
      episodeFixture({ id: "2" }),
      episodeFixture({ id: "3", spacecraft_id: b }),
    ];
    expect(spacecraftOptions(list, null, ready)).toEqual([
      { value: "sc-047", label: "EARENDIL-047 (1)" },
      { value: "sc-312", label: "EARENDIL-312 (2)" },
    ]);
    expect(spacecraftOptions([], "sc-047", ready)).toEqual([
      { value: "sc-047", label: "EARENDIL-047 (0)" },
    ]);
  });
  it("names the filters when nothing matches, and counts what's shown", () => {
    expect(filteredEmpty({ spacecraftId: "sc-312", severities: ["critical"] }, nameOf)).toBe(
      "No critical alarms on EARENDIL-312.",
    );
    expect(filteredEmpty({ spacecraftId: null, severities: ["caution"] }, nameOf)).toBe(
      "No caution alarms.",
    );
    expect(filteredEmpty({ spacecraftId: "sc-312", severities: [] }, nameOf)).toBe(
      "No alarms on EARENDIL-312.",
    );
    expect(shownLine(4, 17, 17, false)).toBe("4 of 17 shown");
    expect(shownLine(4, 200, 400, true)).toBe("4 of 200 shown · from the 400 loaded");
  });
  it("changes one filter and drops empty ones from the URL", () => {
    expect(withFilter({ tab: "acknowledged", sc: "a" }, "sc", null)).toEqual({
      tab: "acknowledged",
    });
    expect(withFilter({ point: "VBAT" }, "severity", "critical")).toEqual({
      point: "VBAT",
      severity: "critical",
    });
  });
});

/** ux's ruling on #652: a craft's name goes by the fleet read's state; never the internal id. */
describe("craft names by the fleet read (U25, U20)", () => {
  const loading: FleetNames = { state: "loading" };
  const failed: FleetNames = { state: "failed" };
  const lost = (n: number) => {
    const id = spacecraftId(`sc-lost-${n}`);
    return episodeFixture({
      spacecraft_id: id,
      spacecraft: { id, name: null, scid: scidReader(n) },
    });
  };

  it("ready, and the craft isn't in it: an unknown spacecraft, with its SCID standing alone", () => {
    expect(craftInSentence("sc-lost-9", 9999, ready)).toBe("an unknown spacecraft");
    expect(craftStandalone("sc-lost-9", 9999, ready)).toBe("Unknown spacecraft · SCID 9999");
    expect(craftStandalone("sc-lost-9", null, ready)).toBe("Unknown spacecraft");
    expect(craftInSentence("sc-312", 312, ready)).toBe("EARENDIL-312");
    expect(spacecraftOptions([lost(9999)], null, ready)).toEqual([
      { value: "sc-lost-9999", label: "Unknown spacecraft · SCID 9999 (1)" },
    ]);
  });

  it("loading: nothing is named yet, so the lines and the picker wait", () => {
    expect(craftInSentence("sc-312", 312, loading)).toBeNull();
    expect(craftStandalone("sc-312", 312, loading)).toBeNull();
    expect(spacecraftOptions([lost(9999)], null, loading)).toEqual([]);
    expect(
      filteredEmpty({ spacecraftId: "sc-312", severities: [] }, (id) =>
        craftInSentence(id, 312, loading),
      ),
    ).toBeNull();
  });

  it("failed: a spacecraft by its SCID, never claimed unknown", () => {
    expect(craftInSentence("sc-312", 312, failed)).toBe("a spacecraft (SCID 312)");
    expect(craftInSentence("sc-312", null, failed)).toBe("a spacecraft");
    expect(craftStandalone("sc-312", 312, failed)).toBe("SCID 312");
    expect(craftStandalone("sc-312", null, failed)).toBe("Spacecraft");
    expect(spacecraftOptions([lost(9999)], null, failed)).toEqual([
      { value: "sc-lost-9999", label: "SCID 9999 (1)" },
    ]);
  });

  it("never says the internal id, in any state", () => {
    for (const fleet of [ready, loading, failed]) {
      for (const scid of [9999, null]) {
        expect(craftInSentence("sc-lost-9", scid, fleet) ?? "").not.toContain("sc-lost-9");
        expect(craftStandalone("sc-lost-9", scid, fleet) ?? "").not.toContain("sc-lost-9");
      }
    }
  });
});
