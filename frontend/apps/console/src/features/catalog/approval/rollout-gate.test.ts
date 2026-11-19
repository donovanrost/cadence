import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { modelRevisionReader } from "./api.ts";
import { rolloutGate } from "./rollout-gate.ts";

const cr = { id: "cr-4", number: 4, label: null, database_id: "db-1" };
function read(o: Record<string, unknown>) {
  const r = decode(modelRevisionReader, {
    id: "mm-4",
    status: "candidate",
    imported_at: null,
    imported_by: null,
    catalog_revision: cr,
    decision: null,
    viewer_can_decide: false,
    viewer_is_importer: false,
    cannot_decide_because: null,
    plans_ready: true,
    comparison: null,
    ...o,
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
}

describe("rolloutGate (U102 'Where', #195)", () => {
  it("offers C3 for an approved revision, for its catalog revision", () => {
    expect(rolloutGate(read({ status: "approved" }))).toEqual({
      kind: "rollout",
      revision: { id: "cr-4", number: 4 },
      catalogRevision: cr,
    });
  });

  it("says why in C3's place while it waits for approval, or once it's rejected", () => {
    expect(rolloutGate(read({ status: "candidate" }))).toEqual({
      kind: "line",
      line: "Spacecraft can't move to rev 4 until it's approved.",
    });
    expect(rolloutGate(read({ status: "rejected" }))).toEqual({
      kind: "line",
      line: "Rev 4 was rejected, so spacecraft can't move to it. To try again, correct the catalog and import the corrected file.",
    });
  });

  it("says a retired revision can't be moved to, and that those on it keep it (#392)", () => {
    expect(rolloutGate(read({ status: "retired" }))).toEqual({
      kind: "line",
      line: "Rev 4 is retired, so spacecraft can't move to it. Any already on it keep it.",
    });
  });

  it("has no C3 and no line without a catalog revision, or for an unknown status (U99, #392)", () => {
    expect(rolloutGate(read({ status: "approved", catalog_revision: null }))).toEqual({
      kind: "none",
    });
    expect(rolloutGate(read({ status: "superseded" }))).toEqual({ kind: "none" });
  });
});
