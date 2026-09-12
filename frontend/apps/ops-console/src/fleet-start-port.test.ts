import { required } from "../../../test-support/required";
import { startReviewFixture } from "../../../modules/planning-and-contacts/src/features/fleet-planning/fleet-start.test-support";
import type { FleetStartCommand } from "../../../modules/planning-and-contacts/src/features/fleet-planning/OpsFleetPlanningNew.contracts";
import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import type {
  FullPageSurfaceProps,
  HostActionReceipt,
  HostActionRequest,
  HostQueryRequest,
} from "@cadence/plugin-sdk";
import { createFleetStartPort } from "./fleet-start-port";
import { surfaceContracts } from "./federated-application";
import OpsConsoleApplication from "./OpsConsoleApplication.vue";

function harness() {
  const surface = required(surfaceContracts.find((s) => s.surfaceId === "fleet_planning_new"));
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

test("the creation port performs only the captured declared read", async () => {
  const { props, query, execute } = harness();
  const port = required(createFleetStartPort(props, () => true));
  query.mockResolvedValue({
    trusted_surface: {
      queryVersion: 1,
      presentation: {
        component: "OpsFleetPlanningNew",
        props: { start: { contract_version: 1 } },
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
test("a departed creation port refuses new reads and late responses", async () => {
  const { props, query } = harness();
  let active = true,
    resolve!: (v: unknown) => void;
  query.mockImplementation(
    () =>
      new Promise((done) => {
        resolve = done;
      }),
  );
  const port = required(createFleetStartPort(props, () => active));
  const pending = port.refresh();
  active = false;
  resolve({});
  await expect(pending).rejects.toThrow("departed");
  await expect(port.refresh()).rejects.toThrow("departed");
  expect(query).toHaveBeenCalledTimes(1);
});
test("the port rejects other presentations and other surfaces", async () => {
  const { props, query } = harness();
  const port = required(createFleetStartPort(props, () => true));
  query.mockResolvedValue({
    queryVersion: 1,
    presentation: { component: "OpsContactDetail", props: { start: {} } },
  });
  await expect(port.refresh()).rejects.toThrow("Unavailable");
  expect(
    createFleetStartPort(
      { ...props, surface: { ...props.surface, surfaceId: "contact_detail" } },
      () => true,
    ),
  ).toBeUndefined();
});
test("the mounted host injects creation read recovery through the module entry", async () => {
  const { props, query, execute } = harness();
  query.mockResolvedValue({
    queryVersion: 1,
    presentation: { component: "OpsFleetPlanningNew", props: { start: { contract_version: 2 } } },
  });
  const app = mount(OpsConsoleApplication, { props });
  await flushPromises();
  expect(app.find("#fleet-start-unavailable").exists()).toBe(true);
  await app.get("#fleet-start-retry").trigger("click");
  await flushPromises();
  expect(query).toHaveBeenCalledTimes(2);
  window.dispatchEvent(
    new CustomEvent("cadence:ops-event", {
      detail: { eventName: "create-fleet-run", payload: {} },
    }),
  );
  await flushPromises();
  expect(execute).not.toHaveBeenCalled();
  app.unmount();
});

test("creation and review use only the captured declared actions and reject departure", async () => {
  const { props, execute } = harness();
  let active = true;
  const port = required(createFleetStartPort(props, () => active));
  execute.mockResolvedValue({ receiptId: "captured" });
  const review = startReviewFixture();
  const createInput = { fleet_run: review.window, evidence: review.evidence };
  const commands: FleetStartCommand[] = [
    ["preview", { fleet_run: review.window, requirements_page: 1, templates_page: 1 }],
    ["create", createInput],
  ];
  for (const command of commands) {
    const [action, input] = command;
    const actionId = action === "preview" ? "validate-fleet-run" : "create-fleet-run";
    await port.execute(...command);
    expect(execute).toHaveBeenLastCalledWith({
      applicationKey: "ops_console",
      applicationVersion: 1,
      surfaceId: "fleet_planning_new",
      surfaceVersion: props.surface.version,
      actionId,
      input,
      context: props.context,
    });
  }
  active = false;
  await expect(port.execute("create", createInput)).rejects.toThrow("departed");
  expect(execute).toHaveBeenCalledTimes(2);
  const undeclared = required(
    createFleetStartPort({ ...props, surface: { ...props.surface, actions: [] } }, () => true),
  );
  await expect(undeclared.execute("create", createInput)).rejects.toThrow("Undeclared");
  expect(execute).toHaveBeenCalledTimes(2);
});
