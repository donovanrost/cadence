import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import type {
  FederatedApplicationProps,
  HostActionReceipt,
  HostActionRequest,
  HostQueryRequest,
  MissionHostContext,
} from "@cadence/plugin-sdk";
import OpsConsoleApplication from "./OpsConsoleApplication.vue";
import { manifest } from "./federated-application";
import { OPS_COMPONENTS, OPS_COMPONENT_NAMES } from "./ops-components";
import { OPS_QUERY_ID, OPS_QUERY_VERSION, unwrapOpsConsoleResponse } from "./ops-console";

const context: MissionHostContext = {
  scope: "mission",
  organizationId: "org-1",
  missionId: "mission-1",
  missionName: "Firebird",
  spacecraftId: null,
  spacecraftName: null,
  actor: { displayName: "Mara Vance", permissions: ["ops:view"] },
};

const response = {
  queryVersion: 1,
  presentation: {
    component: "OpsConsoleLanding",
    props: { missionId: "mission-1", missionName: "Firebird", componentCount: 90 },
  },
};

type TestQuery = (request: HostQueryRequest) => Promise<unknown>;
type TestExecute = (request: HostActionRequest<unknown>) => Promise<HostActionReceipt<unknown>>;

function propsFor(query: TestQuery, execute: TestExecute = vi.fn()) {
  return {
    context,
    bridge: {
      query: async <TResult>(request: HostQueryRequest) => (await query(request)) as TResult,
      execute: async <TInput, TResult>(request: HostActionRequest<TInput>) =>
        (await execute(request as HostActionRequest<unknown>)) as HostActionReceipt<TResult>,
      subscribe: vi.fn(),
    },
  } satisfies FederatedApplicationProps;
}

describe("Ops Console federated application", () => {
  it("queries Phoenix and renders the server-selected app-local surface", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const wrapper = mount(OpsConsoleApplication, { props: propsFor(query) });

    expect(wrapper.find("#ops-console-loading").exists()).toBe(true);
    await flushPromises();

    expect(query).toHaveBeenCalledWith({
      queryId: OPS_QUERY_ID,
      version: OPS_QUERY_VERSION,
      context,
    });
    expect(wrapper.find("#ops-console-surface").exists()).toBe(true);
    expect(wrapper.text()).toContain("Firebird");
    wrapper.unmount();
  });

  it("contains query failures and retries the same Phoenix-owned contract", async () => {
    const query = vi
      .fn<TestQuery>()
      .mockRejectedValueOnce(new Error("query unavailable"))
      .mockResolvedValueOnce(response);
    const wrapper = mount(OpsConsoleApplication, { props: propsFor(query) });

    await flushPromises();
    expect(wrapper.find("#ops-console-error").text()).toContain("query unavailable");
    await wrapper.get("#retry-ops-console").trigger("click");
    await flushPromises();

    expect(query).toHaveBeenCalledTimes(2);
    expect(wrapper.find("#ops-console-surface").exists()).toBe(true);
    wrapper.unmount();
  });

  it("dispatches remote events through the Phoenix-owned action bridge", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const execute = vi.fn<TestExecute>().mockResolvedValue({
      receiptId: "receipt-1",
      completedAt: "2026-09-04T00:00:00.000Z",
      result: {},
    });
    const wrapper = mount(OpsConsoleApplication, { props: propsFor(query, execute) });
    await flushPromises();

    window.dispatchEvent(
      new CustomEvent("cadence:ops-event", {
        detail: { eventName: "refresh", payload: { reason: "operator" } },
      }),
    );
    await flushPromises();

    expect(execute).toHaveBeenCalledWith({
      applicationKey: "ops_console",
      applicationVersion: 1,
      actionId: "refresh",
      input: { reason: "operator" },
      context,
    });
    expect(wrapper.find("#ops-console-action-notice").exists()).toBe(true);
    wrapper.unmount();
  });

  it("keeps the complete frozen Ops family in the remote component registry", () => {
    const required = [
      "OpsActivationRequests",
      "OpsAlarms",
      "OpsCommands",
      "OpsDashboardDirectory",
      "OpsDashboardNew",
      "OpsDataOperations",
      "OpsDataSources",
      "OpsFleetPlanning",
      "OpsTelemetryExplore",
      "DashboardCanvas",
      "DashboardWidget",
      "HistoricalWorkflowControls",
      "RuntimeDiagnosticsPanel",
      "SourceHealth",
      "SelectedActivityActions",
      "ActivityTimeline",
      "ComparisonReviewActivityDetails",
      "EvidenceInspectorPanel",
      "WidgetForm",
      "TelemetryChart",
    ];

    expect(required.every((name) => Boolean(OPS_COMPONENTS[name]))).toBe(true);
    expect(OPS_COMPONENT_NAMES).toContain("OpsConsoleLanding");
  });

  it("publishes the exact first-party mission identity", () => {
    expect(manifest.package).toMatchObject({ packageId: "cadence.ops_console", version: 1 });
    expect(manifest.application).toMatchObject({ applicationKey: "ops_console", version: 1 });
    expect(manifest.application.installableScopes).toEqual(["mission"]);
    expect(manifest.surfaces).toEqual([
      expect.objectContaining({
        surfaceId: "ops",
        purpose: "operations",
        scope: "mission",
        placement: "ops_workspace",
        dataContract: { id: "cadence.ops.console", version: 1 },
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      }),
    ]);
  });
});

describe("Ops Console response boundary", () => {
  it("rejects an unknown component instead of evaluating server input", () => {
    expect(() =>
      unwrapOpsConsoleResponse(
        {
          queryVersion: 1,
          presentation: { component: "NotAnOpsComponent", props: {} },
        },
        OPS_COMPONENTS,
      ),
    ).toThrow("presentation component is invalid");
  });
});
