import { required } from "../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import { defineComponent, h, inject } from "vue";
import {
  CHART_RUNTIME_PORT,
  type ChartRuntimePort,
} from "@cadence/dashboards-and-exploration/workspace";
import OpsConsoleApplication from "./OpsConsoleApplication.vue";
import { manifest, surfaceContracts } from "./federated-application";
import type {
  FullPageSurfaceProps,
  HostActionRequest,
  HostActionReceipt,
} from "@cadence/plugin-sdk";
const captured: ChartRuntimePort[] = [];
vi.mock("./ops-components", () => ({
  OPS_COMPONENTS: {
    ChartProbe: defineComponent({
      setup() {
        captured.push(required(inject(CHART_RUNTIME_PORT)));
        return () => h("div", { id: "chart-probe" });
      },
    }),
  },
}));
const apps: { unmount: () => void }[] = [];
afterEach(() => {
  for (const app of apps.splice(0)) app.unmount();
  captured.length = 0;
  vi.restoreAllMocks();
});
function start(mission: string) {
  const execute = vi
    .fn<(request: HostActionRequest<unknown>) => Promise<unknown>>()
    .mockResolvedValue({
      receiptId: "receipt",
      completedAt: "2026-09-07T00:00:00Z",
      result: { status: "completed" },
    });
  const surface = {
    ...required(surfaceContracts.find((s) => s.surfaceId === "dashboard_show")),
    actions: ["open_evidence"],
  };
  const props: FullPageSurfaceProps = {
    application: {
      applicationKey: manifest.application.applicationKey,
      applicationVersion: manifest.application.version,
      displayName: manifest.application.displayName,
      description: manifest.application.description,
      package: manifest.package,
      surface,
      release: {
        federation: "module_federation",
        releaseId: "ops-console-v1",
        remoteName: "cadence_ops_console",
        manifestUrl: "/assets/ops-console/mf-manifest.json",
        exposedModule: "./Application",
      },
    },
    surface,
    context: {
      scope: "mission",
      organizationId: "org",
      missionId: mission,
      missionName: mission,
      spacecraftId: null,
      spacecraftName: null,
      actor: { displayName: "Operator", permissions: [] },
    },
    bridge: {
      query: async <T>() =>
        ({
          queryVersion: 1,
          presentation: { component: "ChartProbe", props: {} },
        }) as T,
      execute: async <I, R>(request: HostActionRequest<I>) =>
        (await execute(request)) as HostActionReceipt<R>,
      subscribe: () => () => {},
    },
  };
  const app = mount(OpsConsoleApplication, { props });
  apps.push(app);
  return { app, execute };
}
test("module chart actions target only their provided Ops instance and undeclared actions never execute", async () => {
  const one = start("one"),
    two = start("two");
  await flushPromises();
  const dispatch = vi.spyOn(window, "dispatchEvent");
  await required(captured[0]).execute("open_evidence", { kind: "frame", "placement-id": "p" });
  await flushPromises();
  expect(one.execute).toHaveBeenCalledOnce();
  expect(two.execute).not.toHaveBeenCalled();
  expect(required(one.execute.mock.calls[0])[0].context.missionId).toBe("one");
  expect(dispatch.mock.calls.some(([e]) => e.type === "cadence:ops-event")).toBe(false);
  await required(captured[1]).execute("set_chart_time_range", { from: 1, to: 2 });
  expect(two.execute).not.toHaveBeenCalled();
});
