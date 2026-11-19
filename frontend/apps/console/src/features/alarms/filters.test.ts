import { describe, expect, it } from "vite-plus/test";
import { spacecraftId } from "@/api/index.ts";
import {
  filtered,
  filteredEmpty,
  filtersOf,
  matches,
  shownLine,
  spacecraftOptions,
  withFilter,
} from "./filters.ts";
import { episodeFixture } from "./fixtures.ts";

const names: Record<string, string> = {
  // keyed-by-text: a test lookup of fixture spacecraft names.
  "sc-312": "EARENDIL-312",
  "sc-047": "EARENDIL-047",
};
const nameOf = (id: string) => names[id] ?? id;

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
    expect(spacecraftOptions(list, null, nameOf)).toEqual([
      { value: "sc-047", label: "EARENDIL-047 (1)" },
      { value: "sc-312", label: "EARENDIL-312 (2)" },
    ]);
    expect(spacecraftOptions([], "sc-047", nameOf)).toEqual([
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
