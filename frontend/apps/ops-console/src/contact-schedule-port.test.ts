import { required } from "../../../test-support/required";
import { expect, test, vi } from "vite-plus/test";
import type {
  FullPageSurfaceProps,
  HostActionReceipt,
  HostActionRequest,
  HostQueryRequest,
} from "@cadence/plugin-sdk";
import { createContactSchedulePort } from "./contact-schedule-port";
import {
  scheduleFixture,
  searchFixture,
} from "../../../modules/planning-and-contacts/src/features/contact-scheduling/contact-schedule.test-support";
import { surfaceContracts } from "./federated-application";

function harness() {
  const surface = required(surfaceContracts.find((s) => s.surfaceId === "contact_schedule"));
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

const operationId = "11111111-1111-4111-8111-111111111111";
function accepted() {
  return {
    contract_version: 2,
    operation_id: operationId,
    action: "reserve",
    actor_id: "operator-one",
    context: scheduleFixture().context,
    reservation_id: "reservation-one",
    status: "accepted",
    revision: 1,
    result: null,
  };
}

test("the federated adapter admits the same search, operation and observation contract as native scheduling", async () => {
  const { props, query, execute } = harness();
  const port = required(createContactSchedulePort(props, () => true));
  const model = scheduleFixture();
  port.admit(model);
  const input = { token: "opaque-opportunity-token" };
  execute.mockResolvedValue({ receiptId: "receipt", result: accepted() });
  expect(await port.submit({ operationId, action: "reserve", input })).toEqual(accepted());
  expect(execute).toHaveBeenCalledExactlyOnceWith({
    applicationKey: "ops_console",
    applicationVersion: 1,
    surfaceId: "contact_schedule",
    surfaceVersion: 1,
    actionId: "reserve",
    input: { contract_version: 2, operation_id: operationId, payload: input },
    context: props.context,
  });
  execute.mockResolvedValueOnce({ receiptId: "observation", result: { operation: accepted() } });
  expect(await port.observe({ operationId, action: "reserve" })).toEqual(accepted());
  const found = searchFixture(model);
  execute.mockResolvedValueOnce({ receiptId: "search", result: found });
  expect(
    await port.search(
      { contact_search: found.search, route_evidence: found.route.evidence },
      found.route,
    ),
  ).toEqual(found);
  query.mockResolvedValue({
    trusted_surface: {
      queryVersion: 1,
      presentation: { component: "OpsContactSchedule", props: { schedule: model } },
    },
  });
  expect((await port.read()).model).toEqual(model);
  expect(query).toHaveBeenCalledOnce();
  props.surface = { ...props.surface, actions: [] };
  const unavailable = required(createContactSchedulePort(props, () => true));
  unavailable.admit(model);
  await expect(unavailable.submit({ operationId, action: "reserve", input })).rejects.toThrow(
    "Undeclared",
  );
});

test("departed authority refuses new operations and drops late responses", async () => {
  const { props, query, execute } = harness();
  let active = true;
  let resolve: ((value: unknown) => void) | undefined;
  execute.mockImplementation(
    () =>
      new Promise((done) => {
        resolve = done;
      }),
  );
  const port = required(createContactSchedulePort(props, () => active));
  port.admit(scheduleFixture());
  const command = { operationId, action: "reserve" as const, input: { token: "opaque-token" } };
  const pending = port.submit(command);
  active = false;
  required(resolve)({ receiptId: "late", result: accepted() });
  await expect(pending).rejects.toThrow("departed");
  await expect(port.read()).rejects.toThrow("departed");
  await expect(port.submit(command)).rejects.toThrow("departed");
  expect(query).not.toHaveBeenCalled();
  expect(execute).toHaveBeenCalledOnce();
});
