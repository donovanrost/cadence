import { describe, expect, it } from "vite-plus/test";
import { filtered, filtersOf, severitiesOf, withFilter } from "./filters.ts";

describe("Alarms filters (ux U69 A6)", () => {
  it("reads ?sc= and ?severity= from the URL; both severities is none", () => {
    expect(filtersOf({})).toEqual({ spacecraftId: null, severity: null });
    expect(filtersOf({ sc: "sc-047", severity: "critical" })).toEqual({
      spacecraftId: "sc-047",
      severity: "critical",
    });
    expect(filtersOf({ severity: "caution,critical" }).severity).toBeNull();
    expect(severitiesOf({ severity: "caution,critical,bogus" })).toEqual(["critical", "caution"]);
    expect(filtered(filtersOf({ severity: "critical,caution" }))).toBe(false);
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
