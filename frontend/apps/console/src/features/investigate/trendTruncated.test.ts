import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { historyReader } from "./api.ts";
import TrendBlock from "./TrendBlock.vue";

const history = (truncated: boolean) => {
  const r = decode(historyReader, {
    point_id: "EPS.VBAT",
    unit: "V",
    description: null,
    spacecraft_id: "sc-312",
    from: "2026-11-16T00:00:00Z",
    to: "2026-11-16T06:00:00Z",
    bucket_width_ms: 60_000,
    truncated,
    buckets: [],
  });
  if (!r.ok) throw new Error(r.error.message);
  return { status: "ready" as const, value: r.value, receivedAt: new Date() };
};
const view = { window: { from: 0, to: 1 }, series: [], limits: [], sentence: "", stepMs: 60_000 };
const LINE =
  "This range has more samples than one read returns (20,000), so the plot is incomplete.";

describe("D11: a history read that hit its cap says so (ux)", () => {
  it("shows the line only when the read is truncated", () => {
    const at = (truncated: boolean) =>
      mount(TrendBlock, {
        props: {
          pointName: "Battery",
          unit: "V",
          rangeLabel: "6 h",
          history: history(truncated),
          view,
        },
      }).text();
    expect(at(true)).toContain(LINE);
    expect(at(true)).toContain("Pick a shorter range to see all of it.");
    expect(at(false)).not.toContain(LINE);
  });
});
