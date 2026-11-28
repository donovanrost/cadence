import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import type { Density } from "./api.ts";
import DensityStrip from "./DensityStrip.vue";
import { densityLabel, densityTruncation } from "./model.ts";

/** Synthetic density reads in ops.md's events/density shape (#677), not captured from a server. */
const density = (truncated: boolean): Density => ({
  bucket_s: 900,
  truncated,
  buckets: [
    { t: "2026-11-08T04:00:00Z", critical: 1, caution: 2, nominal: 3, info: 3 },
    { t: "2026-11-08T04:15:00Z", critical: 0, caution: 0, nominal: 1, info: 1 },
  ],
});

describe("a density window the server cut (#677)", () => {
  it("says the counts are a floor, and what to do", () => {
    expect(densityTruncation(density(false))).toBeNull();
    expect(densityTruncation(density(true))).toBe(
      "The bars count only the first 5,000 events in this window. Narrow the window to count them all; the event log below lists every one.",
    );
    expect(densityLabel(density(false))).toBe("11 events in the window, busiest 04:00Z with 9.");
    expect(densityLabel(density(true))).toBe(
      "At least 11 events in the window, busiest 04:00Z with 9.",
    );
  });

  it("shows the line under the strip only when the window was cut", () => {
    const props = (truncated: boolean) => ({
      density: density(truncated),
      window: { from: Date.parse("2026-11-08T04:00:00Z"), to: Date.parse("2026-11-08T05:00:00Z") },
      now: Date.parse("2026-11-08T04:30:00Z"),
    });
    const cut = mount(DensityStrip, { props: props(true) });
    expect(cut.text()).toContain("The bars count only the first 5,000 events");
    expect(cut.get("svg").attributes("aria-label")).toMatch(/^At least 11 events/);
    const whole = mount(DensityStrip, { props: props(false) });
    expect(whole.text()).not.toContain("first 5,000");
  });
});
