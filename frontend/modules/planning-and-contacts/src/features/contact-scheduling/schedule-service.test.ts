import { describe, expect, test, vi } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import { reactive, nextTick } from "vue";
import { required } from "../../../../../test-support/required";
import { scheduleFixture, searchFixture, receiptFixture } from "./contact-schedule.test-support";
import { contactPage } from "./contact-workflow.test-support";
import {
  createContactScheduleService,
  readScheduleOperation,
  type ScheduleOperation,
  type ScheduleWireRequest,
} from "./schedule-service";
import { createPageScheduleService } from "./schedule-page-adapter";
import { recordOperation } from "./schedule-transitions";
import OpsContactSchedule from "./OpsContactSchedule.vue";

export function operationFixture(
  id: string,
  action: "reserve" | "cancel" = "reserve",
): ScheduleOperation {
  return {
    contract_version: 2,
    operation_id: id,
    actor_id: "operator-one",
    context: scheduleFixture().context,
    action,
    reservation_id: "reservation-one",
    revision: 1,
    status: "accepted",
    result: null,
  };
}
const id = "11111111-1111-4111-8111-111111111111";
function deferred<T>() {
  let resolve: ((value: T) => void) | undefined;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve: (value: T) => required(resolve)(value) };
}
function harness(native = false) {
  const model = scheduleFixture();
  const read = vi.fn<() => Promise<unknown>>().mockResolvedValue(model);
  const execute = vi.fn<(...request: ScheduleWireRequest) => Promise<unknown>>(
    async (...request) => {
      if (request[0] === "search") return searchFixture(model, request[1].payload.contact_search);
      if ("observe" in request[1])
        return { operation: operationFixture(request[1].operation_id, request[0]) };
      return operationFixture(request[1].operation_id, request[0]);
    },
  );
  let active = true;
  const port = native
    ? createPageScheduleService(
        { ...contactPage(), model },
        {
          navigate: vi.fn(),
          execute: rawExecute,
        },
        { read: async () => ({ ...contactPage(), model: await read() }) },
        () => active,
      )
    : createContactScheduleService({ read, execute }, model.context);
  function rawExecute(action: string, input: Record<string, unknown>): Promise<unknown> {
    if (action === "search") return Promise.resolve(searchFixture(model));
    if ((action === "reserve" || action === "cancel") && typeof input.operation_id === "string") {
      const op = operationFixture(input.operation_id, action);
      return Promise.resolve(input.observe ? { operation: op } : op);
    }
    return Promise.reject(Error("Invalid test request"));
  }
  const wrapper = mount(OpsContactSchedule, { props: { schedule: model, port } });
  return {
    model,
    read,
    execute,
    port,
    wrapper,
    depart: () => {
      active = false;
      wrapper.unmount();
    },
  };
}

describe.each([false, true])("scheduling service conformance (native=%s)", (native) => {
  test("search, accept, observe and read use one admitted contract", async () => {
    const h = harness(native);
    try {
      const projection = h.port.admit(h.model);
      expect(projection.actorId).toBe("operator-one");
      const route = required(projection.model.routes.entries[0]);
      const found = searchFixture(h.model);
      expect(
        await h.port.search(
          { contact_search: found.search, route_evidence: route.evidence },
          route,
        ),
      ).toEqual(found);
      const op = await h.port.submit({
        operationId: id,
        action: "reserve",
        input: { token: required(found.opportunities[0]).token },
      });
      expect(op.status).toBe("accepted");
      expect(await h.port.observe({ operationId: id, action: "reserve" })).toEqual(op);
      expect((await h.port.read()).model).toEqual(h.model);
    } finally {
      h.depart();
    }
  });
});

test("operation admission rejects cross-scope identities, invalid states and forged cancellation outcomes", () => {
  const op = operationFixture(id);
  for (const bad of [
    { ...op, actor_id: "foreign" },
    { ...op, context: { ...op.context, mission_id: "foreign" } },
    { ...op, contract_version: 3 },
    { ...op, status: "completed" },
    { ...op, action: "cancel", status: "completed", result: receiptFixture() },
    {
      ...op,
      status: "completed",
      result: { ...receiptFixture(), providerReservationId: "foreign" },
    },
  ])
    expect(() => readScheduleOperation(bad, op.context, op.actor_id)).toThrow();
  const service = createContactScheduleService({ read: vi.fn(), execute: vi.fn() }, op.context);
  service.admit(scheduleFixture());
  const next = scheduleFixture();
  next.workflow.actor_id = "foreign";
  expect(() => service.admit(next)).toThrow();
});

test("operation transitions retain receipts across stale reads and reject terminal rewrites", () => {
  const accepted = operationFixture(id);
  const completed: ScheduleOperation = {
    ...accepted,
    revision: 3,
    status: "completed",
    result: receiptFixture(),
  };
  const state = recordOperation(undefined, completed);
  expect(recordOperation(state, accepted)).toBe(state);
  expect(() => recordOperation(state, { ...accepted, revision: 3 })).toThrow();
  expect(() => recordOperation(state, { ...accepted, revision: 4 })).toThrow();
});

test("refresh and search cannot supersede a pending mutation, and duplicate clicks cannot resend it", async () => {
  const h = harness();
  const reply = deferred<unknown>();
  try {
    await h.wrapper.get("#contact-search").trigger("submit");
    await flushPromises();
    h.execute.mockImplementationOnce(() => reply.promise);
    await h.wrapper.get("#reserve-opportunity-one").trigger("click");
    await h.wrapper.get("#reserve-opportunity-one").trigger("click");
    const call = required(h.execute.mock.calls.at(-1));
    if (!("operation_id" in call[1])) throw Error("Missing command");
    await h.wrapper.get("#contact-schedule-refresh").trigger("click");
    await flushPromises();
    await h.wrapper.get("#contact-search").trigger("submit");
    await flushPromises();
    expect(
      h.execute.mock.calls.filter(([action, input]) => action === "reserve" && "payload" in input),
    ).toHaveLength(1);
    reply.resolve({
      ...operationFixture(call[1].operation_id),
      revision: 3,
      status: "completed",
      result: receiptFixture(),
    });
    await flushPromises();
    expect(h.wrapper.get("#contact-schedule-receipt").text()).toContain("reservation-one");
    expect(h.wrapper.get("#contact-search fieldset").attributes("disabled")).toBeUndefined();
  } finally {
    h.depart();
  }
});

test("a lost acceptance is observed by its original ID and retries reuse immutable input", async () => {
  const h = harness();
  try {
    h.execute.mockRejectedValueOnce(Error("private response lost"));
    await h.wrapper.get("#cancel-review-reservation-one").trigger("click");
    await h.wrapper.get("#contact-cancel-confirm").trigger("click");
    await flushPromises();
    const call = required(h.execute.mock.calls[0]);
    if (!("operation_id" in call[1])) throw Error("Missing command");
    h.execute.mockResolvedValueOnce({ operation: null });
    await h.wrapper.get("#contact-schedule-refresh").trigger("click");
    await flushPromises();
    expect(h.execute.mock.calls[1]).toEqual([
      "cancel",
      { contract_version: 2, operation_id: call[1].operation_id, observe: true },
    ]);
    await h.wrapper.get("#contact-schedule-operations button").trigger("click");
    await flushPromises();
    expect(h.execute.mock.calls[2]).toEqual(call);
    expect(h.wrapper.text()).not.toContain("private response lost");
  } finally {
    h.depart();
  }
});

test("nested LiveVue patches update projections without discarding drafts or recorded outcomes", async () => {
  const h = harness();
  const incoming = reactive(h.model);
  try {
    await h.wrapper.setProps({ schedule: incoming });
    await h.wrapper.get("#search-start").setValue("2099-09-09T12:01:17");
    required(incoming.reservations.entries[0]).provider_revision = 8;
    incoming.workflow.operations.entries.push({
      ...operationFixture(id),
      revision: 3,
      status: "completed",
      result: receiptFixture(),
    });
    await nextTick();
    expect(h.wrapper.get("#contact-reservations").text()).toContain("revision 8");
    expect(h.wrapper.get<HTMLInputElement>("#search-start").element.value).toBe(
      "2099-09-09T12:01:17",
    );
    incoming.workflow.operations.entries = [operationFixture(id)];
    await nextTick();
    expect(h.wrapper.get("#contact-schedule-operations").text()).toContain("completed");
  } finally {
    h.depart();
  }
});

test("an older read and a departed response cannot replace current evidence", async () => {
  const h = harness();
  const old = deferred<unknown>();
  try {
    h.read.mockReturnValueOnce(old.promise);
    await h.wrapper.get("#contact-schedule-refresh").trigger("click");
    const incoming = scheduleFixture();
    required(incoming.reservations.entries[0]).provider_revision = 9;
    await h.wrapper.setProps({ schedule: incoming });
    old.resolve(h.model);
    await flushPromises();
    expect(h.wrapper.get("#contact-reservations").text()).toContain("revision 9");
    const late = deferred<unknown>();
    h.execute.mockReturnValueOnce(late.promise);
    await h.wrapper.get("#contact-search").trigger("submit");
    h.depart();
    late.resolve(searchFixture());
    await flushPromises();
    expect(h.read).toHaveBeenCalledOnce();
  } finally {
    if (h.wrapper.exists()) h.depart();
  }
});

test("editing a reviewed search prevents booking its old opportunities", async () => {
  const h = harness();
  try {
    await h.wrapper.get("#contact-search").trigger("submit");
    await flushPromises();
    await h.wrapper.get("#search-start").setValue("2099-09-09T12:01:17");
    expect(h.wrapper.get("#reserve-opportunity-one").attributes("disabled")).toBeDefined();
  } finally {
    h.depart();
  }
});

test("definitive rejection remains distinct from unknown acceptance", async () => {
  const h = harness();
  try {
    h.execute.mockImplementationOnce(async (...request) => {
      if (!("operation_id" in request[1])) throw Error("Expected command");
      return {
        contract_version: 2,
        operation_id: request[1].operation_id,
        status: "not_accepted",
        reason: "review_changed",
      };
    });
    await h.wrapper.get("#cancel-review-reservation-one").trigger("click");
    await h.wrapper.get("#contact-cancel-confirm").trigger("click");
    await flushPromises();
    expect(h.wrapper.find("#contact-schedule-uncertain").exists()).toBe(false);
    expect(h.wrapper.get("#contact-schedule-operations").text()).toContain("Not accepted");
    expect(h.wrapper.find("#contact-schedule-operations button").exists()).toBe(false);
  } finally {
    h.depart();
  }
});

test("a late acceptance rejection cannot erase a concurrently observed operation", async () => {
  const h = harness();
  const pending = deferred<unknown>();
  try {
    h.execute.mockReturnValueOnce(pending.promise);
    await h.wrapper.get("#cancel-review-reservation-one").trigger("click");
    await h.wrapper.get("#contact-cancel-confirm").trigger("click");
    const request = required(h.execute.mock.calls[0]);
    if (!("operation_id" in request[1])) throw Error("Expected command");
    const operationId = request[1].operation_id;
    const incoming = scheduleFixture();
    incoming.workflow.operations.entries = [operationFixture(operationId, "cancel")];
    await h.wrapper.setProps({ schedule: incoming });
    pending.resolve({
      contract_version: 2,
      operation_id: operationId,
      status: "not_accepted",
      reason: "review_changed",
    });
    await flushPromises();
    expect(h.wrapper.get("#contact-schedule-operations").text()).toContain("accepted");
    expect(h.wrapper.get("#contact-schedule-operations").text()).not.toContain("Not accepted");
  } finally {
    h.depart();
  }
});
