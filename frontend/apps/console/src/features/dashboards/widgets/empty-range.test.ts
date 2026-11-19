import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { field, frame, snapshotJson } from "../fixtures.test-support.ts";
import { workspaceSnapshot, type WidgetType } from "../model/snapshot.ts";
import WidgetBody from "./WidgetBody.vue";

/** The first placement of a `type` board whose primary frames carry no samples. */
function emptyBoard(type: WidgetType) {
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
const body = (type: WidgetType) => {
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
  it("draws a FIXED past range with no samples, with its contact band (qa: ZKgUX, 11-10)", () => {
    const at = (iso: string) => Date.parse(iso);
    const base = snapshotJson("time_series");
    const r = decode(workspaceSnapshot, {
      ...base,
      context: {
        ...base.context,
        time_mode: "range",
        from: "2026-11-10T02:55:00Z",
        to: "2026-11-10T03:25:00Z",
      },
      placements: base.placements.map((p, i) =>
        i === 0
          ? {
              ...p,
              frames: [
                // A past range's empty primary frame: a time column and no values to parse.
                frame("wide", [field("time", "time", [])]),
                frame(
                  "intervals",
                  [
                    field("starts_at", "time", [at("2026-11-10T03:05:57Z")]),
                    field("ends_at", "time", [at("2026-11-10T03:13:57Z")]),
                    field("kind", "enum", ["realized_contact"]),
                    field("contact_id", "string", ["zkgux"]),
                    field("started", "boolean", [false]),
                    field("close_reason", "string", ["window_ended"]),
                  ],
                  "events",
                ),
              ],
            }
          : p,
      ),
    });
    if (!r.ok) throw new Error("fixture");
    const placement = r.value.placements[0];
    if (!placement) throw new Error("fixture");
    const w = mount(WidgetBody, {
      props: { placement, context: r.value.context, now: 0, group: "g", chartId: "c" },
      global: { stubs: { TelemetryChart: true } },
    });
    const chart = w.findComponent({ name: "TelemetryChart" });
    expect(chart.exists()).toBe(true);
    expect(chart.props("time_from")).toBe("2026-11-10T02:55:00Z");
    expect(chart.props("event_markers")).toEqual([
      expect.objectContaining({ marker_id: "zkgux", started: false, close_reason: "window_ended" }),
    ]);
    expect(w.text()).toContain("No samples in this range.");
  });
});
