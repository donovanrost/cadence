import { jsonFixture } from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { afterEach, beforeEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { DefinitionsSurface } from "../../definitions";
import { definitionsFixture, emptyPage } from "../../shared/testing";
import {
  admitDocument,
  inputThresholds,
  type DefinitionInput,
  type DefinitionsDocument,
  type DefinitionsPort,
} from "./contracts";
const mounted: { unmount: () => void }[] = [];
beforeEach(() => {
  window.sessionStorage.clear();
  window.confirm = vi.fn(() => true);
});
afterEach(() => {
  mounted.splice(0).forEach((w) => w.unmount());
  vi.restoreAllMocks();
});
function start(document = definitionsFixture(), overrides: Partial<DefinitionsPort> = {}) {
  const port: DefinitionsPort = {
    read: vi.fn(async () => document),
    save: vi.fn(async () => {
      throw Error("offline");
    }),
    navigate: vi.fn<(href: string) => void>(),
    ...overrides,
  };
  const w = mount(DefinitionsSurface, { props: { document, port } });
  mounted.push(w);
  return { w, port };
}
async function edit(w: Pick<ReturnType<typeof mount>, "get">) {
  await w.get("#edit-reviewed-limits").trigger("click");
  await w.get("#limits-yellow_high").setValue("31.5");
  await w.get("#limits-red_high").setValue("34");
}
function receipt(input: DefinitionInput) {
  return {
    receiptId: "limit-receipt",
    completedAt: "2026-09-09T12:00:00Z",
    result: {
      definitionId: input.expected_definition_id ?? "limit-definition",
      pointId: input.point_id,
      limitSetName: input.limit_set_name,
      version: input.expected_version + 1,
      thresholds: inputThresholds(input),
    },
  };
}
test("producer supplied document drives the public editor's reviewed save", async () => {
  const document: DefinitionsDocument = process.env.CADENCE_LIMITS_PAGE
    ? required(admitDocument(jsonFixture(process.env.CADENCE_LIMITS_PAGE)))
    : definitionsFixture();
  expect(admitDocument(document)).not.toBeNull();
  const { w, port } = start(document);
  await edit(w);
  await w.get("#limits-definition-form").trigger("submit");
  await flushPromises();
  const [input, key] = required(vi.mocked(port.save).mock.calls[0]);
  expect(input).toMatchObject({
    point_id: document.editor?.point_id,
    limit_set_name: document.editor?.limit_set_name,
    expected_version: document.editor?.review.version,
    expected_definition_id: document.editor?.review.definition_id,
    expected_activation_event_id: document.editor?.review.activation_event_id,
  });
  expect(key).toBeTruthy();
  expect(w.find("#limits-pending").exists()).toBe(true);
  if (process.env.CADENCE_LIMITS_PAGE)
    process.stdout.write("CADENCE_LIMITS_INPUT=" + JSON.stringify(input) + "\n");
});
test("rejects malformed counts, foreign links, and contradictory activation evidence", () => {
  const malformed = definitionsFixture();
  malformed.definitions.total_count = 1;
  expect(admitDocument(malformed)).toBeNull();
  const contradictory = definitionsFixture();
  required(contradictory.editor).review.activation_event_id = "fake-event";
  expect(admitDocument(contradictory)).toBeNull();
  const { w } = start({
    ...definitionsFixture(),
    links: { ...definitionsFixture().links, self: "/missions/other/applications/limits/manage" },
  });
  expect(w.find("#limits-definitions-unavailable").exists()).toBe(true);
  expect(w.find("form").exists()).toBe(false);
});
test("requires a server review and an increasing finite threshold envelope", async () => {
  const { w, port } = start();
  expect(w.get("#save-limit-definition").attributes("disabled")).toBeDefined();
  await edit(w);
  expect(w.get("#save-limit-definition").attributes("disabled")).toBeUndefined();
  await w.get("#limits-red_high").setValue("30");
  await w.get("#limits-definition-form").trigger("submit");
  expect(port.save).not.toHaveBeenCalled();
  await w.get("#limits-red_high").setValue("1e300");
  expect(w.get("#save-limit-definition").attributes("disabled")).toBeDefined();
});
test("retains a draft across navigation and recovers exactly the pending save after remount", async () => {
  const first = start();
  await edit(first.w);
  await first.w.get("#limits-definition-form").trigger("submit");
  await flushPromises();
  const original = required(vi.mocked(first.port.save).mock.calls[0]);
  first.w.unmount();
  mounted.splice(mounted.indexOf(first.w), 1);
  const next = start(definitionsFixture(), {
    save: vi.fn<DefinitionsPort["save"]>(async (input) => receipt(input)),
  });
  expect(next.w.find("#limits-pending").exists()).toBe(true);
  expect(next.w.get("#limits-yellow_high").element).toHaveProperty("value", "31.5");
  await next.w.get("#recover-limits-save").trigger("click");
  await flushPromises();
  expect(next.port.save).toHaveBeenCalledWith(...original);
  expect(next.w.find("#limits-confirmed").exists()).toBe(true);
  expect(next.w.find("#limits-pending").exists()).toBe(false);
});
test("recovery permission failure leaves the original uncertain save pending", async () => {
  const first = start();
  await edit(first.w);
  await first.w.get("#limits-definition-form").trigger("submit");
  await flushPromises();
  const intent = required(vi.mocked(first.port.save).mock.calls[0]);
  first.w.unmount();
  mounted.splice(mounted.indexOf(first.w), 1);
  const next = start(definitionsFixture(), {
    save: vi.fn(async () => {
      throw Object.assign(Error("The host request failed."), { code: "forbidden" });
    }),
  });
  await next.w.get("#recover-limits-save").trigger("click");
  await flushPromises();
  expect(next.port.save).toHaveBeenCalledWith(...intent);
  expect(next.w.find("#limits-pending").exists()).toBe(true);
  expect(next.w.get("#save-limit-definition").attributes("disabled")).toBeDefined();
});
test("a generic bridge rejection keeps thresholds and requires refreshed review", async () => {
  const { w } = start(definitionsFixture(), {
    save: vi.fn(async () => {
      throw Object.assign(Error("The host request failed."), { code: "review_conflict" });
    }),
  });
  await edit(w);
  await w.get("#limits-definition-form").trigger("submit");
  await flushPromises();
  expect(w.get("#limits-notice").text()).toContain("activation changed");
  expect(w.find("#limits-pending").exists()).toBe(false);
  expect(w.get("#limits-yellow_high").element).toHaveProperty("value", "31.5");
  expect(w.get("#save-limit-definition").attributes("disabled")).toBeDefined();
});
test("changed activation evidence invalidates an existing draft and preserves it", async () => {
  const doc = definitionsFixture();
  const { w, port } = start(doc);
  await edit(w);
  const fresh = structuredClone(doc);
  required(fresh.editor).current = {
    id: "definition",
    point_id: "HK.voltage",
    limit_set_name: "FLIGHT",
    version: 1,
    thresholds: { yellow_high: 20 },
  };
  required(fresh.editor).review = {
    definition_id: "definition",
    version: 1,
    activation_event_id: "event-1",
  };
  required(fresh.editor).active = {
    definition_id: "definition",
    version: 1,
    event_id: "event-1",
    active_from: "2026-09-09T12:00:00Z",
    active_to: null,
  };
  vi.mocked(port.read).mockResolvedValue(fresh);
  await w.get("#refresh-limits").trigger("click");
  await flushPromises();
  expect(w.find("#limits-stale").exists()).toBe(true);
  expect(w.get("#limits-yellow_high").element).toHaveProperty("value", "31.5");
  expect(w.get("#save-limit-definition").attributes("disabled")).toBeDefined();
});

function reviewedFixture(): DefinitionsDocument {
  const d = definitionsFixture();
  required(d.editor).current = {
    id: "definition",
    point_id: "HK.voltage",
    limit_set_name: "FLIGHT",
    version: 2,
    thresholds: { yellow_high: 20, red_high: 24 },
  };
  required(d.editor).active = {
    definition_id: "definition",
    version: 2,
    event_id: "event-2",
    active_from: "2026-09-09T12:00:00Z",
    active_to: null,
  };
  required(d.editor).review = {
    definition_id: "definition",
    version: 2,
    activation_event_id: "event-2",
  };
  return d;
}
test("reactivating an older version invalidates review without changing the newest version", async () => {
  const doc = reviewedFixture();
  const { w, port } = start(doc);
  await edit(w);
  const fresh = structuredClone(doc);
  required(required(fresh.editor).active).version = 1;
  required(required(fresh.editor).active).event_id = "reactivated-1";
  required(fresh.editor).review.activation_event_id = "reactivated-1";
  vi.mocked(port.read).mockResolvedValue(fresh);
  await w.get("#refresh-limits").trigger("click");
  await flushPromises();
  expect(w.find("#limits-stale").exists()).toBe(true);
  expect(w.get("#limits-yellow_high").element).toHaveProperty("value", "31.5");
  await w.get("#limits-definition-form").trigger("submit");
  expect(port.save).not.toHaveBeenCalled();
});
test("historical thresholds produce a new version using the current review", async () => {
  const doc = reviewedFixture();
  doc.query.definition = "definition";
  doc.query.version = 1;
  doc.selection = {
    id: "definition",
    available: true,
    current: required(required(doc.editor).current),
    inspected: {
      ...required(required(doc.editor).current),
      version: 1,
      thresholds: { yellow_high: 10, red_high: 14 },
    },
    active: required(doc.editor).active,
    history: emptyPage(),
    activations: emptyPage(),
  };
  const { w, port } = start(doc, {
    save: vi.fn<DefinitionsPort["save"]>(async (input) => receipt(input)),
  });
  await w.get("#reuse-limit-thresholds").trigger("click");
  expect(w.get("#limits-yellow_high").element).toHaveProperty("value", "10");
  await w.get("#limits-definition-form").trigger("submit");
  await flushPromises();
  expect(required(vi.mocked(port.save).mock.calls[0])[0]).toMatchObject({
    expected_version: 2,
    expected_activation_event_id: "event-2",
    yellow_high: "10",
    red_high: "14",
  });
  expect(w.get("#limits-confirmed").text()).toContain("v3");
  expect(w.get("#save-limit-definition").attributes("disabled")).toBeDefined();
});
test("point paging preserves the threshold draft and unfinished identity selection", async () => {
  const doc = definitionsFixture();
  const first = start(doc);
  await edit(first.w);
  await first.w.get("#limits-point").setValue("HK.temperature");
  await first.w.get("#limits-set").setValue("SURVIVAL");
  await first.w.get("#limits-point-search").setValue("temperature");
  required(first.w.get("#limits-point-search").element.closest("form")).dispatchEvent(
    new Event("submit", { bubbles: true, cancelable: true }),
  );
  expect(first.port.navigate).toHaveBeenCalled();
  first.w.unmount();
  mounted.splice(mounted.indexOf(first.w), 1);
  const next = start({ ...doc, query: { ...doc.query, points_q: "temperature" } });
  expect(next.w.get("#limits-yellow_high").element).toHaveProperty("value", "31.5");
  expect(next.w.get("#limits-point").element).toHaveProperty("value", "HK.temperature");
  expect(next.w.get("#limits-set").element).toHaveProperty("value", "SURVIVAL");
  expect(next.port.save).not.toHaveBeenCalled();
});
test("confirmed evidence remains distinct from a later draft and isolated by actor", async () => {
  const doc = definitionsFixture();
  const first = start(doc, {
    save: vi.fn<DefinitionsPort["save"]>(async (input) => receipt(input)),
  });
  await edit(first.w);
  await first.w.get("#limits-definition-form").trigger("submit");
  await flushPromises();
  await first.w.get("#limits-yellow_high").setValue("32");
  first.w.unmount();
  mounted.splice(mounted.indexOf(first.w), 1);
  const next = start(doc);
  expect(next.w.get("#limits-confirmed").text()).toContain("v1");
  expect(next.w.get("#limits-yellow_high").element).toHaveProperty("value", "32");
  const other = start({ ...doc, context: { ...doc.context, actor_id: "other-operator" } });
  expect(other.w.find("#limits-confirmed").exists()).toBe(false);
  expect(other.w.get("#limits-yellow_high").element).toHaveProperty("value", "");
});
