import { describe, expect, it } from "vite-plus/test";
import { decidedLine, type Decided } from "./decided.ts";

/** A group as the server counts it (#793): distinct days, requirements, first/last, and ≤3 dates. */
const group = (dates: readonly string[], perDay = 1): Decided["closed"] => {
  const days = [...new Set(dates)].sort();
  return {
    days: days.length,
    requirements: dates.length * perDay,
    dates: days.length <= 3 ? days : [],
    first_date: days[0] ?? null,
    last_date: days.at(-1) ?? null,
  };
};
const empty = group([]);
const none: Decided = { planned_or_started: empty, closed: empty, canceled: empty };

describe("decided count line (ux U48)", () => {
  it("stands alone when nothing is decided", () => {
    expect(decidedLine(none, 3)).toBe("v3 applies to every day that's still open.");
  });
  it("names up to 3 days, in days when there's one spacecraft, and drops empty groups", () => {
    expect(
      decidedLine(
        {
          planned_or_started: group(["2026-11-15", "2026-11-14", "2026-11-16"]),
          closed: group(["2026-11-12", "2026-11-13"]),
          canceled: group(["2026-11-11"]),
        },
        3,
      ),
    ).toBe(
      "v3 applies to every day that's still open. 3 days already planned or started keep their requirement: 11-14, 11-15, 11-16. 2 closed days stay closed: 11-12, 11-13. 1 canceled day stays canceled: 11-11.",
    );
    expect(decidedLine({ ...none, planned_or_started: group(["2026-11-14"]) }, 2)).toBe(
      "v2 applies to every day that's still open. 1 day already planned or started keeps its requirement: 11-14.",
    );
  });
  it("leads with requirements when several spacecraft share a day, and spans more than 3 days", () => {
    const kept = group(["2026-11-14", "2026-11-16", "2026-11-17", "2026-11-20"], 375);
    expect(
      decidedLine({ ...none, planned_or_started: kept, closed: group(["2026-11-15"], 2) }, 4),
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
          planned_or_started: group(five),
          closed: group(five.slice(0, 4)),
        },
        3,
      ),
    ).toBe(
      "v3 applies to every day that's still open. 5 days between 11-14 and 11-20, already planned or started, keep their requirement. 4 closed days between 11-14 and 11-18 stay closed.",
    );
  });
});
