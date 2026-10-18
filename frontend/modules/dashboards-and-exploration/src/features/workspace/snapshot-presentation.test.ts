import { GridStack } from "gridstack";
import { required } from "../../../../../test-support/required";
import { normalizePoints, normalizeEnvelope } from "./chart-points";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent, h, onMounted } from "vue";
import { renderToString } from "vue/server-renderer";
import WorkspaceSnapshotCanvas from "./WorkspaceSnapshotCanvas.vue";
import TelemetryChart from "./TelemetryChart.vue";
import { CHART_RUNTIME_PORT, useChartRuntime } from "./chart-runtime";
import { snapshotPresentation, workspaceDomId } from "./snapshot-presentation";
import { snapshotSeries } from "./snapshot-series";
import { readWorkspaceSnapshot } from "./validation";
import { field, frame, snapshotContext, snapshotFixture } from "./snapshot-fixture.test-support";
import type { WorkspaceWidget } from "./contracts";

const apps: { unmount: () => void }[] = [];
afterEach(() => {
  for (const app of apps.splice(0)) app.unmount();
  vi.restoreAllMocks();
});
const body = (type: WorkspaceWidget["type"]) =>
  required(
    required(snapshotPresentation(snapshotFixture(type), "viewer").groups[0]).grid.widgets[0],
  ).presentation.body;
function render(model = snapshotFixture(), instanceId = "viewer") {
  const app = mount(WorkspaceSnapshotCanvas, {
    props: { snapshot: model, context: snapshotContext, instanceId },
    attachTo: document.body,
  });
  apps.push(app);
  return app;
}

test("all seven widget kinds receive domain-shaped content, not a generic fallback", () => {
  for (const type of [
    "value_tile",
    "time_series",
    "status_matrix",
    "data_table",
    "state_timeline",
    "event_timeline",
    "constellation_health",
  ] as const) {
    const result = body(type);
    expect(result.notice, type).toBeNull();
    expect(result.content?.presentation.kind, type).toBe(type);
  }
});
test("authored chart style enums reach the real chart markup without invented aliases", async () => {
  const model = snapshotFixture("time_series");
  Object.assign(required(required(model.placements[0]).widget).options, {
    legend_mode: "hidden",
    line_width: "bold",
    fill_opacity: 30,
  });
  const html = await renderToString(
    h(WorkspaceSnapshotCanvas, {
      snapshot: model,
      context: snapshotContext,
      instanceId: "chart-style",
    }),
  );
  const fragment = document.createElement("template");
  fragment.innerHTML = html;
  const chart = fragment.content.querySelector("[data-legend-mode]");
  expect(chart).not.toBeNull();
  expect(required(chart).getAttribute("data-legend-mode")).toBe("hidden");
  expect(required(chart).getAttribute("data-line-width")).toBe("bold");
  expect(required(chart).getAttribute("data-fill-opacity")).toBe("30");
  for (const options of [{ legend_mode: "never" }, { line_width: "thick" }]) {
    const invalid = structuredClone(model);
    Object.assign(required(required(invalid.placements[0]).widget).options, options);
    expect(() => readWorkspaceSnapshot(invalid, snapshotContext)).toThrow();
  }
});
test("real snapshot canvas preserves native grid and disclosure identity on data refresh", async () => {
  const app = render();
  const widget = app.get('[gs-id="battery"]').element;
  const grid = app.get(".grid-stack").element;
  const trigger = app.get('button[id$="-trigger"]');
  await trigger.trigger("click");
  await flushPromises();
  expect(trigger.attributes("aria-expanded")).toBe("false");
  const next = snapshotFixture();
  required(required(required(next.placements[0]).frames[0]).fields[1]).values = [29.1];
  await app.setProps({ snapshot: next });
  expect(app.get('[data-workspace-value="battery"]').text()).toBe("29.10");
  expect(app.get(".grid-stack").element).toBe(grid);
  expect(app.get('[gs-id="battery"]').element).toBe(widget);
  expect(trigger.attributes("aria-expanded")).toBe("false");
  expect(app.emitted("layout_changed")).toBeUndefined();
});
test("snapshot grid geometry is honored, and a geometry or context switch resets native state", async () => {
  const model = snapshotFixture();
  model.grid = { columns: 6, row_height_px: 64, gap_px: 4 };
  const app = render(model);
  const grid = app.get(".grid-stack").element;
  if (!("gridstack" in grid) || !(grid.gridstack instanceof GridStack))
    throw Error("Expected a mounted grid");
  expect(grid.gridstack.opts.column).toBe(6);
  expect(grid.gridstack.opts.cellHeight).toBe(64);
  expect(grid.gridstack.opts.margin).toBe(4);
  expect(grid.gridstack.opts.staticGrid).toBe(true);
  const changed = structuredClone(model);
  changed.context.realm = "rehearsal";
  await app.setProps({ snapshot: changed });
  expect(app.get(".grid-stack").element).not.toBe(grid);
});
test("unavailable, empty and malformed widget frames remain visible without hiding neighboring data", () => {
  const model = snapshotFixture();
  model.placements.push({
    ...structuredClone(required(model.placements[0])),
    id: "missing",
    status: "unavailable",
    reason: "unsupported_widget",
    widget: null,
    frames: [],
  });
  model.placements.push({
    ...structuredClone(required(model.placements[0])),
    id: "empty",
    frames: [],
  });
  model.placements.push({
    ...structuredClone(required(model.placements[0])),
    id: "ambiguous",
    frames: [
      required(required(model.placements[0]).frames[0]),
      required(required(model.placements[0]).frames[0]),
    ],
  });
  const app = render(model);
  expect(app.findAll(".grid-stack-item")).toHaveLength(4);
  expect(app.get('[data-workspace-value="battery"]').text()).toBe("28.40");
  expect(app.get('[data-workspace-widget-body="missing"]').text()).toContain("Widget unavailable");
  expect(app.get('[data-workspace-widget-body="empty"]').text()).toContain("No data");
  expect(app.get('[data-workspace-widget-body="ambiguous"]').text()).toContain(
    "cannot be displayed",
  );
});
test("null scalar values and absent spacecraft states never become zero or healthy", () => {
  const model = snapshotFixture();
  required(required(required(model.placements[0]).frames[0]).fields[1]).values = [null];
  expect(render(model).get('[data-workspace-value="battery"]').text()).toBe("No data");
  const app = render(snapshotFixture("constellation_health"), "health");
  expect(app.get('[data-spacecraft-id="sc-1"]').attributes("aria-label")).toBe("sc-1: red");
  expect(app.get('[data-spacecraft-id="sc-2"]').attributes("aria-label")).toBe("sc-2: no_data");
});
test("series projection keeps gaps, sorts time, preserves units and separates envelopes from sample counts", () => {
  const f = frame("wide", [
    field("bucket_start", "time", [2000, 1000]),
    field("bucket_end", "time", [3000, 2000]),
    field("voltage_min", "number", [27, 26], "V"),
    field("voltage_max", "number", [30, 29], "V"),
    field("voltage_value", "number", [null, 28.4], "V"),
    field("voltage_sample_count", "number", [4, 5]),
  ]);
  const series = snapshotSeries([f], "battery");
  expect(series).toHaveLength(1);
  expect(required(series[0]).unit).toBe("V");
  expect(required(series[0]).points).toEqual([
    [1000, 28.4],
    [2000, null],
  ]);
  expect(required(series[0]).envelope?.points).toEqual([
    [1000, 26, 29],
    [2000, 27, 30],
  ]);
  const missing = structuredClone(f);
  required(missing.fields[0]).values[0] = null;
  expect(() => snapshotSeries([missing], "battery")).toThrow();
  const duplicate = structuredClone(f);
  required(duplicate.fields[0]).values = [1000, 1000];
  expect(() => snapshotSeries([duplicate], "battery")).toThrow();
});
test("table types, state observations and event interval endpoints reach real components", () => {
  const table = render(snapshotFixture("status_matrix"), "table");
  expect(table.get("table").text()).toContain("connected");
  expect(table.get("table").text()).toContain("stale");
  const state = render(snapshotFixture("state_timeline"), "state");
  expect(state.text()).toContain("2 observations");
  expect(state.text()).toContain("1970-01-01T00:00:02.000Z");
  const events = render(snapshotFixture("event_timeline"), "events");
  expect(events.text()).toContain("Ground station pass");
  expect(events.text()).toContain("Ends: 1970-01-01T00:00:02.000Z");
});
test("DOM and chart synchronization identities are instance-specific and collision-free", () => {
  expect(workspaceDomId("viewer", "a/b")).not.toBe(workspaceDomId("viewer", "a-b"));
  expect(workspaceDomId("viewer", "a", "b")).not.toBe(workspaceDomId("viewer", "a-b"));
  const a = snapshotPresentation(snapshotFixture("time_series"), "first");
  const b = snapshotPresentation(snapshotFixture("time_series"), "second");
  const chart = (p: typeof a) => {
    const content = required(
      required(required(p.groups[0]).grid.widgets[0]).presentation.body.content,
    );
    if (content.component !== "WidgetPoint" || content.presentation.kind !== "time_series")
      throw Error("Expected a time-series widget");
    return content.presentation.chart.props;
  };
  expect(chart(a).correlation_group).not.toBe(chart(b).correlation_group);
  expect(() => snapshotPresentation(snapshotFixture(), "bad id")).toThrow();
  const mixed = snapshotFixture();
  required(mixed.sections[0]).id = "ungrouped";
  required(mixed.placements[0]).section_id = "ungrouped";
  mixed.placements.push({
    ...structuredClone(required(mixed.placements[0])),
    id: "loose",
    section_id: null,
  });
  const groups = snapshotPresentation(mixed, "mixed").groups;
  expect(required(groups[0]).root.attrs.id).not.toBe(required(groups[1]).root.attrs.id);
});
test("snapshot composition refuses foreign resources, never turns domain text into executable markup and hides no warnings", () => {
  const model = snapshotFixture();
  required(required(model.placements[0]).widget).title = '<img src=x onerror="alert(1)">';
  model.warnings = [{ code: "source_unavailable", severity: "error" }];
  const app = render(model);
  expect(app.find("img").exists()).toBe(false);
  expect(app.get("#viewer-warnings").text()).toContain("source unavailable");
  const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
  expect(() =>
    mount(WorkspaceSnapshotCanvas, {
      props: {
        snapshot: model,
        context: { ...snapshotContext, resourceId: "foreign" },
        instanceId: "foreign",
      },
    }),
  ).toThrow("Invalid dashboard workspace snapshot");
  warn.mockRestore();
});
test("read-only snapshot cannot inherit another workspace's action or subscription bridge", () => {
  const execute = vi.fn(),
    subscribe = vi.fn();
  const chartProbe = defineComponent({
    setup() {
      const runtime = useChartRuntime();
      runtime.on("append", () => {});
      onMounted(() => runtime.pushEvent("open_evidence", { kind: "frame" }));
      return () => h("div", { "data-chart-port-probe": "" });
    },
  });
  const app = mount(WorkspaceSnapshotCanvas, {
    props: {
      snapshot: snapshotFixture("time_series"),
      context: snapshotContext,
      instanceId: "isolated",
    },
    global: {
      stubs: { TelemetryChart: chartProbe },
      provide: { [CHART_RUNTIME_PORT as symbol]: { version: 1, execute, subscribe } },
    },
  });
  apps.push(app);
  expect(app.find("[data-chart-port-probe]").exists()).toBe(true);
  expect(execute).not.toHaveBeenCalled();
  expect(subscribe).not.toHaveBeenCalled();
});

test("a static snapshot never advances a live clock or silently combines different time axes", () => {
  const model = snapshotFixture("time_series");
  model.context.time_mode = "live";
  model.context.window_seconds = 600;
  const adapted = required(
    required(snapshotPresentation(model, "static").groups[0]).grid.widgets[0],
  ).presentation.body;
  if (adapted.content?.presentation.kind !== "time_series") throw Error("Missing time series");
  expect(adapted.content.presentation.chart.props.time_mode).toBe("snapshot");
  expect(adapted.content.presentation.chart.props.window_seconds).toBe(600);
  expect(adapted.content.presentation.chart.props).not.toHaveProperty("precision");
  required(model.placements[0]).frames.push({
    ...structuredClone(required(required(model.placements[0]).frames[0])),
    role: "compare",
    time_axis: "receipt_time",
  });
  const invalid = required(
    required(snapshotPresentation(model, "static").groups[0]).grid.widgets[0],
  ).presentation.body;
  expect(invalid.content).toBeNull();
  expect(invalid.notice?.text).toContain("cannot be displayed");
});

test("chart's normalizers preserve explicit gaps and reject null envelope coordinates", () => {
  expect(
    normalizePoints([
      [1000, null],
      [2000, 28.4],
      [null, 5],
      [3000, "7"],
    ]),
  ).toEqual([
    [1000, null, {}],
    [2000, 28.4, {}],
  ]);
  expect(
    normalizeEnvelope({
      points: [
        [1000, null, 5],
        [2000, 3, 2],
      ],
    }),
  ).toBeNull();
  expect(TelemetryChart).toBeDefined();
});
