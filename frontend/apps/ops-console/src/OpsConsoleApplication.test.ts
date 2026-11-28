import { required } from "../../../test-support/required";
import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import type {
  FullPageSurfaceProps,
  HostActionReceipt,
  HostActionRequest,
  HostQueryRequest,
  MissionHostContext,
} from "@cadence/plugin-sdk";
import OpsConsoleApplication from "./OpsConsoleApplication.vue";
import { manifest, routeQueryContracts, surfaceContracts } from "./federated-application";
import { OPS_COMPONENTS, OPS_COMPONENT_NAMES } from "./ops-components";
import { unwrapOpsConsoleResponse } from "./ops-console";

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
    props: {
      model: {
        version: 1,
        context: { organization_id: "org-1", mission_id: "mission-1" },
        mission_name: "Firebird",
        can_administer: false,
      },
    },
  },
};

const expectedSurfaceTable = [
  ["workspace", "overview", "mission", "application_workspace", "cadence.ops.workspace", []],
  [
    "contact_schedule",
    "operations",
    "mission",
    "ops_workspace",
    "cadence.ops.contact_schedule",
    ["validate", "search", "reserve", "cancel"],
  ],
  [
    "contact_plan_show",
    "subject_detail",
    "mission",
    "ops_workspace",
    "cadence.ops.contact_plan_show",
    ["submit-plan", "approve-plan", "reject-plan", "execute-plan"],
  ],
  [
    "contact_detail",
    "subject_detail",
    "mission",
    "ops_workspace",
    "cadence.ops.contact_detail",
    ["approve-provider-change", "reject-provider-change", "acknowledge-provider-change"],
  ],
  [
    "contact_record",
    "subject_detail",
    "mission",
    "ops_workspace",
    "cadence.ops.contact_record",
    [],
  ],
  [
    "fleet_planning",
    "operations",
    "mission",
    "ops_workspace",
    "cadence.ops.fleet_planning",
    ["refresh-planning"],
  ],
  [
    "fleet_planning_new",
    "configuration",
    "mission",
    "ops_workspace",
    "cadence.ops.fleet_planning_new",
    ["validate-fleet-run", "create-fleet-run"],
  ],
  [
    "fleet_planning_run",
    "subject_detail",
    "mission",
    "ops_workspace",
    "cadence.ops.fleet_planning_run",
    ["refresh-fleet-run", "repair-fleet-run"],
  ],
  ["commands", "operations", "mission", "ops_workspace", "cadence.ops.commands", []],
  [
    "data_sources",
    "configuration",
    "mission",
    "ops_workspace",
    "cadence.ops.data_sources",
    [
      "register-source",
      "change-binding",
      "disable-source",
      "enable-source",
      "reconcile-tsdb-backend",
      "deprovision-tsdb-backend",
      "provision-tsdb-backend",
      "probe-source",
      "rotate-source-credential",
      "retry-deployment-run",
      "requeue-deployment-run",
    ],
  ],
  [
    "data_source_registration",
    "configuration",
    "mission",
    "ops_workspace",
    "cadence.ops.data_source_registration",
    ["register-source"],
  ],
  [
    "data_source_settings",
    "configuration",
    "mission",
    "ops_workspace",
    "cadence.ops.data_source_settings",
    [
      "change-binding",
      "disable-source",
      "enable-source",
      "reconcile-tsdb-backend",
      "deprovision-tsdb-backend",
      "provision-tsdb-backend",
      "probe-source",
      "rotate-source-credential",
      "retry-deployment-run",
      "requeue-deployment-run",
    ],
  ],
] as const;

type TestQuery = (request: HostQueryRequest) => Promise<unknown>;
type TestExecute = (request: HostActionRequest<unknown>) => Promise<HostActionReceipt<unknown>>;

function propsFor(query: TestQuery, execute: TestExecute = vi.fn(), surfaceId = "fleet_planning") {
  const surface = required(surfaceContracts.find((candidate) => candidate.surfaceId === surfaceId));
  return {
    application: {
      applicationKey: "ops_console",
      applicationVersion: 1,
      displayName: "Ops Console",
      description: "Mission operations.",
      package: { packageId: "cadence.ops_console", version: 1 },
      surface,
      release: {
        federation: "module_federation" as const,
        releaseId: "ops-console-v1",
        remoteName: "cadence_ops_console",
        manifestUrl: "/assets/application-host/ops-console/mf-manifest.json",
        exposedModule: "./Application",
      },
    },
    surface,
    context,
    bridge: {
      query: async <TResult>(request: HostQueryRequest) => (await query(request)) as TResult,
      execute: async <TInput, TResult>(request: HostActionRequest<TInput>) =>
        (await execute(request as HostActionRequest<unknown>)) as HostActionReceipt<TResult>,
      subscribe: vi.fn(),
    },
  } satisfies FullPageSurfaceProps;
}

describe("Ops Console federated application", () => {
  it("queries the preserved Ops workspace surface and renders its Phoenix DTO", async () => {
    const surface = required(
      surfaceContracts.find((candidate) => candidate.surfaceId === "workspace"),
    );
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const baseProps = propsFor(query);
    const wrapper = mount(OpsConsoleApplication, {
      props: { ...baseProps, surface, application: { ...baseProps.application, surface } },
    });

    expect(wrapper.find("#ops-console-loading").exists()).toBe(true);
    await flushPromises();

    expect(query).toHaveBeenCalledWith({
      queryId: surface.dataContract.id,
      version: surface.dataContract.version,
      context,
    });
    expect(wrapper.find("#ops-console-application").exists()).toBe(true);
    wrapper.unmount();
  });

  it("binds legacy landing responses to host identity and removes links after context changes", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const baseProps = propsFor(query);
    const surface = required(
      surfaceContracts.find((candidate) => candidate.surfaceId === "workspace"),
    );
    const wrapper = mount(OpsConsoleApplication, {
      props: { ...baseProps, surface, application: { ...baseProps.application, surface } },
    });
    await flushPromises();
    expect(wrapper.get("#ops-entry-dashboards").attributes("href")).toBe(
      "/missions/mission-1/ops/dashboards",
    );
    await wrapper.setProps({ context: { ...context, missionId: "mission-2" } });
    expect(wrapper.find("#ops-workspace-landing-unavailable").exists()).toBe(true);
    expect(wrapper.find("#ops-entry-dashboards").exists()).toBe(false);
    wrapper.unmount();
  });

  it("ignores response-supplied host identity when a workspace model belongs to another mission", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue({
      ...response,
      presentation: {
        ...response.presentation,
        props: {
          organizationId: "org-foreign",
          missionId: "mission-foreign",
          model: {
            ...response.presentation.props.model,
            context: { organization_id: "org-foreign", mission_id: "mission-foreign" },
          },
        },
      },
    });
    const baseProps = propsFor(query);
    const surface = required(
      surfaceContracts.find((candidate) => candidate.surfaceId === "workspace"),
    );
    const wrapper = mount(OpsConsoleApplication, {
      props: { ...baseProps, surface, application: { ...baseProps.application, surface } },
    });
    await flushPromises();
    expect(wrapper.find("#ops-workspace-landing-unavailable").exists()).toBe(true);
    expect(wrapper.findAll("#ops-workspace-landing a")).toHaveLength(0);
    wrapper.unmount();
  });

  it("never supplies route params to the host query bridge", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const wrapper = mount(OpsConsoleApplication, { props: propsFor(query) });

    await flushPromises();

    expect(query).toHaveBeenCalledOnce();
    expect(query.mock.calls[0]?.[0]).toEqual({
      queryId: required(
        surfaceContracts.find((candidate) => candidate.surfaceId === "fleet_planning"),
      ).dataContract.id,
      version: required(
        surfaceContracts.find((candidate) => candidate.surfaceId === "fleet_planning"),
      ).dataContract.version,
      context,
    });
    expect(query.mock.calls[0]?.[0]).not.toHaveProperty("params");
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
    expect(wrapper.find("#ops-console-application").exists()).toBe(true);
    wrapper.unmount();
  });

  it("dispatches remote events through the Phoenix-owned action bridge", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const execute = vi.fn<TestExecute>().mockResolvedValue({
      receiptId: "receipt-1",
      completedAt: "2026-09-04T00:00:00.000Z",
      result: {},
    });
    const wrapper = mount(OpsConsoleApplication, {
      props: propsFor(query, execute, "data_sources"),
    });
    await flushPromises();

    window.dispatchEvent(
      new CustomEvent("cadence:ops-event", {
        detail: { eventName: "enable-source", payload: { request_id: "request-1" } },
      }),
    );
    await flushPromises();

    expect(execute).toHaveBeenCalledWith({
      applicationKey: "ops_console",
      applicationVersion: 1,
      surfaceId: "data_sources",
      surfaceVersion: 1,
      actionId: "enable-source",
      input: { request_id: "request-1" },
      context,
    });
    expect(wrapper.find("#ops-console-action-notice").exists()).toBe(true);
    wrapper.unmount();
  });

  it("shows the server receipt and refreshes the Phoenix presentation after completion", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const execute = vi.fn<TestExecute>().mockResolvedValue({
      receiptId: "receipt-complete",
      completedAt: "2026-09-04T00:00:00.000Z",
      result: { status: "completed" },
    });
    const wrapper = mount(OpsConsoleApplication, {
      props: propsFor(query, execute, "data_sources"),
    });
    await flushPromises();

    window.dispatchEvent(
      new CustomEvent("cadence:ops-event", {
        detail: { eventName: "enable-source", payload: { request_id: "request-1" } },
      }),
    );
    await flushPromises();

    expect(query).toHaveBeenCalledTimes(2);
    expect(wrapper.find("#ops-console-action-notice").text()).toContain("completed");
    wrapper.unmount();
  });

  it("forwards a visible action from the federated surface", async () => {
    const query = vi.fn<TestQuery>().mockResolvedValue(response);
    const execute = vi.fn<TestExecute>().mockResolvedValue({
      receiptId: "receipt-layout",
      completedAt: "2026-09-04T00:00:00.000Z",
      result: { status: "completed" },
    });
    const wrapper = mount(OpsConsoleApplication, {
      props: propsFor(query, execute, "data_sources"),
    });
    await flushPromises();

    window.dispatchEvent(
      new CustomEvent("cadence:ops-event", {
        detail: { eventName: "enable-source", payload: { request_id: "request-1" } },
      }),
    );
    await flushPromises();

    expect(execute).toHaveBeenCalledTimes(1);
    expect(wrapper.find("#ops-console-action-notice").exists()).toBe(true);
    wrapper.unmount();
  });

  it("admits native route roots and excludes obsolete widgets and inherited object names", () => {
    const required = [
      "OpsCommands",
      "OpsConsoleLanding",
      "OpsContactDetail",
      "OpsContactPlanShow",
      "OpsContactRecord",
      "OpsContactSchedule",
      "OpsDataSourceRegistration",
      "OpsDataSourceSettings",
      "OpsDataSources",
      "OpsFleetPlanning",
      "OpsFleetPlanningNew",
      "OpsFleetPlanningRun",
    ];
    expect(OPS_COMPONENT_NAMES).toEqual(required);
    for (const component of [
      "OpsDashboardActivity",
      "DashboardCanvas",
      "WidgetForm",
      "HistoricalWorkflowControls",
      "unknown",
      "toString",
      "constructor",
      "__proto__",
    ]) {
      expect(() =>
        unwrapOpsConsoleResponse(
          { queryVersion: 1, presentation: { component, props: {} } },
          OPS_COMPONENTS,
        ),
      ).toThrow("presentation component is invalid");
    }
  });

  it("publishes the exact first-party mission identity", () => {
    expect(manifest.package).toMatchObject({ packageId: "cadence.ops_console", version: 1 });
    expect(manifest.application).toMatchObject({ applicationKey: "ops_console", version: 1 });
    expect(manifest.application.installableScopes).toEqual(["mission"]);
    expect(manifest.surfaces).toEqual(surfaceContracts);
    expect(surfaceContracts).toHaveLength(12);
    expect(new Set(surfaceContracts.map((surface) => surface.surfaceId)).size).toBe(12);
    expect(surfaceContracts.flatMap((surface) => surface.actions)).toHaveLength(38);
    expect(
      new Set(
        surfaceContracts.flatMap((surface) =>
          surface.actions.map((action) => `${surface.surfaceId}:${action}`),
        ),
      ).size,
    ).toBe(38);
    expect(new Set(surfaceContracts.flatMap((surface) => surface.actions)).size).toBe(27);
    expect(
      surfaceContracts.slice(2).every((surface) => {
        const componentName = `Ops${surface.surfaceId.replace(/(^|_)(\w)/g, (_: string, _prefix: string, letter: string) => letter.toUpperCase())}`;
        return Boolean(OPS_COMPONENTS[componentName]);
      }),
    ).toBe(true);
  });

  it("publishes exact deep-route subject and query contracts", () => {
    expect(routeQueryContracts.data_source_registration).toEqual({
      subjectParam: null,
      queryParams: [],
    });

    for (const surfaceId of ["data_source_registration", "data_source_settings"]) {
      const surface = surfaceContracts.find((candidate) => candidate.surfaceId === surfaceId);
      expect(surface?.actions).toBeDefined();
    }
  });

  it("matches the complete Phoenix Ops purpose, scope, placement, query, and action table", () => {
    expect(
      surfaceContracts.map((surface) => [
        surface.surfaceId,
        surface.purpose,
        surface.scope,
        surface.placement,
        surface.dataContract.id,
        [...surface.actions],
      ]),
    ).toEqual(expectedSurfaceTable);
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

  it("accepts the authenticated host response envelope", () => {
    expect(unwrapOpsConsoleResponse({ trusted_surface: response }, OPS_COMPONENTS)).toEqual(
      response.presentation,
    );
  });
});
