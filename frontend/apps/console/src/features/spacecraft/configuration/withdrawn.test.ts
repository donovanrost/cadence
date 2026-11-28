import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { compositionReader, type Composition } from "@/features/catalog/composition.ts";
import { snapshotReader } from "./api.ts";
import { snapshotWire } from "./fixtures.ts";
import WithdrawnApprovalLine from "./WithdrawnApprovalLine.vue";
import {
  approvalWithdrawnKey,
  approvalWithdrawnReader,
  compositionName,
  withdrawnRecord,
  withdrawnStateLine,
  type ApprovalWithdrawn,
} from "./withdrawn.ts";

/** E2b (#546, #924; U109): the craft state line for a withdrawn or rejected approval. */
const layer = (id: string, n: number) => ({
  layer_id: id,
  mount: id === "a" ? "/" : `/${id}`,
  catalog_revision: { id: `cr-${id}`, number: n, database: { id: `db-${id}`, name: `DB ${id}` } },
});
const comp = (layers: unknown[], number: number | null = 3): Composition => {
  const r = decode(compositionReader, {
    composition_id: "mission_model_composition:abc",
    number,
    imported_layers: layers,
    created_by: null,
    created_at: "2026-11-20T09:00:00Z",
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
};
const composed = comp([layer("a", 4), layer("b", 7)]);
const oneCatalog = comp([layer("a", 4)]);

const ana = { kind: "user", id: "u-ana", name: "Ana R." };
const withdrawn = (
  decision: Record<string, unknown> = {},
  extra: Record<string, unknown> = {},
): ApprovalWithdrawn => {
  const r = decode(approvalWithdrawnReader, {
    earlier_approved: null,
    ...extra,
    revision_id: "mission_model_revision:r3",
    decision: {
      kind: "withdrawn",
      by: ana,
      at: "2026-11-20T09:12:00Z",
      reason: "Wrong TM table",
      ...decision,
    },
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
};

describe("approval_withdrawn decoder", () => {
  it("reads an approved craft (null) and refuses a read without the key", () => {
    expect(decode(approvalWithdrawnKey, undefined).ok).toBe(false);
    expect(decode(approvalWithdrawnKey, null)).toEqual({ ok: true, value: null });
  });

  it("keeps a decision kind it doesn't know instead of failing the read", () => {
    expect(withdrawn({ kind: "revoked" }).decision.kind).toEqual({ unrecognized: "revoked" });
  });

  it("reads an earlier approved version with no catalog revision recorded (#999)", () => {
    const earlier = { revision_id: "mission_model_revision:r2", catalog_revision: null };
    expect(withdrawn({}, { earlier_approved: earlier }).earlier_approved).toEqual(earlier);
  });
});

describe("compositionName (U109)", () => {
  it("names a composition, one catalog by its revision, and never an id", () => {
    expect(compositionName(composed)).toBe("composition 3");
    expect(compositionName(oneCatalog)).toBe("catalog rev 4");
    expect(compositionName(comp([layer("a", 4), layer("b", 7)], null))).toBe("this composition");
    expect(compositionName(null)).toBe("this composition");
  });
});

describe("withdrawnStateLine (U109's caution words)", () => {
  it("says who withdrew it, when and why, and that the craft stays on it", () => {
    expect(withdrawnStateLine(withdrawn(), composed, "EARENDIL-004")).toBe(
      "Composition 3 is no longer approved: Ana R. withdrew its approval at 11-20 09:12Z: “Wrong TM table”. EARENDIL-004 stays on it until a new configuration is applied. Move it to an approved composition.",
    );
  });

  it("words a rejection, a missing name, and a missing reason", () => {
    expect(withdrawnStateLine(withdrawn({ kind: "rejected" }), oneCatalog, "EARENDIL-004")).toBe(
      "Catalog rev 4 is no longer approved: Ana R. rejected it at 11-20 09:12Z: “Wrong TM table”. EARENDIL-004 stays on it until a new configuration is applied. Move it to an approved composition.",
    );
    expect(
      withdrawnStateLine(withdrawn({ by: null, reason: null }), composed, "EARENDIL-004"),
    ).toBe(
      "Composition 3 is no longer approved: its approval was withdrawn at 11-20 09:12Z. EARENDIL-004 stays on it until a new configuration is applied. Move it to an approved composition.",
    );
    expect(
      withdrawnStateLine(withdrawn({ kind: "rejected", by: null }), composed, "EARENDIL-004"),
    ).toContain("is no longer approved: it was rejected at 11-20 09:12Z: “Wrong TM table”.");
    expect(withdrawnStateLine(withdrawn({ reason: "  " }), composed, "EARENDIL-004")).toContain(
      "withdrew its approval at 11-20 09:12Z. EARENDIL-004",
    );
  });

  it("names a service identity as one, and a craft without a name as this spacecraft", () => {
    const service = { kind: "service", id: "si-1", name: "ingest" };
    expect(withdrawnStateLine(withdrawn({ by: service }), composed, "  ")).toBe(
      "Composition 3 is no longer approved: ingest (a service identity) withdrew its approval at 11-20 09:12Z: “Wrong TM table”. This spacecraft stays on it until a new configuration is applied. Move it to an approved composition.",
    );
  });

  it("says only what's known for a decision kind it doesn't know (U20)", () => {
    expect(withdrawnStateLine(withdrawn({ kind: "revoked" }), composed, "EARENDIL-004")).toBe(
      "Composition 3 is no longer approved since 11-20 09:12Z. EARENDIL-004 stays on it until a new configuration is applied. Move it to an approved composition.",
    );
  });

  it("ends with U109's way out, by what the next staging would select", () => {
    const earlier = {
      revision_id: "mission_model_revision:r2",
      catalog_revision: { id: "cr-2", number: 2, label: "v2", database_id: "db-a" },
    };
    expect(
      withdrawnStateLine(withdrawn({}, { earlier_approved: earlier }), composed, "EARENDIL-004"),
    ).toBe(
      "Composition 3 is no longer approved: Ana R. withdrew its approval at 11-20 09:12Z: “Wrong TM table”. EARENDIL-004 stays on it until a new configuration is applied. Stage a new configuration to move it to composition 3's earlier approved version.",
    );
    expect(
      withdrawnStateLine(withdrawn({}, { earlier_approved: null }), oneCatalog, "EARENDIL-004"),
    ).toMatch(
      /stays on it until a new configuration is applied\. Move it to an approved composition\.$/,
    );
  });

  it("puts the revision and the decision's time under Technical details", () => {
    expect(withdrawnRecord(withdrawn())).toEqual([
      ["Revision", "mission_model_revision:r3"],
      ["Decided", "2026-11-20 09:12:00Z"],
    ]);
  });
});

describe("WithdrawnApprovalLine", () => {
  it("shows the caution line with its record, and nothing when the approval stands", () => {
    const w = mount(WithdrawnApprovalLine, {
      props: { withdrawn: withdrawn(), composition: composed, craft: "EARENDIL-004" },
    });
    expect(w.get('[role="status"]').text()).toContain("Composition 3 is no longer approved");
    expect(w.get("details").text()).toContain("mission_model_revision:r3");
    w.unmount();
    const none = mount(WithdrawnApprovalLine, {
      props: { withdrawn: null, composition: composed, craft: "EARENDIL-004" },
    });
    expect(none.html()).toBe("<!--v-if-->");
    none.unmount();
  });
});

describe("the workspace read's active.approval_withdrawn", () => {
  it("reads the withdrawal on the active configuration, and null when it's approved", () => {
    const active = { version: 3, generation: 9, document: snapshotWire().document };
    const sent = decode(
      snapshotReader,
      snapshotWire({
        active: {
          ...active,
          approval_withdrawn: {
            revision_id: "mission_model_revision:r3",
            earlier_approved: null,
            decision: { kind: "rejected", by: ana, at: "2026-11-20T09:12:00Z", reason: null },
          },
        },
      }),
    );
    expect(sent.ok && sent.value.active?.approval_withdrawn?.decision.kind).toBe("rejected");
    const approved = decode(
      snapshotReader,
      snapshotWire({ active: { ...active, approval_withdrawn: null } }),
    );
    expect(approved.ok && approved.value.active?.approval_withdrawn).toBeNull();
  });
});
