import { required } from "../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import { defineComponent, h } from "vue";
import {
  CHART_RUNTIME_PORT,
  useChartRuntime,
  type ChartRuntimePort,
  type ChartTopic,
} from "./chart-runtime";
const mounted: { unmount: () => void }[] = [];
afterEach(() => {
  for (const app of mounted.splice(0)) app.unmount();
  vi.restoreAllMocks();
});
function transport() {
  const callbacks = new Map<ChartTopic, (p: Record<string, unknown>) => void>();
  const execute = vi.fn(),
    stop = vi.fn();
  const port: ChartRuntimePort = {
    version: 1,
    execute,
    subscribe(topic, listener) {
      callbacks.set(topic, listener);
      return () => {
        callbacks.delete(topic);
        stop();
      };
    },
  };
  return { port, callbacks, execute, stop };
}
function probe(port?: ChartRuntimePort) {
  let runtime: ReturnType<typeof useChartRuntime> | undefined;
  const received = vi.fn();
  const Component = defineComponent({
    setup() {
      runtime = useChartRuntime();
      runtime.on("append", received);
      runtime.on("selection", received);
      return () => h("div");
    },
  });
  const app = mount(Component, {
    global: { provide: port ? { [CHART_RUNTIME_PORT as symbol]: port } : {} },
  });
  mounted.push(app);
  return { app, runtime: required(runtime), received };
}
test("ports isolate workspace instances, restrict actions and unsubscribe on unmount", () => {
  const one = transport(),
    two = transport(),
    a = probe(one.port),
    b = probe(two.port);
  const late = required(one.callbacks.get("append"));
  required(one.callbacks.get("append"))({ series: { battery: [] } });
  expect(a.received).toHaveBeenCalledOnce();
  expect(b.received).not.toHaveBeenCalled();
  a.runtime.pushEvent("open_evidence", { kind: "frame" });
  expect(one.execute).toHaveBeenCalledWith("open_evidence", { kind: "frame" });
  expect(two.execute).not.toHaveBeenCalled();
  a.runtime.pushEvent("arbitrary" as never, {});
  expect(one.execute).toHaveBeenCalledOnce();
  a.app.unmount();
  late({ series: {} });
  a.runtime.pushEvent("open_evidence", {});
  expect(one.stop).toHaveBeenCalledTimes(2);
  expect(a.received).toHaveBeenCalledOnce();
  expect(one.execute).toHaveBeenCalledOnce();
});
test("missing or unsupported ports never fall back to browser events", () => {
  const dispatch = vi.spyOn(window, "dispatchEvent"),
    subscribe = vi.fn();
  const a = probe(),
    b = probe({ version: 2, execute: vi.fn(), subscribe } as never);
  a.runtime.pushEvent("open_evidence", {});
  b.runtime.pushEvent("open_evidence", {});
  expect(dispatch).not.toHaveBeenCalled();
  expect(subscribe).not.toHaveBeenCalled();
});
test("malformed messages are ignored and failed outbound operations are not retried", async () => {
  const one = transport(),
    a = probe(one.port);
  required(one.callbacks.get("append"))(null as never);
  expect(a.received).not.toHaveBeenCalled();
  one.execute.mockRejectedValue(new Error("offline"));
  a.runtime.pushEvent("set_chart_time_range", { from: 1, to: 2 });
  await Promise.resolve();
  await Promise.resolve();
  expect(one.execute).toHaveBeenCalledOnce();
});
