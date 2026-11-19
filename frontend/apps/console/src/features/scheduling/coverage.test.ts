import { describe, expect, it } from "vite-plus/test";
import { contactsShortText, coverage, spacecraftNotCovered } from "./coverage.ts";
import { station } from "./fixtures.ts";

const sc = (id: string, have: number, need: number | null, met: boolean) => ({
  spacecraft_id: id,
  rule_met: met,
  contacts: { have, need },
  reasons: [],
  longest_gap: null,
  uplink_passes: null,
});

describe("coverage (ux U23)", () => {
  it("counts uncovered spacecraft first and contacts short second", () => {
    const c = coverage({
      demand: {
        rule_met: 1,
        rule_total: 3,
        spacecraft: [sc("a", 3, 3, true), sc("b", 1, 3, false), sc("c", 0, 4, false)],
        rules: [],
      },
      unmet: [
        { requirement_id: "r1", requirement_version: 1, spacecraft_id: "b", why: [] },
        { requirement_id: "r2", requirement_version: 1, spacecraft_id: "c", why: [] },
        { requirement_id: "r3", requirement_version: 1, spacecraft_id: "c", why: [] },
      ],
    });
    expect(c).toEqual({ spacecraft: 2, contactsShort: 6, gaps: 2 });
    expect(spacecraftNotCovered(c.spacecraft)).toBe("2 spacecraft not covered");
    expect(contactsShortText(1)).toBe("1 contact short");
  });
});

describe("distinctWindows (ux K1 #5)", () => {
  it("keeps one row per station + window", async () => {
    const { distinctWindows } = await import("./api.ts");
    const alt = (id: string, req: string) => ({
      snapshot_id: id,
      requirement_id: req,
      station: station({ ref: "earendil-fairbanks", id: "gs_1", code: "FAI", name: "Fairbanks" }),
      starts_at: "2026-11-11T12:09:00Z",
      ends_at: "2026-11-11T12:17:00Z",
      synthetic: true,
      effect: {
        rule_met_after: false,
        contacts_after: { have: 5, need: 8 },
        clashes_with: [],
        longest_gap_after_seconds: null,
      },
    });
    expect(distinctWindows([alt("s1", "r1"), alt("s2", "r2")]).map((a) => a.snapshot_id)).toEqual([
      "s1",
    ]);
  });
});

describe("station labels (ux U25)", () => {
  it("prefer the confirmed code, then the name, never a guess", async () => {
    const { stationCode, stationName } = await import("./api.ts");
    expect(
      stationCode(
        station({ ref: "earendil-fairbanks", id: "gs_1", code: "FAI", name: "Fairbanks" }),
      ),
    ).toBe("FAI");
    expect(
      stationCode(
        station({ ref: "earendil-fairbanks", id: "gs_1", code: null, name: "Fairbanks (Demo)" }),
      ),
    ).toBe("Fairbanks (Demo)");
    expect(stationCode(station({ ref: "earendil-x", id: null, code: null, name: null }))).toBe(
      "earendil-x",
    );
    expect(stationName(null)).toBe("unknown station");
  });
});
