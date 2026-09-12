import { expect, test, vi } from "vite-plus/test";
import type {
  FullPageSurfaceProps,
  HostActionReceipt,
  HostActionRequest,
  HostQueryRequest,
} from "@cadence/plugin-sdk";
import { createContactSchedulePort } from "./contact-schedule-port";
import { surfaceContracts } from "./federated-application";

function harness() {
  const surface = surfaceContracts.find((s) => s.surfaceId === "contact_schedule")!;
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

test("the contact scheduling port captures host authority and only delegates declared scheduling actions", async () => {
  const { props, query, execute } = harness();
  const port = createContactSchedulePort(props, () => true)!;
  const input = {
    provider_reservation_id: "plan-one",
    change_evidence: { content_sha256: "a".repeat(64) },
  };
  execute.mockResolvedValue({ receiptId: "completed" });
  await port.execute("reserve", input);
  expect(execute).toHaveBeenCalledExactlyOnceWith({
    applicationKey: "ops_console",
    applicationVersion: 1,
    surfaceId: "contact_schedule",
    surfaceVersion: 1,
    actionId: "reserve",
    input,
    context: props.context,
  });
  expect(port.context).toEqual({ organization_id: "org-one", mission_id: "mission-one" });
  await expect(port.execute("delete-plan" as never, {})).rejects.toThrow("Undeclared");
  expect(execute).toHaveBeenCalledTimes(1);
  query.mockResolvedValue({
    trusted_surface: {
      queryVersion: 1,
      presentation: {
        component: "OpsContactSchedule",
        props: { schedule: { contract_version: 1 } },
      },
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
    resolve!: (value: unknown) => void;
  execute.mockImplementation(
    () =>
      new Promise((done) => {
        resolve = done;
      }),
  );
  const port = createContactSchedulePort(props, () => active)!;
  const pending = port.execute("reserve", {});
  active = false;
  resolve({ receiptId: "late" });
  await expect(pending).rejects.toThrow("departed");
  await expect(port.refresh()).rejects.toThrow("departed");
  await expect(port.execute("cancel", {})).rejects.toThrow("departed");
  expect(query).not.toHaveBeenCalled();
  expect(execute).toHaveBeenCalledTimes(1);
});
