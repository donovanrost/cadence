import { producerFixture } from "../../../../../test-support/producer-fixture";
import type { MutableFixture } from "../../../../../test-support/mutable-fixture";
import { required } from "../../../../../test-support/required";
import { fixtureRecord, jsonFixture } from "../../../../../test-support/json-fixture";
import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import NativeHistoricalWorkflows from "./NativeHistoricalWorkflows.vue";
import {
  historicalWorkflowsContribution,
  historicalWorkflowsManageContribution,
} from "./native-contribution";
import {
  admitHistoryPage,
  admitHistoryOperation,
  isHistoryEffect,
  type HistoryPage,
  type HistoryOperation,
  type HistoryInputs,
  isHistoryCommand,
} from "./native-contract";
const context = { organization_id: "org", mission_id: "mission" };
function fixture(): MutableFixture<HistoryPage> {
  return {
    actor_id: "actor",
    sequence: 0,
    operation: null,
    read_error: false,
    model: {
      contract_version: 1,
      context,
      mode: "reader",
      query: {
        group: null,
        binding_q: "",
        page: 1,
        audit_page: 1,
        jobs_page: 1,
        origins_page: 1,
        bindings_page: 1,
      },
      permissions: { request: true, manage: true },
      groups: { entries: [], page: 1, page_size: 25, total: 0 },
      selected: null,
      bindings: {
        entries: [
          {
            id: "binding",
            source_id: "source",
            realm: "backfill",
            version: 1,
            evidence: "b".repeat(64),
          },
        ],
        page: 1,
        page_size: 25,
        total: 1,
      },
      defaults: {
        workflow: "backfill",
        run_id: "",
        realm: "",
        data_source_id: "",
        source_binding_id: "",
        point_ids: "",
        source_from: "2026-09-08T14:00:17Z",
        source_to: "2026-09-08T15:00:23Z",
        reason: "",
        confirmed: "false",
      },
    },
  };
}
function completed(
  input: HistoryInputs["record-request"],
  p = fixture(),
): Extract<HistoryOperation<"record-request">, { status: "completed" }> {
  return {
    id: "operation",
    sequence: 1,
    action: "record-request",
    input,
    status: "completed",
    feedback: [],
    result: {
      contract_version: 1,
      ...p.model.context,
      actor_id: p.actor_id,
      action: "record-request",
      operation_id: "operation",
      group_id: "group",
      event_ids: ["event"],
      event_count: 1,
      event_ids_truncated: false,
      event_digest: "a".repeat(64),
      job_ids: [],
      job_count: 0,
      job_ids_truncated: false,
    },
  };
}
async function fill(w: Pick<ReturnType<typeof mount>, "get">) {
  await w.get("#history-binding").setValue("binding");
  await w.get("#history-points").setValue("HK.temp,HK.rate");
  await w.get("#history-reason").setValue("Recover telemetry");
  await w.get("#history-confirmed").setValue(true);
}
test("native DTO rejects foreign context, malformed versions and forged result identities", () => {
  const p = fixture();
  expect(admitHistoryPage(p, context, "reader")).toEqual(p);
  expect(
    admitHistoryPage({ ...p, model: { ...p.model, contract_version: 2 } }, context, "reader"),
  ).toBeNull();
  expect(admitHistoryPage(p, { ...context, mission_id: "other" }, "reader")).toBeNull();
  const input = { request: { ...p.model.defaults }, binding_evidence: "b".repeat(64) };
  const op = completed(input, p);
  expect(admitHistoryPage({ ...p, sequence: 1, operation: op }, context, "reader")).not.toBeNull();
  expect(
    admitHistoryPage(
      { ...p, sequence: 1, operation: { ...op, result: { ...op.result, actor_id: "other" } } },
      context,
      "reader",
    ),
  ).toBeNull();
  expect(
    admitHistoryPage(
      { ...p, sequence: 1, operation: { ...op, result: { ...op.result, event_count: 25 } } },
      context,
      "reader",
    ),
  ).toBeNull();
});
test("unconfirmed outcomes admit recovery hints but never a completed receipt", () => {
  const p = fixture();
  const op = completed({ request: { ...p.model.defaults }, binding_evidence: "b".repeat(64) }, p);
  expect(admitHistoryOperation({ ...op, status: "unconfirmed" }, p)).toBeNull();
  expect(admitHistoryOperation({ ...op, status: "unconfirmed", result: null }, p)).not.toBeNull();
  expect(
    admitHistoryOperation(
      { ...op, status: "unconfirmed", result: { group_id: "group", operation_id: op.id } },
      p,
    ),
  ).not.toBeNull();
  expect(
    admitHistoryOperation(
      { ...op, status: "unconfirmed", result: { group_id: "group", operation_id: "foreign" } },
      p,
    ),
  ).toBeNull();
});
test("lost response retains native drafts and refresh recovers the exact operation without resubmitting", async () => {
  const p = fixture();
  let submitted: { sequence: number; payload: HistoryInputs["record-request"] } | undefined,
    guard: () => boolean = () => true;
  const execute = vi.fn(async (action: string, input: Record<string, unknown>) => {
    const command = { action, input: input.payload };
    if (
      !isHistoryCommand(command) ||
      command.action !== "record-request" ||
      typeof input.sequence !== "number"
    )
      throw Error("Unexpected request command");
    submitted = { sequence: input.sequence, payload: command.input };
    throw Error("lost");
  });
  const read = vi.fn(async () => ({
    ...p,
    sequence: 1,
    operation: completed(required(submitted).payload, p),
  }));
  const w = mount(NativeHistoricalWorkflows, {
    props: {
      page: p,
      port: {
        execute,
        navigate: vi.fn(),
        guardNavigation: (g: () => boolean) => {
          guard = g;
          return () => {};
        },
      },
      readPort: { read },
    },
  });
  await fill(w);
  await w.get("#historical-workflow-form").trigger("submit");
  await flushPromises();
  expect(execute).toHaveBeenCalledTimes(1);
  expect(w.find("#history-unconfirmed").exists()).toBe(true);
  expect(guard()).toBe(false);
  expect(required(submitted).payload.request.source_from).toBe("2026-09-08T14:00:17Z");
  await w.get("#history-refresh").trigger("click");
  await flushPromises();
  expect(w.find("#history-unconfirmed").exists()).toBe(false);
  expect(w.get("#history-operation").text()).toContain("event");
  expect((w.get("#history-reason").element as HTMLTextAreaElement).value).toBe("Recover telemetry");
  expect(w.get("#history-record-request").attributes("disabled")).toBeDefined();
  expect(execute).toHaveBeenCalledTimes(1);
  w.unmount();
});
test("foreign and stale refreshes cannot overwrite drafts or admit another action", async () => {
  const p = fixture(),
    execute = vi.fn(),
    read = vi.fn(async () => ({
      ...p,
      model: { ...p.model, context: { ...context, mission_id: "foreign" } },
    }));
  const w = mount(NativeHistoricalWorkflows, {
    props: { page: p, port: { execute, navigate: vi.fn() }, readPort: { read } },
  });
  await fill(w);
  await w.get("#history-refresh").trigger("click");
  await flushPromises();
  expect(w.get("#history-record-request").attributes("disabled")).toBeDefined();
  expect((w.get("#history-reason").element as HTMLTextAreaElement).value).toBe("Recover telemetry");
  expect(execute).not.toHaveBeenCalled();
  w.unmount();
});
test("binding paging retains the reviewed binding and unsaved request", async () => {
  const p = fixture();
  p.model.bindings.total = 26;
  let operation: HistoryOperation;
  const execute = vi.fn(async (action: string, input: Record<string, unknown>) => {
    const command = { action, input: input.payload };
    if (
      !isHistoryCommand(command) ||
      command.action !== "read-page" ||
      typeof input.sequence !== "number"
    )
      throw Error("Unexpected paging command");
    operation = {
      ...command,
      id: "page-operation",
      sequence: input.sequence,
      status: "completed",
      result: { page_changed: true },
      feedback: [],
    };
    return operation;
  });
  const read = vi.fn(async () => ({
    ...p,
    sequence: 1,
    operation,
    model: {
      ...p.model,
      query: { ...p.model.query, bindings_page: 2 },
      bindings: { entries: [], page: 2, page_size: 25, total: 26 },
    },
  }));
  const w = mount(NativeHistoricalWorkflows, {
    props: { page: p, port: { execute, navigate: vi.fn() }, readPort: { read } },
  });
  await fill(w);
  await w.get("#history-bindings-next").trigger("click");
  await flushPromises();
  expect((w.get("#history-binding").element as HTMLSelectElement).value).toBe("binding");
  expect((w.get("#history-reason").element as HTMLTextAreaElement).value).toBe("Recover telemetry");
  expect(required(execute.mock.calls[0])[1]).toMatchObject({
    payload: { query: { bindings_page: "2" } },
  });
  w.unmount();
});
const producer = producerFixture("CADENCE_HISTORY", import.meta.url);
test.skipIf(!producer.available)("producer supplied native history contribution", async () => {
  const supplied = jsonFixture(producer.read()),
    snapshot = fixtureRecord(supplied.snapshot),
    raw = fixtureRecord(snapshot.data),
    model = fixtureRecord(raw.model),
    context = fixtureRecord(model.context);
  if (typeof context.organization_id !== "string" || typeof context.mission_id !== "string")
    throw Error("Missing native context");
  const data = required(
    admitHistoryPage(
      raw,
      { organization_id: context.organization_id, mission_id: context.mission_id },
      String(model.mode),
    ),
  );
  const registration =
    data.model.mode === "manage"
      ? historicalWorkflowsManageContribution
      : historicalWorkflowsContribution;
  const props = registration.read(data, {
    organizationId: data.model.context.organization_id,
    missionId: data.model.context.mission_id,
  });
  const calls: [string, Record<string, unknown>][] = [];
  const w = mount(NativeHistoricalWorkflows, {
    props: {
      ...props,
      port: {
        navigate: vi.fn(),
        execute: async (action: string, input: Record<string, unknown>) => {
          calls.push([action, input]);
          if (supplied.operation) return supplied.operation;
          throw Error("capture-only");
        },
      },
      readPort: { read: async () => supplied.after ?? data },
    },
  });
  const originalConfirm = window.confirm;
  window.confirm = vi.fn(() => true);
  if (supplied.stage) {
    await w.get("#history-transition-reason").setValue("界".repeat(600));
    if (typeof supplied.stage !== "string") throw Error("Invalid stage fixture");
    await w.get("#history-" + supplied.stage).trigger("click");
  } else {
    await w.get("#history-binding").setValue(required(data.model.bindings.entries[0]).id);
    await w.get("#history-points").setValue("HK.temp,HK.rate");
    await w.get("#history-reason").setValue("界".repeat(600));
    await w.get("#history-confirmed").setValue(true);
    await w.get("#historical-workflow-form").trigger("submit");
  }
  await flushPromises();
  window.confirm = originalConfirm;
  expect(calls).toHaveLength(1);
  expect(required(calls[0])[0]).toBe(supplied.stage ? "transition-group" : "record-request");
  if (supplied.operation) {
    const operation = required(admitHistoryOperation(supplied.operation, data));
    if (!isHistoryEffect(operation) || operation.status !== "completed")
      throw Error("Expected completed effect fixture");
    expect(w.get("#history-operation").text()).toContain(required(operation.result.event_ids[0]));
    expect(w.find("#history-unconfirmed").exists()).toBe(false);
  }
  process.stdout.write("CADENCE_HISTORY_CALLS=" + JSON.stringify(calls) + "\n");
  w.unmount();
});

test("a changed binding requires an explicit review while retaining request values", async () => {
  const p = fixture(),
    fresh = {
      ...p,
      model: {
        ...p.model,
        bindings: {
          ...p.model.bindings,
          entries: [{ ...p.model.bindings.entries[0], version: 2, evidence: "c".repeat(64) }],
        },
      },
    };
  const execute = vi.fn(async () => {
    throw Error("capture-only");
  });
  const w = mount(NativeHistoricalWorkflows, {
    props: { page: p, port: { execute, navigate: vi.fn() }, readPort: { read: async () => fresh } },
  });
  await fill(w);
  await w.get("#history-refresh").trigger("click");
  await flushPromises();
  expect(w.get("#history-record-request").attributes("disabled")).toBeDefined();
  expect((w.get("#history-reason").element as HTMLTextAreaElement).value).toBe("Recover telemetry");
  await w.get("#history-use-current-binding").trigger("click");
  expect(w.get("#history-record-request").attributes("disabled")).toBeUndefined();
  w.unmount();
});
