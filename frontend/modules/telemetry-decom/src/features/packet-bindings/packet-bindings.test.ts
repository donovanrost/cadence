import { producerFixture } from "../../../../../test-support/producer-fixture";
import { fixtureArrayAt, fixtureRecordAt } from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { mount, flushPromises } from "@vue/test-utils";
import { beforeEach, test, expect, vi } from "vite-plus/test";
import PacketBindingsSurface from "./PacketBindingsSurface.vue";
import {
  admitPacketDocument,
  type PacketDocument,
  type PacketPort,
  type SelectionInput,
} from "./contracts";
const base = "/missions/mission/spacecraft/spacecraft/applications/telemetry_decom/packet_bindings";
const expected = {
  scope: "spacecraft",
  organizationId: "org",
  missionId: "mission",
  spacecraftId: "spacecraft",
};
const endpoint = { id: "endpoint-1", label: "Primary downlink" };
function packet(index = 0) {
  return {
    id: `packet-${index}`,
    name: `HEALTH ${index}`,
    apid: index,
    field_count: 2,
    compatible_field_count: 1,
    selectable: true,
    detail_href: base + `?page=1&packet=packet-${index}`,
  };
}
function document(): PacketDocument {
  return {
    contract_version: 1,
    context: {
      organization_id: "org",
      mission_id: "mission",
      spacecraft_id: "spacecraft",
      actor_id: "user",
      installation_id: "installation",
    },
    spacecraft_name: "Nova",
    review_token: "a".repeat(64),
    query: { page: 1, endpoint_page: 1, resource_page: 1, q: "", endpoint_q: "", packet: "" },
    configuration: {
      id: null,
      version: 0,
      catalog_revision_id: "revision-1",
      catalog_label: "Flight bus",
      catalog_version: 1,
      enabled: true,
    },
    input: { id: "telemetry-fields", version: 1, minimum: 1, maximum: 512 },
    selection: { ids: [], total_count: 0, complete: true, unavailable_ids: [], endpoint: null },
    summary: {
      packet_count: 1,
      selected_count: 0,
      compatible_packet_count: 1,
      selected_field_count: 0,
    },
    packets: {
      items: [packet()],
      page: 1,
      page_size: 25,
      total_count: 1,
      previous_href: null,
      next_href: null,
    },
    endpoints: {
      items: [endpoint],
      page: 1,
      page_size: 25,
      total_count: 1,
      previous_href: null,
      next_href: null,
    },
    detail: null,
    status: "configured",
    links: { self: base, manage: base.replace(/packet_bindings$/, "manage") },
  };
}
function receipt(input: SelectionInput) {
  return {
    receiptId: "receipt-1",
    completedAt: "2026-09-09T00:00:00Z",
    result: {
      configurationId: "configuration-1",
      configurationVersion: 1,
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      inputId: "telemetry-fields",
      inputVersion: 1,
      enabled: true,
      selectedPacketIds: input.selected_packet_ids,
      bindingCount: input.selected_packet_ids.length,
    },
  };
}
function saved(p: PacketDocument, input: SelectionInput): PacketDocument {
  const next = structuredClone(p);
  required(next.configuration).id = "configuration-1";
  required(next.configuration).version = 1;
  next.review_token = "b".repeat(64);
  next.selection = {
    ...next.selection,
    ids: input.selected_packet_ids,
    total_count: input.selected_packet_ids.length,
    endpoint,
  };
  next.summary.selected_count = input.selected_packet_ids.length;
  next.summary.selected_field_count = input.selected_packet_ids.length;
  return next;
}
function port(p: PacketDocument): PacketPort {
  return {
    read: vi.fn().mockResolvedValue(p),
    save: vi.fn<PacketPort["save"]>().mockImplementation(async (input) => receipt(input)),
    navigate: vi.fn(),
  };
}
function render(p = document(), bridge = port(p)) {
  return mount(PacketBindingsSurface, {
    props: { document: p, hostContext: expected, port: bridge },
  });
}
async function choose(w: ReturnType<typeof render>) {
  await w.get("#packet-source-endpoint").setValue(endpoint.id);
  await w.get("#packet-select-packet-0").setValue(true);
}
beforeEach(() => {
  sessionStorage.clear();
  vi.unstubAllGlobals();
});

test("admits scoped packet evidence and rejects malformed identities, counts and navigation", () => {
  const p = document();
  expect(admitPacketDocument(p, expected)).toEqual(p);
  for (const change of [
    (x: unknown) => (fixtureRecordAt(x).contract_version = 2),
    (x: unknown) => (fixtureRecordAt(x, "context").mission_id = "other"),
    (x: unknown) => (fixtureRecordAt(x).review_token = "bad"),
    (x: unknown) =>
      fixtureArrayAt(x, "packets", "items").push(fixtureArrayAt(x, "packets", "items")[0]),
    (x: unknown) =>
      (fixtureRecordAt(x, "packets", "items", 0).detail_href = "https://foreign.test/"),
    (x: unknown) => (fixtureRecordAt(x, "summary").selected_count = 3),
    (x: unknown) => (fixtureRecordAt(x, "input").maximum = 1000),
    (x: unknown) => (fixtureRecordAt(x, "selection").ids = ["unknown"]),
    (x: unknown) => (fixtureRecordAt(x, "endpoints").next_href = base + "?mission_id=foreign"),
  ]) {
    const bad = structuredClone(p);
    change(bad);
    expect(admitPacketDocument(bad, expected)).toBeNull();
    const w = render(bad);
    expect(w.find("#packet-bindings-contract-unavailable").exists()).toBe(true);
    expect(w.find("#save-packet-bindings").exists()).toBe(false);
    w.unmount();
  }
});

test("selection is local, clearing the endpoint persists, and save carries exact review and version evidence", async () => {
  const p = document(),
    bridge = port(p),
    w = render(p, bridge);
  await choose(w);
  expect(bridge.save).not.toHaveBeenCalled();
  await w.get("#packet-source-endpoint").setValue("");
  expect(w.get("#save-packet-bindings").attributes("disabled")).toBeDefined();
  await w.get("#refresh-packet-bindings").trigger("click");
  await flushPromises();
  expect((w.get("#packet-source-endpoint").element as HTMLSelectElement).value).toBe("");
  await w.get("#packet-source-endpoint").setValue(endpoint.id);
  vi.mocked(bridge.save).mockImplementation(async (input) => {
    vi.mocked(bridge.read).mockResolvedValue(saved(p, input));
    return receipt(input);
  });
  await w.get("#save-packet-bindings").trigger("click");
  await flushPromises();
  const [input, key] = required(vi.mocked(bridge.save).mock.calls[0]);
  expect(key).toMatch(/^[a-f0-9-]{36}$/);
  expect(input).toEqual({
    expected_review: p.review_token,
    expected_configuration_version: 0,
    input_id: "telemetry-fields",
    input_version: 1,
    catalog_revision_id: "revision-1",
    source_endpoint_ref: endpoint.id,
    selected_packet_ids: ["packet-0"],
  });
  expect(w.get("#packet-save-receipt").text()).toContain("receipt-1");
  expect(w.find("#packet-bindings-pending").exists()).toBe(false);
  // A later read must not reuse the previous receipt to erase a new draft.
  await w.get("#packet-select-packet-0").setValue(false);
  await w.get("#refresh-packet-bindings").trigger("click");
  await flushPromises();
  expect((w.get("#packet-select-packet-0").element as HTMLInputElement).checked).toBe(false);
  w.unmount();
});

test("drafts survive packet-page remounts and are isolated by actor", async () => {
  const first = document();
  first.packets = {
    ...first.packets,
    items: Array.from({ length: 25 }, (_, i) => packet(i)),
    total_count: 26,
    next_href: base + "?page=2",
  };
  first.summary.packet_count = 26;
  first.summary.compatible_packet_count = 26;
  const bridge = port(first);
  const w = render(first, bridge);
  await choose(w);
  await w.get('nav[aria-label="Packet pages"] a').trigger("click");
  expect(bridge.navigate).toHaveBeenCalledWith(base + "?page=2");
  w.unmount();
  const second = structuredClone(first);
  second.query.page = 2;
  second.packets = {
    ...second.packets,
    items: [packet(25)],
    page: 2,
    previous_href: base + "?page=1",
    next_href: null,
  };
  const next = render(second, bridge);
  await next.get("#packet-select-packet-25").setValue(true);
  await next.get("#save-packet-bindings").trigger("click");
  await flushPromises();
  expect(required(vi.mocked(bridge.save).mock.calls[0])[0].selected_packet_ids).toEqual([
    "packet-0",
    "packet-25",
  ]);
  next.unmount();
  const other = structuredClone(first);
  other.context.actor_id = "other-user";
  const isolated = render(other);
  expect((isolated.get("#packet-select-packet-0").element as HTMLInputElement).checked).toBe(false);
  isolated.unmount();
});

test("changed configuration evidence preserves the draft and requires explicit review", async () => {
  const p = document(),
    bridge = port(p),
    w = render(p, bridge);
  await choose(w);
  const changed = structuredClone(p);
  changed.review_token = "c".repeat(64);
  await w.setProps({ document: changed });
  expect((w.get("#packet-select-packet-0").element as HTMLInputElement).checked).toBe(true);
  expect(w.get("#save-packet-bindings").attributes("disabled")).toBeDefined();
  expect(w.find("#packet-bindings-stale").exists()).toBe(true);
  vi.stubGlobal("confirm", () => true);
  await w.get("#review-current-packets").trigger("click");
  expect(w.find("#packet-bindings-stale").exists()).toBe(false);
  expect((w.get("#packet-select-packet-0").element as HTMLInputElement).checked).toBe(false);
  w.unmount();
});

test("a lost response survives remount and recovery reuses the exact key and input", async () => {
  const p = document(),
    bridge = port(p);
  vi.mocked(bridge.save).mockRejectedValueOnce(new Error("response lost"));
  const w = render(p, bridge);
  await choose(w);
  await w.get("#save-packet-bindings").trigger("click");
  await flushPromises();
  const first = vi.mocked(bridge.save).mock.calls[0];
  expect(w.find("#packet-bindings-pending").exists()).toBe(true);
  expect(w.get("#save-packet-bindings").attributes("disabled")).toBeDefined();
  w.unmount();
  const recovered = render(p, bridge);
  vi.mocked(bridge.save).mockRejectedValueOnce(
    Object.assign(new Error("permission changed"), { code: "forbidden" }),
  );
  await recovered.get("#recover-packet-save").trigger("click");
  await flushPromises();
  expect(recovered.find("#packet-bindings-pending").exists()).toBe(true);
  expect(vi.mocked(bridge.save).mock.calls[1]).toEqual(first);
  vi.mocked(bridge.read).mockResolvedValue(saved(p, required(first)[0]));
  await recovered.get("#recover-packet-save").trigger("click");
  await flushPromises();
  expect(vi.mocked(bridge.save).mock.calls[2]).toEqual(first);
  expect(recovered.find("#packet-bindings-pending").exists()).toBe(false);
  expect(recovered.get("#packet-save-receipt").text()).toContain("receipt-1");
  recovered.unmount();
});

test("a legacy selection exceeding the binding limit requires explicit replacement", async () => {
  const p = document();
  p.selection = {
    ...p.selection,
    ids: Array.from({ length: 512 }, (_, i) => `packet-${i}`),
    total_count: 530,
    complete: false,
    endpoint,
  };
  p.summary.selected_count = 530;
  const bridge = port(p),
    w = render(p, bridge);
  expect(w.find("#packet-selection-incomplete").exists()).toBe(true);
  expect(w.get("#save-packet-bindings").attributes("disabled")).toBeDefined();
  vi.stubGlobal("confirm", vi.fn().mockReturnValue(false));
  await w.get("#packet-selection-incomplete button").trigger("click");
  expect(w.find("#packet-selection-incomplete").exists()).toBe(true);
  vi.stubGlobal("confirm", vi.fn().mockReturnValue(true));
  await w.get("#packet-selection-incomplete button").trigger("click");
  expect(w.find("#packet-selection-incomplete").exists()).toBe(false);
  expect(bridge.save).not.toHaveBeenCalled();
  await w.get("#packet-select-packet-0").setValue(true);
  await w.get("#save-packet-bindings").trigger("click");
  await flushPromises();
  expect(required(vi.mocked(bridge.save).mock.calls[0])[0].selected_packet_ids).toEqual([
    "packet-0",
  ]);
  w.unmount();
});

test("unavailable tab storage prevents an effect whose response could not be recovered", async () => {
  const p = document(),
    bridge = port(p);
  p.selection = { ...p.selection, ids: ["packet-0"], total_count: 1, endpoint };
  p.summary.selected_count = 1;
  const w = render(p, bridge);
  const failure = vi.spyOn(window.sessionStorage, "setItem").mockImplementation(() => {
    throw Error("full");
  });
  await w.get("#save-packet-bindings").trigger("click");
  expect(w.find("#packet-bindings-storage-error").exists()).toBe(true);
  expect(bridge.save).not.toHaveBeenCalled();
  failure.mockRestore();
  w.unmount();
});

const producer = producerFixture("CADENCE_PACKET_PAGE", import.meta.url);
test.skipIf(!producer.available)(
  "producer supplied packet configuration reaches the public feature and yields its explicit save input",
  async () => {
    const p = JSON.parse(producer.read()) as PacketDocument;
    expect(admitPacketDocument(p)).not.toBeNull();
    const bridge = port(p);
    vi.mocked(bridge.save).mockRejectedValue(new Error("capture only"));
    const w = mount(PacketBindingsSurface, { props: { document: p, port: bridge } });
    const first = required(p.packets.items.find((p) => p.selectable));
    await required(
      w.findAll("[data-packet-id]").find((row) => row.attributes("data-packet-id") === first.id),
    )
      .get("input[type=checkbox]")
      .setValue(true);
    if (!p.selection.endpoint)
      await w.get("#packet-source-endpoint").setValue(required(p.endpoints.items[0]).id);
    await w.get("#save-packet-bindings").trigger("click");
    await flushPromises();
    expect(bridge.save).toHaveBeenCalledTimes(1);
    process.stdout.write(
      "CADENCE_PACKET_INPUT=" +
        JSON.stringify(required(vi.mocked(bridge.save).mock.calls[0])[0]) +
        "\n",
    );
    w.unmount();
  },
);
