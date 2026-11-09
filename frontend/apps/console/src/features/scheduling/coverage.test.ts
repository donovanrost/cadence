import { describe, expect, it } from "vite-plus/test";
import { contactsShortText, coverage, spacecraftNotCovered } from "./coverage.ts";

const sc = (id: string, have: number, need: number | null, met: boolean) => ({
  spacecraft_id: id,
  rule_met: met,
  contacts: { have, need },
  reasons: [],
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
    expect(c).toEqual({ spacecraft: 2, contactsShort: 6, gaps: 3 });
    expect(spacecraftNotCovered(c.spacecraft)).toBe("2 spacecraft not covered");
    expect(contactsShortText(1)).toBe("1 contact short");
  });
});
