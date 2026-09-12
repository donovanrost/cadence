import { required } from "../../../test-support/required";
import { repairFixture } from "../../../modules/planning-and-contacts/src/features/fleet-planning/fleet-run.test-support";
import type { FleetRunCommand } from "../../../modules/planning-and-contacts/src/features/fleet-planning/OpsFleetPlanningRun.contracts";
import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import type {
  FullPageSurfaceProps,
  HostActionReceipt,
  HostActionRequest,
  HostQueryRequest,
} from "@cadence/plugin-sdk";
import { createFleetRunPort } from "./fleet-run-port";
import { surfaceContracts } from "./federated-application";
import OpsConsoleApplication from "./OpsConsoleApplication.vue";

function harness() {
  const surface = required(surfaceContracts.find((s) => s.surfaceId === "fleet_planning_run"));
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

test("the run port performs only the captured declared read", async () => {
  const { props, query, execute } = harness();
  const port = required(createFleetRunPort(props, () => true));
  query.mockResolvedValue({
    trusted_surface: {
      queryVersion: 1,
      presentation: {
        component: "OpsFleetPlanningRun",
        props: { run: { contract_version: 1 } },
      },
    },
  });
  expect(await port.refresh()).toEqual({ contract_version: 1 });
  expect(query).toHaveBeenCalledExactlyOnceWith({
    queryId: props.surface.dataContract.id,
    version: props.surface.dataContract.version,
    context: props.context,
  });
  expect(typeof port.execute).toBe("function");
  expect(execute).not.toHaveBeenCalled();
});
test("a departed run port refuses new reads and late responses", async () => {
  const { props, query } = harness();
  let active = true,
    resolve!: (v: unknown) => void;
  query.mockImplementation(
    () =>
      new Promise((done) => {
        resolve = done;
      }),
  );
  const port = required(createFleetRunPort(props, () => active));
  const pending = port.refresh();
  active = false;
  resolve({});
  await expect(pending).rejects.toThrow("departed");
  await expect(port.refresh()).rejects.toThrow("departed");
  expect(query).toHaveBeenCalledTimes(1);
});
test("the port rejects other presentations and other surfaces", async () => {
  const { props, query } = harness();
  const port = required(createFleetRunPort(props, () => true));
  query.mockResolvedValue({
    queryVersion: 1,
    presentation: { component: "OpsContactDetail", props: { run: {} } },
  });
  await expect(port.refresh()).rejects.toThrow("Unavailable");
  expect(
    createFleetRunPort(
      { ...props, surface: { ...props.surface, surfaceId: "contact_detail" } },
      () => true,
    ),
  ).toBeUndefined();
});
test("the mounted host injects run read recovery through the module entry", async () => {
  const { props, query, execute } = harness();
  query.mockResolvedValue({
    queryVersion: 1,
    presentation: { component: "OpsFleetPlanningRun", props: { run: { contract_version: 2 } } },
  });
  const app = mount(OpsConsoleApplication, { props });
  await flushPromises();
  expect(app.find("#fleet-run-unavailable").exists()).toBe(true);
  await app.get("#fleet-run-retry").trigger("click");
  await flushPromises();
  expect(query).toHaveBeenCalledTimes(2);
  window.dispatchEvent(
    new CustomEvent("cadence:ops-event", {
      detail: { eventName: "repair-fleet-run", payload: {} },
    }),
  );
  await flushPromises();
  expect(execute).not.toHaveBeenCalled();
  app.unmount();
});

test("run and review use only the captured declared actions and reject departure", async () => {
  const { props, execute } = harness();
  let active = true;
  const port = required(createFleetRunPort(props, () => active));
  execute.mockResolvedValue({ receiptId: "captured" });
  const model = repairFixture();
  const repairInput = {
    fleet_planning_run_id: model.id,
    evidence: model.repair.evidence,
    repair: model.repair.defaults,
  };
  const commands: FleetRunCommand[] = [
    ["continue", { fleet_planning_run_id: model.id, evidence: model.evidence }],
    ["repair", repairInput],
  ];
  for (const command of commands) {
    const [action, input] = command;
    const actionId = action === "continue" ? "refresh-fleet-run" : "repair-fleet-run";
    await port.execute(...command);
    expect(execute).toHaveBeenLastCalledWith({
      applicationKey: "ops_console",
      applicationVersion: 1,
      surfaceId: "fleet_planning_run",
      surfaceVersion: props.surface.version,
      actionId,
      input,
      context: props.context,
    });
  }
  active = false;
  await expect(port.execute("repair", repairInput)).rejects.toThrow("departed");
  expect(execute).toHaveBeenCalledTimes(2);
  const undeclared = required(
    createFleetRunPort({ ...props, surface: { ...props.surface, actions: [] } }, () => true),
  );
  await expect(undeclared.execute("repair", repairInput)).rejects.toThrow("Undeclared");
  expect(execute).toHaveBeenCalledTimes(2);
});
