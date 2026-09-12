import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import { defineComponent, h, inject } from "vue";
import {
  CHART_RUNTIME_PORT,
  type ChartRuntimePort,
} from "@cadence/dashboards-and-exploration/workspace";
import OpsConsoleApplication from "./OpsConsoleApplication.vue";
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
const captured: ChartRuntimePort[] = [];
vi.mock("./ops-components", () => ({
  OPS_COMPONENTS: {
    ChartProbe: defineComponent({
      setup() {
        captured.push(inject(CHART_RUNTIME_PORT)!);
        return () => h("div", { id: "chart-probe" });
      },
    }),
  },
}));
const apps: ReturnType<typeof mount>[] = [];
afterEach(() => {
  for (const app of apps.splice(0)) app.unmount();
  captured.length = 0;
  vi.restoreAllMocks();
});
function start(mission: string) {
  const execute = vi.fn().mockResolvedValue({
    receiptId: "receipt",
    completedAt: "2026-09-07T00:00:00Z",
    result: { status: "completed" },
  });
  const props = {
    application: { applicationKey: "ops_console", applicationVersion: 1 },
    surface: {
      surfaceId: "dashboard_show",
      actions: ["open_evidence"],
      dataContract: { id: "dashboard", version: 1 },
    },
    context: {
      scope: "mission",
      organizationId: "org",
      missionId: mission,
      queryParams: { dashboard_id: "dashboard-" + mission },
    },
    bridge: {
      query: vi.fn().mockResolvedValue({
        queryVersion: 1,
        presentation: { component: "ChartProbe", props: {} },
      }),
      execute,
    },
  };
  const app = mount(OpsConsoleApplication, { props: props as unknown as FullPageSurfaceProps });
  apps.push(app);
  return { app, execute };
}
test("module chart actions target only their provided Ops instance and undeclared actions never execute", async () => {
  const one = start("one"),
    two = start("two");
  await flushPromises();
  const dispatch = vi.spyOn(window, "dispatchEvent");
  await captured[0].execute("open_evidence", { kind: "frame", "placement-id": "p" });
  await flushPromises();
  expect(one.execute).toHaveBeenCalledOnce();
  expect(two.execute).not.toHaveBeenCalled();
  expect(one.execute.mock.calls[0][0].context.missionId).toBe("one");
  expect(dispatch.mock.calls.some(([e]) => e.type === "cadence:ops-event")).toBe(false);
  await captured[1].execute("set_chart_time_range", { from: 1, to: 2 });
  expect(two.execute).not.toHaveBeenCalled();
});
