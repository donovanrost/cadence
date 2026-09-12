import type uPlot from "uplot";
import { afterEach, beforeEach, expect, test, vi } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import TelemetryChart from "./TelemetryChart.vue";
import { CHART_RUNTIME_PORT, type ChartRuntimePort, type ChartTopic } from "./chart-runtime";
import { required } from "../../../../../test-support/required";

type PlotProbe = {
  data: uPlot.AlignedData;
  over: HTMLDivElement;
  select: uPlot.Select;
  destroy: ReturnType<typeof vi.fn>;
  setSize: ReturnType<typeof vi.fn>;
};
const probes = vi.hoisted(() => {
  const plots: PlotProbe[] = [];
  return { plots };
});
vi.mock("uplot", () => ({
  default: class {
    static pxRatio = 1;
    over = document.createElement("div");
    bbox = { left: 0, top: 0, width: 300, height: 120 };
    scales = { x: { min: 0, max: 1_000_000 } };
    cursor = { idx: 0, left: 20, top: 20 };
    select = { left: 0, width: 0, top: 0, height: 0 };
    destroy = vi.fn(() => this.over.remove());
    setSize = vi.fn();
    constructor(
      _options: uPlot.Options,
      public data: uPlot.AlignedData,
      element: HTMLElement,
    ) {
      this.over.className = "u-over";
      element.append(this.over);
      probes.plots.push(this);
    }
    setData(data: uPlot.AlignedData) {
      this.data = data;
    }
    valToPos(value: number) {
      return value;
    }
    posToVal(value: number) {
      return value;
    }
    posToIdx() {
      return 0;
    }
    setSelect(selection: uPlot.Select) {
      this.select = selection;
    }
    setCursor() {}
  },
}));
const resize: { notify: () => void; disconnect: ReturnType<typeof vi.fn> }[] = [];
const themes: { notify: () => void; disconnect: ReturnType<typeof vi.fn> }[] = [];
let app: Pick<ReturnType<typeof mount>, "attributes" | "find" | "unmount"> | undefined;
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(120_000);
  vi.stubGlobal(
    "ResizeObserver",
    class implements ResizeObserver {
      disconnect = vi.fn();
      constructor(callback: ResizeObserverCallback) {
        resize.push({ notify: () => callback([], this), disconnect: this.disconnect });
      }
      observe() {}
      unobserve() {}
    },
  );
  vi.stubGlobal(
    "MutationObserver",
    class implements MutationObserver {
      disconnect = vi.fn();
      constructor(callback: MutationCallback) {
        themes.push({ notify: () => callback([], this), disconnect: this.disconnect });
      }
      observe() {}
      takeRecords() {
        return [];
      }
    },
  );
  vi.stubGlobal("getComputedStyle", () => ({
    color: "rgba(1, 2, 3, 1)",
    getPropertyValue: () => "rgba(1, 2, 3, 1)",
  }));
});
afterEach(() => {
  app?.unmount();
  app = undefined;
  probes.plots.length = 0;
  resize.length = 0;
  themes.length = 0;
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  vi.useRealTimers();
});
function start() {
  const listeners = new Map<ChartTopic, (payload: Record<string, unknown>) => void>();
  const execute = vi.fn();
  const stop = vi.fn();
  const port: ChartRuntimePort = {
    version: 1,
    execute,
    subscribe(topic, listener) {
      listeners.set(topic, listener);
      return () => {
        listeners.delete(topic);
        stop();
      };
    },
  };
  app = mount(TelemetryChart, {
    props: {
      chart_id: "chart",
      widget_id: "battery",
      placement_id: "p",
      correlation_group: "power",
      window_seconds: 60,
      time_mode: "live",
      backfill: [
        [50_000, 1],
        [100_000, 2, { link_id: "sample-link", sample_id: "sample" }],
      ],
    },
    global: { provide: { [CHART_RUNTIME_PORT as symbol]: port } },
    attachTo: document.body,
  });
  return { app, listeners, execute, stop };
}
test("mounted chart appends, trims, updates markers and follows selected evidence", () => {
  const { app, listeners } = start();
  required(listeners.get("append"))({
    series: { battery: [[120_000, 3]] },
    markers: {
      p: {
        event_markers: [
          {
            marker_id: "mission",
            link_id: "mission-link",
            marker_type: "mission_event",
            mission_event_id: "event",
            timestamp_ms: 120_000,
          },
        ],
      },
    },
    window_end_ms: 120_000,
    refresh_interval_ms: 1_000,
  });
  expect(required(probes.plots.at(-1)).data).toEqual([
    [100, 120],
    [2, 3],
  ]);
  expect(app.attributes("data-chart-point-count")).toBe("2");
  expect(app.find('[data-event-marker-target="mission event"]').exists()).toBe(true);
  required(listeners.get("selection"))({
    selection: {
      placement_id: "p",
      target: "telemetry_sample",
      link_id: "sample-link",
      target_id: "sample",
      timestamp_ms: 100_000,
    },
  });
  expect(app.find('[data-chart-selection-target="telemetry sample"]').exists()).toBe(true);
  required(listeners.get("selection"))({ selection: null });
  expect(app.find('[data-chart-selection-target="telemetry sample"]').exists()).toBe(false);
});
test("range actions retain timestamps, and unmount removes subscriptions, timers, listeners and plot", async () => {
  const { app, listeners, execute, stop } = start();
  const append = required(listeners.get("append"));
  append({
    series: { battery: [[121_000, 3]] },
    window_end_ms: 121_000,
    refresh_interval_ms: 1_000,
  });
  const plot = required(probes.plots.at(-1));
  plot.select = { left: 100, width: 20, top: 0, height: 100 };
  plot.over.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
  expect(execute).toHaveBeenCalledWith("set_chart_time_range", {
    from: "1970-01-01T00:01:40.000Z",
    to: "1970-01-01T00:02:00.000Z",
  });
  app.unmount();
  expect(stop).toHaveBeenCalledTimes(2);
  expect(required(resize[0]).disconnect).toHaveBeenCalledOnce();
  expect(required(themes.at(-1)).disconnect).toHaveBeenCalledOnce();
  expect(plot.destroy).toHaveBeenCalledOnce();
  expect(vi.getTimerCount()).toBe(0);
  append({ series: { battery: [[125_000, 4]] }, window_end_ms: 125_000 });
  plot.select = { left: 100, width: 20, top: 0, height: 100 };
  plot.over.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
  await vi.advanceTimersByTimeAsync(10_000);
  expect(execute).toHaveBeenCalledOnce();
  expect(plot.data).toEqual([
    [100, 121],
    [2, 3],
  ]);
});
test("theme rebuild replaces the plot and range listener while preserving samples and selection", () => {
  const { app, listeners, execute } = start();
  required(listeners.get("selection"))({
    selection: {
      placement_id: "p",
      target: "telemetry_sample",
      link_id: "sample-link",
      timestamp_ms: 100_000,
    },
  });
  const old = required(probes.plots.at(-1));
  required(themes.at(-1)).notify();
  const current = required(probes.plots.at(-1));
  expect(current).not.toBe(old);
  expect(old.destroy).toHaveBeenCalledOnce();
  expect(current.data).toEqual(old.data);
  expect(app.find('[data-chart-selection-target="telemetry sample"]').exists()).toBe(true);
  old.select = { left: 1, width: 20, top: 0, height: 100 };
  old.over.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
  expect(execute).not.toHaveBeenCalled();
  required(resize[0]).notify();
  expect(current.setSize).toHaveBeenCalledOnce();
  app.unmount();
  required(themes.at(-1)).notify();
  required(resize[0]).notify();
  expect(probes.plots).toHaveLength(2);
});
