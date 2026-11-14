import { describe, expect, it } from "vite-plus/test";
import { chained, mergedSpans } from "./chart-events.ts";
import type { ChartMarker } from "./chart-input.ts";

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

describe("mission event marks", () => {
  const at = (left: number, id: string) => ({
    left,
    marker: { marker_id: id } satisfies ChartMarker,
  });
  it("chains a dense run (a once-a-second event stream) into one mark", () => {
    const runs = chained([at(10, "a"), at(14, "b"), at(18, "c"), at(22, "d"), at(40, "e")], 6);
    expect(runs.map((r) => [r.left, r.markers.length])).toEqual([
      [10, 4],
      [40, 1],
    ]);
  });
});
