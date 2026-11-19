import { describe, expect, it } from "vite-plus/test";
import { chartSentence } from "./chart-sentence.ts";
import type { Series } from "./snapshot-series.ts";

describe("chart sentence (B5)", () => {
  const point = (v: number | null): [number, number | null] => [0, v];
  const s = (label: string, values: (number | null)[], unit: string | null = "V"): Series => ({
    id: label,
    label,
    unit,
    time_axis: "receipt_time",
    points: values.map(point),
  });
  const live = { live: true, from: null, to: null, windowSeconds: 900 };
  it("says what it plots, over when, and each series' latest value", () => {
    expect(chartSentence("Bus voltage", [s("BUS_V", [28.1, 28.04, null])], live)).toBe(
      "Bus voltage, the last 15 minutes. Latest: BUS_V 28.04 V.",
    );
  });
  it("reads a fixed range, and counts series past four", () => {
    const many = ["A", "B", "C", "D", "E", "F"].map((l) => s(l, [1], null));
    const fixed = {
      live: false,
      from: "2026-11-10T00:00:00Z",
      to: "2026-11-10T06:00:00Z",
      windowSeconds: 21_600,
    };
    const text = chartSentence("Temps", many, fixed);
    expect(text).toMatch(/^Temps, .+ to .+\. Latest: A 1, B 1, C 1, D 1, and 2 more series\.$/);
  });
  it("says an empty range has no samples", () => {
    expect(chartSentence("", [], live)).toBe(
      "Time series, the last 15 minutes: no samples in this range.",
    );
  });
});
