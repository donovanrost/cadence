import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import type {
  FullPageSurfaceProps,
  HostActionReceipt,
  HostActionRequest,
  HostQueryRequest,
} from "@cadence/plugin-sdk";
import { createContactRecordPort } from "./contact-record-port";
import { surfaceContracts } from "./federated-application";
import OpsConsoleApplication from "./OpsConsoleApplication.vue";

function harness() {
  const surface = surfaceContracts.find((s) => s.surfaceId === "contact_record")!;
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

test("the record port performs only the captured declared read", async () => {
  const { props, query, execute } = harness();
  const port = createContactRecordPort(props, () => true)!;
  query.mockResolvedValue({
    trusted_surface: {
      queryVersion: 1,
      presentation: { component: "OpsContactRecord", props: { record: { contract_version: 1 } } },
    },
  });
  expect(await port.refresh()).toEqual({ contract_version: 1 });
  expect(query).toHaveBeenCalledExactlyOnceWith({
    queryId: props.surface.dataContract.id,
    version: props.surface.dataContract.version,
    context: props.context,
  });
  expect("execute" in port).toBe(false);
  expect(execute).not.toHaveBeenCalled();
});
test("a departed record port refuses new reads and late responses", async () => {
  const { props, query } = harness();
  let active = true,
    resolve!: (v: unknown) => void;
  query.mockImplementation(
    () =>
      new Promise((done) => {
        resolve = done;
      }),
  );
  const port = createContactRecordPort(props, () => active)!;
  const pending = port.refresh();
  active = false;
  resolve({});
  await expect(pending).rejects.toThrow("departed");
  await expect(port.refresh()).rejects.toThrow("departed");
  expect(query).toHaveBeenCalledTimes(1);
});
test("the port rejects other presentations and other surfaces", async () => {
  const { props, query } = harness();
  const port = createContactRecordPort(props, () => true)!;
  query.mockResolvedValue({
    queryVersion: 1,
    presentation: { component: "OpsContactDetail", props: { record: {} } },
  });
  await expect(port.refresh()).rejects.toThrow("Unavailable");
  expect(
    createContactRecordPort(
      { ...props, surface: { ...props.surface, surfaceId: "contact_detail" } },
      () => true,
    ),
  ).toBeUndefined();
});
test("the mounted host injects record read recovery through the module entry", async () => {
  const { props, query, execute } = harness();
  query.mockResolvedValue({
    queryVersion: 1,
    presentation: { component: "OpsContactRecord", props: { record: { contract_version: 2 } } },
  });
  const app = mount(OpsConsoleApplication, { props });
  await flushPromises();
  expect(app.find("#contact-record-unavailable").exists()).toBe(true);
  await app.get("#contact-record-retry").trigger("click");
  await flushPromises();
  expect(query).toHaveBeenCalledTimes(2);
  expect(execute).not.toHaveBeenCalled();
  app.unmount();
});
