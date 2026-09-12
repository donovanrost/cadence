import type { PlanInputs } from "@cadence/planning-and-contacts/contact-plans";
import { required } from "../../../test-support/required";
import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import type {
  FullPageSurfaceProps,
  HostActionReceipt,
  HostActionRequest,
  HostQueryRequest,
} from "@cadence/plugin-sdk";
import { createPlanDetailPort } from "./plan-detail-port";
import { surfaceContracts } from "./federated-application";
import OpsConsoleApplication from "./OpsConsoleApplication.vue";

const reference = {
  contact_plan_id: "plan-one",
  plan_evidence: {
    contract_version: 1,
    organization_id: "org-one",
    mission_id: "mission-one",
    plan_id: "plan-one",
    plan_version: 1,
    content_sha256: "a".repeat(64),
  },
} satisfies PlanInputs["execute-plan"];
function harness() {
  const surface = required(surfaceContracts.find((s) => s.surfaceId === "contact_plan_show"));
  const query = vi.fn<(request: HostQueryRequest) => Promise<unknown>>();
  const execute = vi.fn<(request: HostActionRequest<unknown>) => Promise<unknown>>();
  const props: FullPageSurfaceProps = {
    application: {
      applicationKey: "ops_console",
      applicationVersion: 1,
      displayName: "Ops Console",
      description: "Mission operations",
      package: { packageId: "cadence.ops_console", version: 1 },
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
      organizationId: "org-one",
      missionId: "mission-one",
      missionName: "Mission",
      spacecraftId: null,
      spacecraftName: null,
      actor: { displayName: "Operator", permissions: [] },
    },
    bridge: {
      query: async <T>(request: HostQueryRequest) => (await query(request)) as T,
      execute: async <I, R>(request: HostActionRequest<I>) =>
        (await execute(request)) as HostActionReceipt<R>,
      subscribe: vi.fn(),
    },
  };
  return { props, query, execute };
}

test("the plan port captures host authority and only delegates declared plan decisions", async () => {
  const { props, query, execute } = harness();
  const port = required(createPlanDetailPort(props, () => true));
  const input = { ...reference, decision: { reason: "Reviewed selection" } };
  execute.mockResolvedValue({ receiptId: "completed" });
  await port.execute("approve-plan", input);
  expect(execute).toHaveBeenCalledExactlyOnceWith({
    applicationKey: "ops_console",
    applicationVersion: 1,
    surfaceId: "contact_plan_show",
    surfaceVersion: 1,
    actionId: "approve-plan",
    input,
    context: props.context,
  });
  expect(port.context).toEqual({ organization_id: "org-one", mission_id: "mission-one" });
  // @ts-expect-error Probe the runtime guard for an undeclared action.
  await expect(port.execute("delete-plan", reference)).rejects.toThrow("Undeclared");
  expect(execute).toHaveBeenCalledTimes(1);
  query.mockResolvedValue({
    trusted_surface: {
      queryVersion: 1,
      presentation: { component: "OpsContactPlanShow", props: { detail: { contract_version: 1 } } },
    },
  });
  expect(await port.refresh()).toEqual({ contract_version: 1 });
  expect(query).toHaveBeenCalledExactlyOnceWith({
    queryId: props.surface.dataContract.id,
    version: props.surface.dataContract.version,
    context: props.context,
  });
});

test("departed authority refuses new operations and drops late responses", async () => {
  const { props, query, execute } = harness();
  let active = true,
    resolve: ((value: unknown) => void) | undefined;
  execute.mockImplementation(
    () =>
      new Promise((done) => {
        resolve = done;
      }),
  );
  const port = required(createPlanDetailPort(props, () => active));
  const pending = port.execute("submit-plan", {
    ...reference,
    submission: { reason: "Reviewed selection" },
  });
  active = false;
  required(resolve)({ receiptId: "late" });
  await expect(pending).rejects.toThrow("departed");
  await expect(port.refresh()).rejects.toThrow("departed");
  await expect(port.execute("execute-plan", reference)).rejects.toThrow("departed");
  expect(query).not.toHaveBeenCalled();
  expect(execute).toHaveBeenCalledTimes(1);
});

test("the read adapter rejects other presentations and does not exist outside its surface", async () => {
  const { props, query } = harness();
  const port = required(createPlanDetailPort(props, () => true));
  query.mockResolvedValue({
    queryVersion: 1,
    presentation: { component: "OpsContactRequirementShow", props: { detail: {} } },
  });
  await expect(port.refresh()).rejects.toThrow("Unavailable");
  expect(
    createPlanDetailPort(
      { ...props, surface: { ...props.surface, surfaceId: "fleet_planning" } },
      () => true,
    ),
  ).toBeUndefined();
});

test("the mounted delivery application provides the plan port without requiring feature events", async () => {
  const { props, query } = harness();
  // A rejected model still exposes the feature-owned read retry through the injected port.
  query.mockResolvedValue({
    queryVersion: 1,
    presentation: { component: "OpsContactPlanShow", props: { detail: { contract_version: 2 } } },
  });
  const app = mount(OpsConsoleApplication, { props });
  await flushPromises();
  expect(app.find("#plan-detail-unavailable").exists()).toBe(true);
  await app.get("#retry-plan-review").trigger("click");
  await flushPromises();
  expect(query).toHaveBeenCalledTimes(2);
  app.unmount();
});
