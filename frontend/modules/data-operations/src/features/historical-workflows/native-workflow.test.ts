import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import NativeHistoricalWorkflows from "./NativeHistoricalWorkflows.vue";
import {
  historicalWorkflowsContribution,
  historicalWorkflowsManageContribution,
} from "./native-contribution";
import { admitHistoryPage, type HistoryPage, type HistoryOperation } from "./native-contract";
const context = { organization_id: "org", mission_id: "mission" };
function fixture(): HistoryPage {
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
function completed(input: Record<string, any>, p = fixture()): HistoryOperation {
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
async function fill(w: ReturnType<typeof mount>) {
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
test("lost response retains native drafts and refresh recovers the exact operation without resubmitting", async () => {
  const p = fixture();
  let submitted: any,
    guard: () => boolean = () => true;
  const execute = vi.fn(async (_action, input) => {
    submitted = input;
    throw Error("lost");
  });
  const read = vi.fn(async () => ({
    ...p,
    sequence: 1,
    operation: completed(submitted.payload, p),
  }));
  const w = mount(NativeHistoricalWorkflows, {
    props: {
      page: p,
      port: {
        execute,
        navigate: vi.fn(),
        guardNavigation: (g) => {
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
  expect(submitted.payload.request.source_from).toBe("2026-09-08T14:00:17Z");
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
  const execute = vi.fn(
    async (action, input) =>
      (operation = {
        id: "page-operation",
        sequence: input.sequence,
        action,
        input: input.payload,
        status: "completed",
        result: { page_changed: true },
        feedback: [],
      }),
  );
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
  expect(execute.mock.calls[0][1].payload.query.bindings_page).toBe("2");
  w.unmount();
});
test("producer supplied native history contribution", async () => {
  if (!process.env.CADENCE_HISTORY) return;
  const supplied = JSON.parse(process.env.CADENCE_HISTORY),
    snapshot = supplied.snapshot,
    data = snapshot.data;
  const registration =
    data.model.mode === "manage"
      ? historicalWorkflowsManageContribution
      : historicalWorkflowsContribution;
  const props = registration.read(data, {
    organizationId: data.model.context.organization_id,
    missionId: data.model.context.mission_id,
  }) as { page: HistoryPage };
  const calls: any[] = [];
  const w = mount(NativeHistoricalWorkflows, {
    props: {
      ...props,
      port: {
        navigate: vi.fn(),
        execute: async (action, input) => {
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
    await w.get("#history-" + supplied.stage).trigger("click");
  } else {
    await w.get("#history-binding").setValue(data.model.bindings.entries[0].id);
    await w.get("#history-points").setValue("HK.temp,HK.rate");
    await w.get("#history-reason").setValue("界".repeat(600));
    await w.get("#history-confirmed").setValue(true);
    await w.get("#historical-workflow-form").trigger("submit");
  }
  await flushPromises();
  window.confirm = originalConfirm;
  expect(calls).toHaveLength(1);
  expect(calls[0][0]).toBe(supplied.stage ? "transition-group" : "record-request");
  if (supplied.operation) {
    expect(w.get("#history-operation").text()).toContain(supplied.operation.result.event_ids[0]);
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
