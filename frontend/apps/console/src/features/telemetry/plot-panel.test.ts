import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import {
  scid as scidReader,
  spacecraftId as spacecraftIdReader,
  pointId as pointIdReader,
} from "@/api/index.ts";
import { spacecraftRow } from "@/features/fleet/index.ts";
import type { History } from "@/features/investigate/index.ts";
import PlotPanel from "./PlotPanel.vue";
import type { SeriesData } from "./useSeries.ts";

const history = (truncated: boolean): History => ({
  point_id: pointIdReader("EPS.VBAT"),
  unit: "V",
  description: null,
  spacecraft_id: spacecraftIdReader("sc"),
  from: "2026-11-08T00:00:00Z",
  to: "2026-11-08T06:00:00Z",
  bucket_width_ms: 60_000,
  truncated,
  buckets: [],
});
const rows = (truncated: boolean): SeriesData[] => [
  {
    key: { scid: scidReader(1), pointId: pointIdReader("EPS.VBAT") },
    sc: spacecraftRow(1),
    history: history(truncated),
  },
];

function render(props: Record<string, unknown>) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: "/:p(.*)", component: { template: "<div />" } }],
  });
  return mount(PlotPanel, {
    props: {
      window: { from: 0, to: 1 },
      view: null,
      empty: false,
      dropped: 0,
      windowLabel: "6 h",
      state: { status: "ready", value: rows(false), receivedAt: new Date() },
      ...props,
    },
    global: { plugins: [router], stubs: { TrendChart: true, ApTimeRange: true } },
  });
}

describe("Telemetry plot honesty (§11c(D), ux)", () => {
  it("says the plot is incomplete when a history read hit its cap (D11)", () => {
    expect(render({}).text()).not.toContain("plot is incomplete");
    const capped = render({
      state: { status: "ready", value: rows(true), receivedAt: new Date() },
    });
    expect(capped.text()).toContain(
      "This range has more samples than one read returns (20,000). The plot shows 00:00Z to 00:00Z",
    );
  });

  it("asks for a spacecraft when points have none (D12), never an empty plot", async () => {
    const w = render({ empty: true, pointsWithoutSc: ["EPS.VBAT", "EPS.IBAT"] });
    expect(w.text()).toContain("Pick a spacecraft to plot EPS.VBAT and 1 more.");
    expect(w.text()).not.toContain("Pick a point to plot");
    await w.get("button").trigger("click");
    expect(w.emitted("pickSc")).toHaveLength(1);
  });

  it("keeps the last plot when a refresh fails, saying when each read was", async () => {
    const w = render({
      refreshFailed: {
        at: new Date("2026-11-16T09:41:05Z"),
        readAt: new Date("2026-11-16T09:40:02Z"),
      },
    });
    const line = w.get('[role="status"]');
    expect(line.text().replace(/\s+/g, " ")).toContain(
      "Couldn't refresh at 09:41Z; showing data read at 09:40Z.",
    );
    await line.get("button").trigger("click");
    expect(w.emitted("retry")).toHaveLength(1);
  });
});
