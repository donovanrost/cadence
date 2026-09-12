import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import NativeDataSources from "./NativeDataSources.vue";
import { sourceContributions } from "./native-contribution";
import {
  admitSourcePage,
  type SourcePage,
  type SourceOperation,
  type Source,
} from "./native-contract";
const context = { organization_id: "org", mission_id: "mission" };
function stubConfirm(value: boolean) {
  const original = window.confirm;
  window.confirm = vi.fn(() => value);
  return {
    mockRestore: () => {
      window.confirm = original;
    },
  };
}
function fixture(): SourcePage {
  return {
    actor_id: "actor",
    sequence: 0,
    operation: null,
    read_error: false,
    model: {
      contract_version: 1,
      context,
      mode: "registration",
      permissions: { manage: true },
      query: {
        data_source_id: null,
        binding_id: null,
        page: 1,
        bindings_page: 1,
        events_page: 1,
        binding_events_page: 1,
        health_page: 1,
        health_events_page: 1,
        watermarks_page: 1,
        jobs_page: 1,
      },
      sources: { entries: [], page: 1, page_size: 25, has_next: false },
      bindings: { entries: [], page: 1, page_size: 25, has_next: false },
      selected: null,
      adapters: ["telemetry"],
      defaults: {
        data_source_id: "",
        logical_source: "telemetry",
        kind: "managed_tsdb",
        isolation_level: "mission_isolated",
        credentials_ref: "",
        credential_provider: "",
        endpoint_ref: "",
        material_env_profile: "",
        http_endpoint_env: "",
        storage: "questdb",
      },
    },
  };
}
function settings(): SourcePage {
  const p = fixture();
  p.model.mode = "settings";
  p.model.query.data_source_id = "source";
  const s: Source = {
    id: "source",
    ...context,
    owner: "cadence",
    kind: "managed_tsdb",
    status: "active",
    isolation: "mission_isolated",
    logical_source: "telemetry",
    credential_reference: null,
    event_id: "event",
    editable: true,
    evidence: "a".repeat(64),
    backend: { status: null, operation: null },
    capabilities: [],
    capabilities_more: false,
  };
  const empty = { entries: [], page: 1, page_size: 25 as const, has_next: false };
  p.model.sources.entries = [s];
  p.model.selected = {
    source: s,
    binding: null,
    events: structuredClone(empty),
    binding_events: structuredClone(empty),
    health: structuredClone(empty),
    health_events: structuredClone(empty),
    watermarks: structuredClone(empty),
    jobs: structuredClone(empty),
  };
  return p;
}
function completed(input: Record<string, any>, p = fixture()): SourceOperation {
  return {
    id: "operation",
    sequence: 1,
    action: "register-source",
    input,
    status: "completed",
    feedback: [],
    result: {
      contract_version: 1,
      ...context,
      actor_id: p.actor_id,
      action: "register-source",
      operation_id: "operation",
      source_id: input.params.source.data_source_id,
      event_ids: ["new-event"],
      result: {
        dataSourceId: input.params.source.data_source_id,
        organizationId: context.organization_id,
        missionId: context.mission_id,
        status: "active",
        kind: "managed_tsdb",
        isolationLevel: "mission_isolated",
      },
    },
  };
}
test("semantic admission rejects substituted source, observation, paging, permission and receipt identities", () => {
  const p = settings();
  expect(admitSourcePage(p, context, "settings")).toEqual(p);
  for (const mutate of [
    (x: any) => (x.model.contract_version = 2),
    (x: any) => (x.model.permissions.manage = false),
    (x: any) => (x.model.selected.source.mission_id = "foreign"),
    (x: any) => (x.model.query.data_source_id = "other"),
    (x: any) => (x.model.sources.has_next = true),
    (x: any) =>
      (x.model.selected.events.entries = [
        {
          id: "event",
          source_id: "other",
          type: "registered",
          status: "active",
          actor_id: "actor",
          occurred_at: "2026-09-09T10:00:00.123456Z",
        },
      ]),
  ]) {
    const bad = structuredClone(p);
    mutate(bad);
    expect(admitSourcePage(bad, context, "settings")).toBeNull();
  }
  const registration = fixture(),
    op = completed({
      params: { source: { ...registration.model.defaults, data_source_id: "new-source" } },
      review: {},
      confirmed: true,
    });
  expect(
    admitSourcePage({ ...registration, sequence: 1, operation: op }, context, "registration"),
  ).not.toBeNull();
  expect(
    admitSourcePage(
      {
        ...registration,
        sequence: 1,
        operation: { ...op, result: { ...op.result, source_id: "other" } },
      },
      context,
      "registration",
    ),
  ).toBeNull();
});
test("lost registration response recovers without resubmitting and retains native values", async () => {
  const p = fixture();
  let request: any,
    guard = () => true;
  const execute = vi.fn(async (_action, input) => {
    request = input;
    throw Error("lost");
  });
  const read = vi.fn(async () => ({ ...p, sequence: 1, operation: completed(request.payload) }));
  const confirm = stubConfirm(true);
  const w = mount(NativeDataSources, {
    props: {
      page: p,
      port: {
        execute,
        navigate: vi.fn(),
        guardNavigation(g) {
          guard = g;
          return () => {};
        },
      },
      readPort: { read },
    },
  });
  await w.get("#source-data_source_id").setValue("new-source");
  await w.get("#source-registration-form").trigger("submit");
  await flushPromises();
  expect(guard()).toBe(false);
  expect(w.find("#sources-unconfirmed").exists()).toBe(true);
  await w.get("#sources-refresh").trigger("click");
  await flushPromises();
  expect(w.find("#sources-unconfirmed").exists()).toBe(false);
  expect(w.get("#sources-operation").text()).toContain("new-event");
  expect(w.get("#source-register").attributes("disabled")).toBeDefined();
  expect((w.get("#source-data_source_id").element as HTMLInputElement).value).toBe("new-source");
  expect(execute).toHaveBeenCalledTimes(1);
  w.unmount();
  confirm.mockRestore();
});
test("changed source evidence requires explicit review and cancel creates no action", async () => {
  const p = settings(),
    fresh = structuredClone(p);
  fresh.model.selected!.source.evidence = "b".repeat(64);
  const execute = vi.fn(),
    confirm = stubConfirm(false);
  const w = mount(NativeDataSources, {
    props: {
      page: p,
      port: { execute, navigate: vi.fn() },
      readPort: { read: async () => structuredClone(fresh) },
    },
  });
  await w.get("#sources-refresh").trigger("click");
  await flushPromises();
  expect(w.get("#source-disable").attributes("disabled")).toBeDefined();
  await w.get("#source-accept-review").trigger("click");
  expect(w.get("#source-disable").attributes("disabled")).toBeUndefined();
  await w.get("#source-disable").trigger("click");
  expect(execute).not.toHaveBeenCalled();
  w.unmount();
  confirm.mockRestore();
});
test("foreign refresh and invalid local input retain registration draft without dispatch", async () => {
  const p = fixture(),
    execute = vi.fn();
  const confirm = stubConfirm(true);
  const w = mount(NativeDataSources, {
    props: {
      page: p,
      port: { execute, navigate: vi.fn() },
      readPort: { read: async () => ({ ...p, actor_id: "foreign" }) },
    },
  });
  await w.get("#source-data_source_id").setValue("界".repeat(100));
  await w.get("#source-registration-form").trigger("submit");
  await flushPromises();
  expect(execute).not.toHaveBeenCalled();
  expect(w.find("#sources-unconfirmed").exists()).toBe(false);
  await w.get("#source-data_source_id").setValue("retained-source");
  await w.get("#sources-refresh").trigger("click");
  await flushPromises();
  expect(w.get("#source-register").attributes("disabled")).toBeDefined();
  expect((w.get("#source-data_source_id").element as HTMLInputElement).value).toBe(
    "retained-source",
  );
  w.unmount();
  confirm.mockRestore();
});
test("reader and shared definitions expose no administrative controls", () => {
  for (const shared of [false, true]) {
    const p = settings();
    if (shared) {
      p.model.selected!.source.organization_id = null;
      p.model.selected!.source.mission_id = null;
      p.model.selected!.source.editable = false;
    } else {
      p.model.mode = "reader";
      p.model.permissions.manage = false;
    }
    expect(admitSourcePage(p, context, p.model.mode)).not.toBeNull();
    const w = mount(NativeDataSources, {
      props: {
        page: p,
        port: { execute: vi.fn(), navigate: vi.fn() },
        readPort: { read: vi.fn() },
      },
    });
    expect(w.find("#source-controls").exists()).toBe(false);
    expect(w.find("#source-binding-form").exists()).toBe(false);
    w.unmount();
  }
});
test("producer supplied native source contribution", async () => {
  if (!process.env.CADENCE_SOURCES) return;
  const supplied = JSON.parse(process.env.CADENCE_SOURCES),
    snapshot = supplied.snapshot,
    data = snapshot.data;
  const c = sourceContributions.find((c) => c.id === snapshot.id)!;
  const props = c.read(data, {
    organizationId: data.model.context.organization_id,
    missionId: data.model.context.mission_id,
  }) as { page: SourcePage };
  const calls: any[] = [],
    confirm = stubConfirm(true);
  const w = mount(NativeDataSources, {
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
  if (supplied.action === "requeue-deployment-run")
    await w.get("#source-job-requeue-" + supplied.job_id).trigger("click");
  else if (supplied.action === "disable-source") await w.get("#source-disable").trigger("click");
  else if (supplied.action === "change-binding") {
    await w.get("#source-binding").setValue(supplied.binding_id);
    await w.get("#source-target").setValue(supplied.target_id);
    await w.get("#source-binding-form").trigger("submit");
  } else {
    await w.get("#source-data_source_id").setValue(supplied.source_id);
    await w.get("#source-registration-form").trigger("submit");
  }
  await flushPromises();
  expect(calls).toHaveLength(1);
  if (supplied.operation) {
    expect(w.get("#sources-operation").text()).toContain(supplied.operation.id);
    expect(w.find("#sources-unconfirmed").exists()).toBe(false);
  }
  process.stdout.write("CADENCE_SOURCES_CALLS=" + JSON.stringify(calls) + "\n");
  w.unmount();
  confirm.mockRestore();
});

test("paging retains binding review and a changed destination requires explicit acceptance", async () => {
  const p = settings();
  const target = { ...p.model.sources.entries[0], id: "target", evidence: "b".repeat(64) };
  p.model.sources.entries.push(target);
  p.model.bindings.entries = [
    {
      id: "binding",
      source_id: "source",
      logical_source: "telemetry",
      realm: "flight",
      dataset: null,
      priority: 0,
      status: "active",
      version: 1,
      event_id: "binding-event",
      active_from: null,
      active_to: null,
      editable: true,
      evidence: "c".repeat(64),
    },
  ];
  const fresh = structuredClone(p);
  fresh.model.sources.entries[1].evidence = "d".repeat(64);
  const w = mount(NativeDataSources, {
    props: {
      page: p,
      port: { execute: vi.fn(), navigate: vi.fn() },
      readPort: { read: async () => structuredClone(fresh) },
    },
  });
  await w.get("#source-binding").setValue("binding");
  await w.get("#source-target").setValue("target");
  expect(w.get("#source-change-binding").attributes("disabled")).toBeUndefined();
  for (const [selector, value] of [
    ["#source-binding", "binding"],
    ["#source-target", "target"],
  ]) {
    await w.get(selector).setValue("");
    expect((w.get(selector).element as HTMLSelectElement).value).toBe("");
    expect(w.get("#source-change-binding").attributes("disabled")).toBeDefined();
    await w.get("#sources-refresh").trigger("click");
    await flushPromises();
    expect((w.get(selector).element as HTMLSelectElement).value).toBe("");
    expect(w.get("#source-change-binding").attributes("disabled")).toBeDefined();
    await w.get(selector).setValue(value);
  }
  fresh.model.sources.entries[1].evidence = "e".repeat(64);
  await w.get("#sources-refresh").trigger("click");
  await flushPromises();
  expect((w.get("#source-binding").element as HTMLSelectElement).value).toBe("binding");
  expect((w.get("#source-target").element as HTMLSelectElement).value).toBe("target");
  expect(w.get("#source-change-binding").attributes("disabled")).toBeDefined();
  await w.get("#source-accept-target").trigger("click");
  expect(w.get("#source-change-binding").attributes("disabled")).toBeUndefined();
  fresh.model.sources.entries = [fresh.model.sources.entries[0]];
  fresh.model.sources.page = 2;
  fresh.model.query.page = 2;
  await w.get("#sources-refresh").trigger("click");
  await flushPromises();
  expect((w.get("#source-target").element as HTMLSelectElement).value).toBe("target");
  expect(w.get("#source-change-binding").attributes("disabled")).toBeDefined();
  w.unmount();
});

test("observations retain microseconds and distinct binding context without rendering unadmitted fields", () => {
  const p = settings(),
    at = "2026-09-09T10:00:00.123456Z";
  p.model.selected!.health.entries = ["one", "two"].map((binding, i) => ({
    id: "health-" + i,
    key: "key-" + i,
    source_id: "source",
    binding_id: binding,
    logical_source: "telemetry",
    realm: "flight",
    dataset: null,
    replay_run_id: null,
    observed_at: at,
    reason: null,
    state: "healthy",
    last_seen_at: at,
    transitions: 0,
  }));
  Object.assign(p.model.selected!.health.entries[0], { private_payload: "MUST_NOT_RENDER" });
  expect(admitSourcePage(p, context, "settings")).not.toBeNull();
  const w = mount(NativeDataSources, {
    props: { page: p, port: { execute: vi.fn(), navigate: vi.fn() }, readPort: { read: vi.fn() } },
  });
  expect(w.get("#sources-health_page").text()).toContain(at);
  expect(w.get("#sources-health_page").text()).toContain("one");
  expect(w.get("#sources-health_page").text()).toContain("two");
  expect(w.text()).not.toContain("MUST_NOT_RENDER");
  w.unmount();
});

test("job recovery matches failed versus running state and lifecycle controls require dedicated BYO", async () => {
  const p = settings();
  p.model.selected!.jobs.entries = ["failed", "running"].map((status) => ({
    id: status + "-job",
    run_id: status + "-run",
    type: "tsdb_backend_lifecycle",
    status,
    attempts: 1,
    operation: "provision",
    started_at: "2026-09-09T12:00:00Z",
    completed_at: null,
    failure_recorded: status === "failed",
    evidence: "e".repeat(64),
  }));
  const execute = vi.fn(async () => {
      throw Error("capture");
    }),
    confirm = stubConfirm(true);
  const w = mount(NativeDataSources, {
    props: { page: p, port: { execute, navigate: vi.fn() }, readPort: { read: vi.fn() } },
  });
  expect(w.find("#source-provision-tsdb-backend").exists()).toBe(false);
  expect(w.get("#source-job-retry-failed-job").attributes("disabled")).toBeUndefined();
  expect(w.get("#source-job-requeue-failed-job").attributes("disabled")).toBeDefined();
  expect(w.get("#source-job-retry-running-job").attributes("disabled")).toBeDefined();
  expect(w.get("#source-job-requeue-running-job").attributes("disabled")).toBeUndefined();
  await w.get("#source-job-requeue-running-job").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith("requeue-deployment-run", {
    sequence: 1,
    payload: {
      params: { "job-id": "running-job" },
      review: { source: "a".repeat(64), job: "e".repeat(64) },
      confirmed: true,
    },
  });
  w.unmount();
  confirm.mockRestore();
  p.model.selected!.source.kind = "byo_tsdb";
  const byo = mount(NativeDataSources, {
    props: { page: p, port: { execute: vi.fn(), navigate: vi.fn() }, readPort: { read: vi.fn() } },
  });
  expect(byo.get("#source-provision-tsdb-backend").attributes("disabled")).toBeUndefined();
  byo.unmount();
});
