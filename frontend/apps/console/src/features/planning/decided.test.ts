import { describe, expect, it } from "vite-plus/test";
import { decidedLine, type Decided } from "./decided.ts";

const day = (date: string, spacecraft = 1) => ({
  occurrence_at: `${date}T00:00:00Z`,
  date,
  spacecraft_ids: Array.from({ length: spacecraft }, (_, i) => `sc-${i}`),
});
const none: Decided = { planned_or_started: [], closed: [], canceled: [] };

describe("decided count line (ux U48)", () => {
  it("stands alone when nothing is decided", () => {
    expect(decidedLine(none, 3)).toBe("v3 applies to every day that's still open.");
  });
  it("names up to 3 days, in days when there's one spacecraft, and drops empty groups", () => {
    expect(
      decidedLine(
        {
          planned_or_started: [day("2026-11-15"), day("2026-11-14"), day("2026-11-16")],
          closed: [day("2026-11-12"), day("2026-11-13")],
          canceled: [day("2026-11-11")],
        },
        3,
      ),
    ).toBe(
      "v3 applies to every day that's still open. 3 days already planned or started keep their requirement: 11-14, 11-15, 11-16. 2 closed days stay closed: 11-12, 11-13. 1 canceled day stays canceled: 11-11.",
    );
    expect(decidedLine({ ...none, planned_or_started: [day("2026-11-14")] }, 2)).toBe(
      "v2 applies to every day that's still open. 1 day already planned or started keeps its requirement: 11-14.",
    );
  });
  it("leads with requirements when several spacecraft share a day, and spans more than 3 days", () => {
    const kept = ["2026-11-14", "2026-11-16", "2026-11-17", "2026-11-20"].map((d) => day(d, 375));
    expect(
      decidedLine({ ...none, planned_or_started: kept, closed: [day("2026-11-15", 2)] }, 4),
    ).toBe(
      "v4 applies to every day that's still open. 1,500 requirements on 4 days between 11-14 and 11-20, already planned or started, stay as they are. 2 closed requirements on 1 day stay closed: 11-15.",
    );
  });
  it("puts a span of more than 3 days right after the noun", () => {
    const five = ["2026-11-14", "2026-11-15", "2026-11-17", "2026-11-18", "2026-11-20"];
    expect(
      decidedLine(
        {
          ...none,
          planned_or_started: five.map((d) => day(d)),
          closed: five.slice(0, 4).map((d) => day(d)),
        },
        3,
      ),
    ).toBe(
      "v3 applies to every day that's still open. 5 days between 11-14 and 11-20, already planned or started, keep their requirement. 4 closed days between 11-14 and 11-18 stay closed.",
    );
  });
});
