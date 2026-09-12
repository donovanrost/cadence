import { mount, flushPromises } from "@vue/test-utils";
import { beforeEach, test, expect, vi } from "vite-plus/test";
import DefinitionsSurface from "./DefinitionsSurface.vue";
import {
  admitDocument,
  type DefinitionsDocument,
  type DefinitionsPort,
  type DefinitionInput,
} from "./contracts";
const base = "/missions/mission/applications/derived_telemetry/manage";
const context = { scope: "mission", organizationId: "org", missionId: "mission" };
const page = <T>(items: T[] = []) => ({
  items,
  total_count: items.length,
  page: 1,
  page_size: 25 as const,
  previous_href: null,
  next_href: null,
});
function document(): DefinitionsDocument {
  return {
    contract_version: 1,
    context: {
      organization_id: "org",
      mission_id: "mission",
      actor_id: "actor",
      installation_id: "installation",
    },
    mission_name: "Nova",
    query: {
      page: 1,
      history_page: 1,
      values_page: 1,
      sources_page: 1,
      spacecraft_page: 1,
      spacecraft_q: "",
      q: "",
      values_q: "",
      definition: "",
      version: null,
      spacecraft: "",
    },
    definitions: page(),
    selection: null,
    values: page(),
    spacecraft: page(),
    spacecraft_filter: "All spacecraft and mission values",
    links: { self: base, applications: "/missions/mission/applications" },
  };
}
function receipt(input: DefinitionInput) {
  return {
    receiptId: "receipt-1",
    completedAt: "2026-09-09T00:00:00Z",
    result: {
      definitionId: input.expected_definition_id ?? "definition-1",
      pointId: input.point_id,
      pointName: input.point_name,
      expression: input.expression,
      version: input.expected_version + 1,
      sourceCount: 1,
    },
  };
}
function port(p: DefinitionsDocument): DefinitionsPort {
  return {
    read: vi.fn().mockResolvedValue(p),
    save: vi.fn().mockImplementation(async (input) => receipt(input)),
    navigate: vi.fn(),
  };
}
function render(p = document(), bridge = port(p)) {
  return mount(DefinitionsSurface, { props: { document: p, hostContext: context, port: bridge } });
}
async function fill(w: ReturnType<typeof render>) {
  await w.get("#derived-point-id").setValue("DERIVED.power");
  await w.get("#derived-point-name").setValue("Bus power");
  await w.get("#derived-expression").setValue("HK.voltage * 2");
}
beforeEach(() => {
  sessionStorage.clear();
  vi.unstubAllGlobals();
});
test("rejects foreign or malformed definition evidence", () => {
  const p = document();
  expect(admitDocument(p, context)).not.toBeNull();
  for (const change of [
    (x: any) => (x.context.mission_id = "foreign"),
    (x: any) => (x.definitions.total_count = 1),
    (x: any) => (x.links.applications = "https://foreign"),
    (x: any) => (x.query.page = -1),
  ]) {
    const broken = structuredClone(p);
    change(broken);
    expect(admitDocument(broken, context)).toBeNull();
  }
});
test("editing is local and an explicit save carries reviewed identity and returns a retained receipt", async () => {
  const p = document(),
    bridge = port(p),
    w = render(p, bridge);
  await fill(w);
  expect(bridge.save).not.toHaveBeenCalled();
  await w.get("#derived-definition-form").trigger("submit");
  await flushPromises();
  const [input, key] = vi.mocked(bridge.save).mock.calls[0];
  expect(input).toEqual({
    point_id: "DERIVED.power",
    point_name: "Bus power",
    expression: "HK.voltage * 2",
    expected_definition_id: null,
    expected_version: 0,
  });
  expect(key).toMatch(/^[a-f0-9-]{36}$/);
  expect(w.get("#derived-save-receipt").text()).toContain("receipt-1");
  await w.get("#new-derived-definition").trigger("click");
  w.unmount();
  const restored = render(p, bridge);
  expect(restored.get("#derived-save-receipt").text()).toContain("receipt-1");
  restored.unmount();
});
test("unknown outcomes survive remount and recover with identical input and key", async () => {
  const p = document(),
    bridge = port(p);
  vi.mocked(bridge.save).mockRejectedValueOnce(Error("lost"));
  const w = render(p, bridge);
  await fill(w);
  await w.get("#derived-definition-form").trigger("submit");
  await flushPromises();
  const first = vi.mocked(bridge.save).mock.calls[0];
  expect(w.find("#derived-pending").exists()).toBe(true);
  w.unmount();
  const restored = render(p, bridge);
  vi.mocked(bridge.save).mockRejectedValueOnce(
    Object.assign(Error("denied"), { code: "forbidden" }),
  );
  await restored.get("#recover-derived-save").trigger("click");
  await flushPromises();
  expect(restored.find("#derived-pending").exists()).toBe(true);
  await restored.get("#recover-derived-save").trigger("click");
  await flushPromises();
  expect(vi.mocked(bridge.save).mock.calls[1]).toEqual(first);
  expect(vi.mocked(bridge.save).mock.calls[2]).toEqual(first);
  expect(restored.find("#derived-pending").exists()).toBe(false);
  restored.unmount();
});
test("newer saved evidence retains the draft and requires explicit version review", async () => {
  const p = document(),
    bridge = port(p),
    w = render(p, bridge);
  await fill(w);
  const def = {
    id: "definition-1",
    point_id: "DERIVED.power",
    point_name: "Saved",
    expression: "HK.voltage * 3",
    version: 1,
    source_count: 1,
  };
  const next = {
    ...p,
    query: { ...p.query, definition: def.id },
    selection: {
      available: true as const,
      id: def.id,
      current: def,
      inspected: def,
      history: page([
        {
          ...def,
          expression_preview: def.expression,
          href: base + "?definition=definition-1&version=1",
        },
      ]),
      sources: page(["HK.voltage"]),
    },
  };
  vi.mocked(bridge.read).mockResolvedValue(next);
  await w.get("#refresh-derived").trigger("click");
  await flushPromises();
  expect(w.find("#derived-stale").exists()).toBe(true);
  expect((w.get("#derived-expression").element as HTMLTextAreaElement).value).toBe(
    "HK.voltage * 2",
  );
  vi.stubGlobal("confirm", vi.fn().mockReturnValue(true));
  await w.get("#review-derived-current").trigger("click");
  expect((w.get("#derived-expression").element as HTMLTextAreaElement).value).toBe(
    "HK.voltage * 3",
  );
  w.unmount();
});
test("producer supplied evidence mounts the public editor and yields the explicit action input", async () => {
  if (!process.env.CADENCE_DERIVED_PAGE) return;
  const p = JSON.parse(process.env.CADENCE_DERIVED_PAGE) as DefinitionsDocument;
  expect(admitDocument(p)).not.toBeNull();
  const bridge = port(p);
  vi.mocked(bridge.save).mockRejectedValue(Error("capture only"));
  const w = mount(DefinitionsSurface, { props: { document: p, port: bridge } });
  await fill(w);
  await w.get("#derived-expression").setValue("HK.voltage" + " + 1".repeat(100));
  await w.get("#derived-definition-form").trigger("submit");
  await flushPromises();
  expect(bridge.save).toHaveBeenCalledTimes(1);
  process.stdout.write(
    "CADENCE_DERIVED_INPUT=" + JSON.stringify(vi.mocked(bridge.save).mock.calls[0][0]) + "\n",
  );
  w.unmount();
});

test("review evidence rejects mismatched version links, source counts and history identities", () => {
  const p = document();
  const d = {
    id: "definition-1",
    point_id: "DERIVED.power",
    point_name: "Power",
    expression: "HK.voltage",
    version: 2,
    source_count: 1,
  };
  const selected: DefinitionsDocument = {
    ...p,
    query: { ...p.query, definition: d.id, version: 2 },
    selection: {
      available: true,
      id: d.id,
      current: d,
      inspected: d,
      history: page([
        {
          ...d,
          expression_preview: d.expression,
          href: base + "?definition=definition-1&version=2",
        },
      ]),
      sources: page(["HK.voltage"]),
    },
  };
  expect(admitDocument(selected)).not.toBeNull();
  for (const change of [
    (x: any) => (x.query.version = 1),
    (x: any) => (x.selection.inspected.source_count = 2),
    (x: any) => (x.selection.history.items[0].id = "foreign"),
    (x: any) => (x.selection.history.items[0].href = base + "?definition=definition-1&version=1"),
    (x: any) => (x.selection = null),
  ]) {
    const broken = structuredClone(selected);
    change(broken);
    expect(admitDocument(broken)).toBeNull();
  }
});

for (const [code, message] of [
  ["invalid_expression", "The expression is invalid"],
  ["review_conflict", "This definition changed"],
  ["review_required", "Review the current definition"],
]) {
  test(`explains ${code} even when the production bridge supplies a generic message`, async () => {
    const p = document(),
      bridge = port(p),
      w = render(p, bridge);
    vi.mocked(bridge.save).mockRejectedValue(
      Object.assign(Error("The host request failed."), { code }),
    );
    await fill(w);
    await w.get("#derived-definition-form").trigger("submit");
    await flushPromises();
    expect(w.get("#derived-notice").text()).toContain(message);
    expect(w.find("#derived-pending").exists()).toBe(false);
    expect((w.get("#derived-expression").element as HTMLTextAreaElement).value).toBe(
      "HK.voltage * 2",
    );
    expect(w.get("#save-derived-definition").attributes("disabled")).toBeDefined();
    await w.get("#refresh-derived").trigger("click");
    await flushPromises();
    expect(w.get("#save-derived-definition").attributes("disabled")).toBeUndefined();
    w.unmount();
  });
}
