import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { snapshotJson } from "../fixtures.test-support.ts";
import { workspaceSnapshot } from "../model/snapshot.ts";
import WidgetBody from "./WidgetBody.vue";

/** The first placement of a `type` board whose primary frames carry no samples. */
function emptyBoard(type: string) {
  const base = snapshotJson(type);
  const r = decode(workspaceSnapshot, {
    ...base,
    placements: base.placements.map((p) => ({
      ...p,
      frames: p.frames.map((f) => ({ ...f, fields: f.fields.map((x) => ({ ...x, values: [] })) })),
    })),
  });
  if (!r.ok) throw new Error("fixture");
  const placement = r.value.placements[0];
  if (!placement) throw new Error("fixture");
  return { placement, context: r.value.context };
}
const body = (type: string) => {
  const { placement, context } = emptyBoard(type);
  // The real chart needs the design tokens (not in jsdom); a stub shows whether it's drawn and how.
  return mount(WidgetBody, {
    props: {
      placement,
      context,
      now: Date.parse("2026-11-14T10:00:00Z"),
      group: "g",
      chartId: "c",
    },
    global: { stubs: { TelemetryChart: true } },
  });
};

describe("an empty range (ux, Overlays)", () => {
  it("keeps a time series (bands and marks still draw) and says 'No samples', never why", () => {
    const w = body("time_series");
    expect(w.text()).toContain("No samples in this range.");
    expect(w.text()).not.toContain("No data in this range.");
  });
  it("draws an empty LIVE range as now−window…now with the now-line (the chart's live mode)", () => {
    const chart = body("time_series").findComponent({ name: "TelemetryChart" });
    expect(chart.exists()).toBe(true);
    expect(chart.props("time_mode")).toBe("live");
    expect(chart.props("time_to")).toBe("2026-11-14T10:00:00.000Z");
  });
  it("keeps the plain message on tiles", () => {
    expect(body("value_tile").text()).toContain("No data in this range.");
  });
});
