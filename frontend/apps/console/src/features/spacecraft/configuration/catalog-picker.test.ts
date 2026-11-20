import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId, spacecraftId } from "@/api/index.ts";
import { snapshotReader, type ConfigurationSnapshot } from "./api.ts";
import CatalogField from "./CatalogField.vue";
import { droppedApidsLine, rowState } from "./catalog-words.ts";
import { snapshotWire } from "./fixtures.ts";

/** #595b (U94, U65; mms-ux): choosing the draft's catalog revision. */
type Packets = typeof import("./api.ts").fetchPacketChoices;
const packets = vi.hoisted(() => ({ fn: vi.fn<Packets>() }));
vi.mock("./api.ts", async (original) => ({
  ...(await original<typeof import("./api.ts")>()),
  fetchPacketChoices: (...args: Parameters<Packets>) => packets.fn(...args),
}));
afterEach(() => packets.fn.mockReset());

const row = (id: string, number: number, approval_status?: string) => ({
  id,
  name: "EARENDIL FSW",
  label: `FSW 2.${number}`,
  number,
  declarations: 812,
  packets: 40,
  commands: 120,
  ...(approval_status === undefined ? {} : { approval_status }),
});
const snap = (o: Record<string, unknown> = {}): ConfigurationSnapshot => {
  const r = decode(snapshotReader, snapshotWire(o));
  if (!r.ok) throw r.error;
  return r.value;
};
const firstRow = (s: ConfigurationSnapshot) => {
  const c = s.catalogs[0];
  if (!c) throw new Error("fixture row");
  return c;
};
const stubs = { RouterLink: { template: "<a><slot /></a>" } };
const workspace = {
  missionId: missionId("m1"),
  spacecraftId: spacecraftId("spacecraft-earendil-004"),
  section: "catalog" as const,
};

describe("the picker's words", () => {
  it("tags rows by approval: waiting can be chosen, the rest can't, unknown says so", () => {
    expect(rowState(firstRow(snap({ catalogs: [row("a", 1, "candidate")] })), null)).toMatchObject({
      choosable: true,
      tag: { label: "Waiting" },
      line: "Not approved yet. The draft can be saved, but not sent until it's approved.",
    });
    const rejected = firstRow(snap({ catalogs: [row("a", 1, "rejected")] }));
    expect(rowState(rejected, null)).toMatchObject({
      choosable: false,
      line: "Rejected, so spacecraft can't move to it.",
    });
    const odd = firstRow(snap({ catalogs: [row("a", 1, "quarantined")] }));
    expect(rowState(odd, null)).toMatchObject({
      choosable: false,
      line: "Can't be chosen.",
      technical: "quarantined",
    });
    const active = firstRow(snap({ catalogs: [row("a", 1, "approved")] }));
    expect(rowState(active, "a").tag?.label).toBe("Active");
  });

  it("says which handled APIDs a revision doesn't define, up to 5, capitalised", () => {
    expect(droppedApidsLine("catalog rev 15", [257, 416])).toBe(
      "Catalog rev 15 doesn't define 0x101 and 0x1A0, so they're removed from Handled APIDs. Discard edits brings them back.",
    );
    expect(droppedApidsLine("catalog rev 15", [1, 2, 3, 4, 5, 6, 7])).toContain(
      "0x01, 0x02, 0x03, 0x04, 0x05 and 2 more, so they're",
    );
    expect(droppedApidsLine("catalog rev 15", [])).toBeNull();
  });
});

describe("the catalog revision field", () => {
  const mountField = (s: ConfigurationSnapshot) =>
    mount(CatalogField, {
      props: { workspace, snapshot: s, doc: s.document },
      global: { stubs },
      attachTo: document.body,
    });
  const button = (w: ReturnType<typeof mountField>, label: string) =>
    w.findAll("button").find((b) => b.text().startsWith(label));

  it("turns Change… off with U94's reason and Open profile when the profile sets it", () => {
    const w = mountField(snap({ catalog_set_by: "profile", profile: { id: "p1", name: "Bus A" } }));
    const change = button(w, "Change…");
    expect(change?.attributes("aria-disabled")).toBe("true");
    expect(change?.text()).toContain("EARENDIL-004's profile sets its catalog revision.");
    expect(w.text()).toContain("Open profile");
    w.unmount();
  });

  it("chooses another revision and drops the APIDs it doesn't define", async () => {
    packets.fn.mockResolvedValue({
      ok: true,
      value: {
        catalog_id: "cr-15",
        catalog_number: 15,
        packets: [{ apid: 42, name: "BUS_HK", definitions: 2 }],
      },
    });
    const s = snap({
      catalogs: [
        row("cr-14", 14, "approved"),
        row("cr-15", 15, "candidate"),
        row("cr-13", 13, "retired"),
      ],
    });
    const w = mountField(s);
    await button(w, "Change…")?.trigger("click");
    const radios = w.findAll("input[type=radio]");
    // Newest first; the retired one can't be chosen.
    expect(radios.map((r) => r.attributes("value"))).toEqual(["cr-15", "cr-14", "cr-13"]);
    expect(radios[2]?.attributes("disabled")).toBeDefined();
    expect(button(w, "Choose")?.text()).toContain("Pick a different catalog revision first.");
    await radios[0]?.setValue(true);
    await flushPromises();
    expect(w.text()).toContain(
      "Catalog rev 15 doesn't define 0x2B, so it's removed from Handled APIDs. Discard edits brings it back.",
    );
    await button(w, "Choose")?.trigger("click");
    expect(w.emitted("edit")?.[0]).toEqual([{ catalog_revision_id: "cr-15", handled_apids: [42] }]);
    w.unmount();
  });
});
