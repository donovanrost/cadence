import { mount } from "@vue/test-utils";
import { nextTick, ref, shallowRef } from "vue";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId, spacecraftId, type ApiError } from "@/api/index.ts";
import ApidChips from "./ApidChips.vue";
import { snapshotReader, type ConfigurationSnapshot, type WorkspaceKey } from "./api.ts";
import {
  conflictRows,
  discardQuestion,
  packetsOffReason,
  presetOf,
  saveRefusal,
  savedLine,
} from "./draft-words.ts";
import { documentWire, snapshotWire } from "./fixtures.ts";
import FramingFields from "./FramingFields.vue";
import { useConfigurationDraft } from "./useConfigurationDraft.ts";

/** #595a (U94; mms-ux): saving a spacecraft's configuration draft from the console. */
type Save = typeof import("./api.ts").saveDraft;
const save = vi.hoisted(() => ({ fn: vi.fn<Save>() }));
vi.mock("./api.ts", async (original) => ({
  ...(await original<typeof import("./api.ts")>()),
  saveDraft: (...args: Parameters<Save>) => save.fn(...args),
}));
afterEach(() => save.fn.mockReset());

const snap = (o: Record<string, unknown> = {}): ConfigurationSnapshot => {
  const r = decode(snapshotReader, snapshotWire(o));
  if (!r.ok) throw r.error;
  return r.value;
};
const framing = {
  downlink: "tm",
  uplink: "tc",
  frame_size: 1115,
  secondary_header_length: 0,
  insert_zone_length: 0,
  ocf_length: 4,
  truncated_primary_header: false,
};
const conflict = (code: string, details: unknown = null): ApiError => ({
  kind: "conflict",
  code,
  message: "x",
  details,
});

describe("the save words", () => {
  it("says what was saved and what stays active (U94; v0 has no number)", () => {
    expect(savedLine(snap())).toBe("Saved as v4. v3 stays active until v4 is activated.");
    expect(savedLine(snap({ active: null, saved_version: 1 }))).toBe(
      "Saved as v1. Nothing runs until it's activated.",
    );
    const v0 = snapshotWire().active;
    expect(savedLine(snap({ active: { ...v0, version: 0 } }))).toBe(
      "Saved as v4. The current configuration stays active until v4 is activated.",
    );
  });

  it("asks before discarding, by whether anything was saved (mms-ux)", () => {
    expect(discardQuestion(snap())).toBe("Discard your edits? The saved draft stays as it is.");
    expect(discardQuestion(snap({ saved_version: null }))).toBe(
      "Discard your edits? Nothing has been saved yet.",
    );
  });

  it("lists only what differs in Someone saved…", () => {
    const s = snap();
    const rows = conflictRows(s, s.document, { ...s.document, handled_apids: [42] });
    expect(rows).toEqual([
      { key: "apids", label: "Handled APIDs", saved: "0x2A, 0x2B", mine: "0x2A" },
    ]);
  });

  it("words U94's save refusals, the field errors under their fields, others by code", () => {
    const s = snap();
    expect(
      saveRefusal(conflict("spacecraft_catalog_set_by_profile"), s, s.document).openProfile,
    ).toBe(true);
    expect(saveRefusal(conflict("spacecraft_catalog_set_by_profile"), s, s.document).text).toBe(
      "Not saved: EARENDIL-004's profile sets its catalog revision. Change it on the profile, through Setup › Changes.",
    );
    expect(saveRefusal(conflict("spacecraft_catalog_unavailable"), s, s.document).text).toBe(
      "Not saved: catalog rev 14 isn't one of this mission's catalog revisions. Choose another.",
    );
    const invalid: ApiError = {
      kind: "invalid",
      code: "invalid_params",
      message: "x",
      details: { "document.protocol.frame_size": ["must be at most 2048"] },
    };
    expect(saveRefusal(invalid, s, s.document)).toEqual({
      text: "Not saved.",
      fields: { frame_size: "must be at most 2048" },
    });
    expect(saveRefusal(conflict("something_new"), s, s.document)).toEqual({
      text: "Not saved.",
      code: "something_new",
      fields: {},
    });
  });

  it("says why Add APID is off, and matches presets exactly", () => {
    const s = snap();
    expect(
      packetsOffReason(s, { ...s.document, catalog_revision_id: null }, { status: "ready" }),
    ).toBe("Choose a catalog revision first.");
    expect(
      packetsOffReason(s, s.document, { status: "failed", code: "spacecraft_catalog_unavailable" }),
    ).toBe("Catalog rev 14 isn't one of this mission's catalog revisions. Choose another.");
    const withPreset = snap({
      presets: [{ id: "p1", version: 2, name: "S-band", protocol: framing }],
    });
    expect(presetOf(withPreset, withPreset.document.protocol)).toBe("p1");
    expect(
      presetOf(withPreset, { ...framing, ocf_length: 0, downlink: "tm", uplink: "tc" }),
    ).toBeNull();
  });
});

describe("the draft", () => {
  const key = ref<WorkspaceKey | null>({
    missionId: missionId("m1"),
    spacecraftId: spacecraftId("spacecraft-earendil-004"),
    section: "catalog",
  });

  it("saves the edited document with the snapshot's token, and shows the answer", async () => {
    const read = shallowRef<ConfigurationSnapshot | null>(snap());
    const refetch = vi.fn();
    const answer = snap({
      token: "t-2",
      saved_version: 5,
      document: documentWire({ handled_apids: [42] }),
    });
    save.fn.mockResolvedValue({ ok: true, value: answer });
    const d = useConfigurationDraft(key, () => read.value, refetch);
    d.edit({ handled_apids: [42] });
    expect(d.dirty.value).toBe(true);
    await d.save();
    const call = save.fn.mock.calls[0];
    expect(call?.[1]).toBe("t-1");
    expect(Object.keys(call?.[2] ?? {}).sort()).toEqual([
      "catalog_revision_id",
      "handled_apids",
      "protocol",
      "telemetry_source_endpoint_id",
    ]);
    expect(d.dirty.value).toBe(false);
    expect(d.snapshot.value?.token).toBe("t-2");
    expect(d.saved.value?.text).toBe("Saved as v5. v3 stays active until v5 is activated.");
    expect(refetch).toHaveBeenCalled();
  });

  it("keeps the edits on a stale token and opens Someone saved… over the newer read", async () => {
    const read = shallowRef<ConfigurationSnapshot | null>(snap());
    save.fn.mockResolvedValue({ ok: false, error: conflict("spacecraft_configuration_changed") });
    const d = useConfigurationDraft(key, () => read.value, vi.fn());
    d.edit({ handled_apids: [99] });
    await d.save();
    expect(d.failure.value).toBeNull();
    read.value = snap({ token: "t-9", document: documentWire({ handled_apids: [7] }) });
    await nextTick();
    expect(d.conflict.value?.handled_apids).toEqual([7]);
    expect(d.doc.value?.handled_apids).toEqual([99]);
    d.keepMine();
    expect(d.conflict.value).toBeNull();
    expect(d.dirty.value).toBe(true);
    d.useSaved();
    expect(d.doc.value?.handled_apids).toEqual([7]);
  });
});

describe("the editors", () => {
  it("names each chip's × and offers the catalog's other APIDs as '0x101 · EPS_HK'", () => {
    const w = mount(ApidChips, {
      props: {
        apids: [42],
        packets: {
          catalog_id: "cr-14",
          catalog_number: 14,
          packets: [
            { apid: 42, name: "BUS_HK", definitions: 3 },
            { apid: 257, name: "EPS_HK", definitions: 9 },
          ],
        },
        unavailable: null,
      },
    });
    expect(w.find("button[aria-label='Remove APID 0x2A']").exists()).toBe(true);
    const labels = w.findAll("option").map((o) => o.text());
    expect(labels).toContain("0x101 · EPS_HK");
    expect(labels).not.toContain("0x2A · BUS_HK");
  });

  it("reads Custom when the framing matches no preset, and counts unreadable sizes", async () => {
    const s = snap({ presets: [{ id: "p1", version: 2, name: "S-band", protocol: framing }] });
    const p = s.document.protocol;
    if (!p) throw new Error("fixture has framing");
    const w = mount(FramingFields, {
      props: { snapshot: s, protocol: { ...p, ocf_length: 0 }, errors: {} },
    });
    expect(w.findAll("option").map((o) => o.text())).toContain("Custom");
    await w.findAll("input")[0]?.setValue("11.5");
    expect(w.emitted("invalid")?.at(-1)).toEqual([1]);
    expect(w.emitted("change")).toBeUndefined();
  });
});
