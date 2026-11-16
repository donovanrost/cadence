import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import ApTimeSeries from "./ApTimeSeries.vue";

const base = {
  window: { from: 0, to: 1_000_000 },
  label: "VBAT over 6 h",
  formatTick: (t: number) => String(t),
  formatValue: (v: number) => v.toFixed(1),
  stepMs: 100_000,
  series: [
    { t: 400_000, min: 24, mean: 24, max: 24 },
    { t: 500_000, min: 23, mean: 23, max: 23 },
  ],
};

describe("ApTimeSeries marks (fe-ops, lead's review)", () => {
  it("rings the main series at the mark and reads the label out", () => {
    const w = mount(ApTimeSeries, {
      props: { ...base, marks: [{ t: 500_000, label: "the sample that raised it, 02:08:11Z" }] },
    });
    expect(w.findAll(".rounded-full")).toHaveLength(1);
    expect(w.findAll(".border-dashed")).toHaveLength(1);
    expect(w.find(".sr-only").text()).toBe("Marked: the sample that raised it, 02:08:11Z.");
  });
  it("draws the vertical alone where the named series has no value, and skips marks outside", () => {
    const w = mount(ApTimeSeries, {
      props: {
        ...base,
        marks: [
          { t: 900_000, label: "gap" },
          { t: 500_000, label: "other", series: "missing" },
          { t: 2_000_000, label: "outside" },
        ],
      },
    });
    expect(w.findAll(".rounded-full")).toHaveLength(0);
    expect(w.findAll(".border-dashed")).toHaveLength(2);
  });
});
