import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { historyReader } from "./api.ts";
import { truncatedLine } from "./model.ts";
import TrendBlock from "./TrendBlock.vue";

const read = (truncated: boolean, from: string, to: string, lastEnd: string | null) => {
  const r = decode(historyReader, {
    point_id: "EPS.VBAT",
    unit: "V",
    description: null,
    spacecraft_id: "sc-312",
    from,
    to,
    bucket_width_ms: 60_000,
    truncated,
    buckets: lastEnd ? [{ t: from, t_end: lastEnd, min: 1, max: 1, mean: 1, count: 20_000 }] : [],
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};

describe("D11: a history read that hit its cap says how much it shows (ux)", () => {
  it("names the shown span: the read's start to the last bucket's end", () => {
    expect(
      truncatedLine(
        read(true, "2026-11-16T09:00:00Z", "2026-11-16T15:00:00Z", "2026-11-16T10:12:00Z"),
      ),
    ).toBe(
      "This range has more samples than one read returns (20,000). The plot shows 09:00Z to 10:12Z; samples after 10:12Z weren't read. Pick a shorter or later range to see the rest.",
    );
  });

  it("dates both ends when the shown span crosses days (§4)", () => {
    expect(
      truncatedLine(
        read(true, "2026-11-15T22:00:00Z", "2026-11-16T22:00:00Z", "2026-11-16T03:12:00Z"),
      ),
    ).toContain(
      "The plot shows 11-15 22:00Z to 11-16 03:12Z; samples after 11-16 03:12Z weren't read.",
    );
  });

  it("says nothing when the read wasn't cut", () => {
    expect(truncatedLine(read(false, "2026-11-16T09:00:00Z", "2026-11-16T15:00:00Z", null))).toBe(
      null,
    );
  });

  it("shows the line under the plot", () => {
    const value = read(
      true,
      "2026-11-16T09:00:00Z",
      "2026-11-16T15:00:00Z",
      "2026-11-16T10:12:00Z",
    );
    const w = mount(TrendBlock, {
      props: {
        pointName: "Battery",
        unit: "V",
        rangeLabel: "6 h",
        history: { status: "ready", value, receivedAt: new Date() },
        view: { window: { from: 0, to: 1 }, series: [], limits: [], sentence: "", stepMs: 60_000 },
      },
    });
    expect(w.text()).toContain("samples after 10:12Z weren't read");
  });
});
