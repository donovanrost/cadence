import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { snapshotJson } from "../fixtures.test-support.ts";
import { applyPush, liveSnapshot, viewPush, type LiveBoard } from "./live-merge.ts";
import { workspaceSnapshot } from "./snapshot.ts";

const base = (): LiveBoard => {
  const r = decode(workspaceSnapshot, snapshotJson());
  if (!r.ok) throw new Error("fixture");
  return { snapshot: r.value, version: r.value.document_version };
};
const push = (over: Record<string, unknown>) => {
  const s = snapshotJson();
  const r = decode(viewPush, {
    seq: 2,
    full: false,
    version: s.document_version,
    resolved_at: "2026-11-13T02:52:10Z",
    context: s.context,
    snapshot: null,
    placements: [],
    removed: [],
    ...over,
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};

describe("C1 view pushes", () => {
  it("replaces changed placements by id and keeps the rest in order", () => {
    const changed = { ...snapshotJson().placements[0], layout: { x: 0, y: 0, w: 12, h: 3 } };
    const r = applyPush(base(), push({ placements: [changed] }));
    expect(r.ok && r.board.snapshot?.placements.map((p) => [p.id, p.layout.w])).toEqual([
      ["battery", 12],
      ["gone", 4],
    ]);
  });

  it("drops removed placements", () => {
    const r = applyPush(base(), push({ removed: ["gone"] }));
    expect(r.ok && r.board.snapshot?.placements.map((p) => p.id)).toEqual(["battery"]);
  });

  it("refuses a delta for another version or with nothing on screen", () => {
    expect(applyPush(base(), push({ version: 99 }))).toEqual({
      ok: false,
      reason: "version_mismatch",
    });
    expect(applyPush(null, push({}))).toEqual({ ok: false, reason: "no_base" });
  });

  it("takes a full push as the whole snapshot", () => {
    const r = applyPush(null, push({ full: true, seq: 1, snapshot: snapshotJson() }));
    expect(r.ok && r.board.snapshot?.placements).toHaveLength(2);
  });

  it("takes a full push with no snapshot (never made current), and rejects a delta with one", () => {
    const s = snapshotJson();
    const raw = {
      seq: 1,
      version: 3,
      resolved_at: "2026-11-13T02:52:10Z",
      placements: [],
      removed: [],
    };
    const empty = decode(viewPush, { ...raw, full: true, snapshot: null, context: null });
    expect(empty.ok && applyPush(null, empty.value)).toEqual({
      ok: true,
      board: { snapshot: null, version: 3 },
    });
    expect(decode(viewPush, { ...raw, full: false, snapshot: s, context: s.context }).ok).toBe(
      false,
    );
    expect(decode(viewPush, { ...raw, full: false, snapshot: null, context: null }).ok).toBe(false);
  });
});

describe("which snapshot the board shows", () => {
  it("shows a push only when it is at least as new as the read's head (qa: lag after save)", () => {
    const b = base();
    expect(liveSnapshot(b, b.version)).toBe(b.snapshot);
    expect(liveSnapshot(b, b.version - 1)).toBe(b.snapshot);
    expect(liveSnapshot(b, b.version + 1)).toBeNull();
    expect(liveSnapshot(null, b.version)).toBeNull();
    expect(liveSnapshot({ snapshot: null, version: 9 }, null)).toBeNull();
  });
});
