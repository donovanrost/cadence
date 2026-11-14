import { describe, expect, it } from "vite-plus/test";
import { mergedSpans } from "./chart-events.ts";

describe("contact tints (qa's overlay look)", () => {
  it("merges overlapping or touching passes into one tint, so 5% washes never stack", () => {
    expect(
      mergedSpans([
        { left: 300, width: 50 },
        { left: 10, width: 40 },
        { left: 30, width: 40 },
        { left: 70, width: 10 },
      ]),
    ).toEqual([
      { left: 10, width: 70 },
      { left: 300, width: 50 },
    ]);
  });
  it("keeps a pass inside a longer one as the longer one", () => {
    expect(
      mergedSpans([
        { left: 0, width: 100 },
        { left: 20, width: 10 },
      ]),
    ).toEqual([{ left: 0, width: 100 }]);
  });
});
