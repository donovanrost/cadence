import { mount, type DOMWrapper } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { field, frame, snapshotJson } from "../fixtures.test-support.ts";
import { workspaceSnapshot, type WidgetType } from "../model/snapshot.ts";
import { formatTime, laneSentence, segmentLine, widgetTitle } from "../model/widget-data.ts";
import EventTimelineWidget from "./EventTimelineWidget.vue";
import StateTimelineWidget from "./StateTimelineWidget.vue";
import WidgetBody from "./WidgetBody.vue";
import WidgetPanel from "../viewer/WidgetPanel.vue";

/** #245: the viewer's scrolling widgets are named tab stops (B1), lists stay lists (B2), lanes say themselves (B5). */
function ready(type: WidgetType, title = "Battery") {
  const base = snapshotJson(type);
  const r = decode(workspaceSnapshot, {
    ...base,
    placements: base.placements.map((p) =>
      p.widget ? { ...p, widget: { ...p.widget, title } } : p,
    ),
  });
  if (!r.ok) throw r.error;
  const placement = r.value.placements[0];
  if (placement?.status !== "ready") throw new Error("fixture");
  return { placement, context: r.value.context };
}
/** WidgetBody with the fixture's data (data_table, constellation_health). */
function board(type: WidgetType, title = "Battery") {
  const { placement, context } = ready(type, title);
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
}

describe("widget scroll boxes (B1)", () => {
  const named = (box: DOMWrapper<Element>) => {
    expect(box.attributes("role")).toBe("region");
    expect(box.attributes("aria-label")).toBe("Battery");
  };
  it.each(["data_table", "constellation_health"] as const)(
    "%s scrolls in a named region that takes Tab",
    (type) => named(board(type).find('[tabindex="0"]')),
  );
  it("the state timeline scrolls in a named region that takes Tab", () => {
    const { placement } = ready("state_timeline");
    const w = mount(StateTimelineWidget, { props: { placement, now: 0 } });
    named(w.find('[tabindex="0"]'));
  });
  it("the event timeline's list scrolls as a named tab stop", () => {
    const { placement } = ready("event_timeline");
    const list = mount(EventTimelineWidget, { props: { placement } }).find("ol");
    expect(list.attributes("tabindex")).toBe("0");
    expect(list.attributes("aria-label")).toBe("Battery");
  });
  it("a table has its widget's name as caption; an untitled widget reads Untitled widget", () => {
    expect(board("data_table").find("caption").text()).toBe("Battery");
    expect(board("data_table", "").find("caption").text()).toBe("Untitled widget");
  });
  it("in its panel, an untitled widget is named by its place: heading, region and caption agree", () => {
    const { placement, context } = ready("data_table", "");
    const w = mount(WidgetPanel, {
      props: { placement, context, now: 0, group: "g", position: 3 },
      global: { stubs: { TelemetryChart: true } },
    });
    expect(w.get("h3").text()).toContain("Untitled widget 3");
    expect(w.get('[role="region"]').attributes("aria-label")).toBe("Untitled widget 3");
    expect(w.get("caption").text()).toBe("Untitled widget 3");
    expect(w.get('button[aria-label^="Inspect"]').attributes("aria-label")).toBe(
      "Inspect Untitled widget 3",
    );
  });
});

describe("constellation health (B2)", () => {
  it("keeps its cells as list items, with each spacecraft's words as text", () => {
    const w = board("constellation_health");
    expect(w.find('li[role="img"]').exists()).toBe(false);
  });
});

describe("state timeline lanes (B5)", () => {
  const at = Date.parse("2026-11-14T09:00:00Z");
  it("says one state from when, or how many and the last one (not now: U20)", () => {
    expect(laneSentence("Mode", [{ state: "SAFE", limit: null, from: at }])).toMatch(
      /^Mode: SAFE from .+\.$/,
    );
    expect(
      laneSentence("Mode", [
        { state: "SAFE", limit: null, from: at },
        { state: "NOMINAL", limit: "red", from: at + 60_000 },
      ]),
    ).toMatch(/^Mode: 2 states from .+, last NOMINAL \(red limit\)\.$/);
    expect(laneSentence("Mode", [])).toBe("Mode: no states.");
  });

  it("follows the lane image with a list of its segments", () => {
    const base = snapshotJson("state_timeline");
    const states = frame("intervals", [
      field("time", "time", [at, at + 60_000]),
      field("normalized_state", "enum", ["SAFE", "NOMINAL"]),
      field("limit_state", "enum", [null, "red"]),
      field("label", "string", ["Mode", "Mode"]),
    ]);
    const r = decode(workspaceSnapshot, {
      ...base,
      placements: base.placements.map((p) => (p.widget ? { ...p, frames: [states] } : p)),
    });
    if (!r.ok) throw r.error;
    const placement = r.value.placements[0];
    if (placement?.status !== "ready") throw new Error("fixture");
    const w = mount(StateTimelineWidget, { props: { placement, now: at + 120_000 } });
    expect(w.get('[role="img"]').attributes("aria-label")).toMatch(
      /^Mode: 2 states from .+, last NOMINAL \(red limit\)\.$/,
    );
    expect(
      w
        .get("ul.sr-only")
        .findAll("li")
        .map((li) => li.text()),
    ).toEqual([
      `SAFE from ${formatTime(at)}`,
      `NOMINAL, red limit, from ${formatTime(at + 60_000)}`,
    ]);
  });

  it("says each segment and when it started, beside the lane image", () => {
    expect(segmentLine({ state: "SAFE", limit: null, from: at })).toBe(
      `SAFE from ${formatTime(at)}`,
    );
    expect(segmentLine({ state: "NOMINAL", limit: "red", from: at + 60_000 })).toBe(
      `NOMINAL, red limit, from ${formatTime(at + 60_000)}`,
    );
  });
});

describe("widget names (B7)", () => {
  it("reads an unavailable placement as Unavailable widget", () => {
    expect(widgetTitle({ status: "unavailable" } as Parameters<typeof widgetTitle>[0])).toBe(
      "Unavailable widget",
    );
  });
});
