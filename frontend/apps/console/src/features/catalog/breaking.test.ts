import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { modelRevisionReader } from "./approval/api.ts";
import { breakingWords, importBreaking, revisionBreaking, type Breaking } from "./breaking.ts";

const summary = (breaking: number | null) => ({
  summary: {
    commands: null,
    telemetry: null,
    unchanged: 0,
    total_before: 0,
    breaking,
  },
  changes: [],
  truncated: false,
});
const base = { id: "cr-3", number: 3 };

describe("importBreaking (#364: the import page's C3 never reads unknown as 0)", () => {
  it("takes the diff's count against its base", () => {
    expect(importBreaking({ base_revision: base, diff: summary(2) })).toEqual({
      kind: "count",
      count: 2,
      base: 3,
    });
    expect(importBreaking({ base_revision: base, diff: summary(0) })).toEqual({
      kind: "count",
      count: 0,
      base: 3,
    });
  });

  it("no base is the database's first revision (the server sends a diff only with a base)", () => {
    expect(importBreaking({ base_revision: null, diff: null })).toEqual({ kind: "first" });
  });

  it("a base with no diff, or a diff with no count, is uncompared, not 0", () => {
    expect(importBreaking({ base_revision: base, diff: null })).toEqual({
      kind: "uncompared",
      base: 3,
    });
    expect(importBreaking({ base_revision: base, diff: summary(null) })).toEqual({
      kind: "uncompared",
      base: 3,
    });
  });
});

describe("revisionBreaking (#195's revision read, U102)", () => {
  const cr = { import_run_id: "run-4" };

  it("reads the three states the server sends", () => {
    expect(
      revisionBreaking({
        ...cr,
        breaking: 3,
        breaking_base: { catalog_revision_id: "cr-3", revision: 3 },
      }),
    ).toEqual({ kind: "count", count: 3, base: 3 });
    expect(revisionBreaking({ ...cr, breaking: null, breaking_base: null })).toEqual({
      kind: "first",
    });
    expect(
      revisionBreaking({
        ...cr,
        breaking: null,
        breaking_base: { catalog_revision_id: "cr-3", revision: 3 },
      }),
    ).toEqual({ kind: "uncompared", base: 3 });
  });

  it("a server without the fields reads as not known, with no link", () => {
    expect(revisionBreaking({})).toEqual({ kind: "unknown", importRunId: null });
  });

  it("decodes from the revision read, and without the fields", () => {
    const wire = (extra: Record<string, unknown>) => ({
      id: "mm-4",
      status: "candidate",
      imported_at: null,
      imported_by: null,
      catalog_revision: { id: "cr-4", number: 4, label: null, database_id: "db-1", ...extra },
      decision: null,
      viewer_can_decide: true,
      viewer_is_importer: false,
      cannot_decide_because: null,
      plans_ready: true,
      comparison: null,
    });
    const read = (extra: Record<string, unknown>) => {
      const r = decode(modelRevisionReader, wire(extra));
      if (!r.ok) throw new Error(r.error.message);
      if (!r.value.catalog_revision) throw new Error("no catalog revision");
      return revisionBreaking(r.value.catalog_revision);
    };
    expect(
      read({
        import_run_id: "run-4",
        breaking: 1,
        breaking_base: { catalog_revision_id: "cr-3", revision: 3 },
      }),
    ).toEqual({ kind: "count", count: 1, base: 3 });
    expect(read({ import_run_id: "run-1", breaking: null, breaking_base: null })).toEqual({
      kind: "first",
    });
    expect(read({})).toEqual({ kind: "unknown", importRunId: null });
  });
});

describe("breakingWords (U102 as amended by #363)", () => {
  const words = (b: Breaking, rev = 4) => breakingWords(b, rev);

  it("a known 0 needs nothing; every other state needs the acknowledgment", () => {
    const zero: Breaking = { kind: "count", count: 0, base: 3 };
    expect(words(zero)).toBeNull();
    for (const b of [
      { kind: "count", count: 1, base: 3 },
      { kind: "first" },
      { kind: "uncompared", base: 3 },
      { kind: "unknown", importRunId: null },
    ] satisfies Breaking[]) {
      expect(words(b)).not.toBeNull();
    }
  });

  it("singular and plural counts, with what they were compared against", () => {
    expect(words({ kind: "count", count: 1, base: 14 }, 15)).toEqual({
      line: "Rev 15 changes 1 command or point in a way that breaks existing use, compared with rev 14. Cadence can't tell yet what uses it.",
      checkbox: "I've checked the breaking change",
      reason: "Check the breaking change first.",
    });
    expect(words({ kind: "count", count: 3, base: 3 })).toEqual({
      line: "Rev 4 changes 3 commands or points in a way that breaks existing use, compared with rev 3. Cadence can't tell yet what uses them.",
      checkbox: "I've checked the 3 breaking changes",
      reason: "Check the 3 breaking changes first.",
    });
  });

  it("the first revision of a catalog", () => {
    expect(words({ kind: "first" }, 1)).toEqual({
      line: "Rev 1 is the first revision of this catalog, so Cadence has nothing earlier to compare it with and can't tell what it breaks. Check what uses its commands and points before you stage.",
      checkbox: "I've checked what rev 1 changes",
      reason: "Check what rev 1 changes first.",
    });
  });

  it("the import page's own line when its diff couldn't be read (no link)", () => {
    expect(words({ kind: "uncompared", base: 3 })).toEqual({
      line: "Cadence couldn't compare rev 4 with rev 3, so this page can't show whether it breaks anything in use. Check what uses its commands and points before you stage.",
      checkbox: "I've checked what rev 4 changes",
      reason: "Check what rev 4 changes first.",
    });
  });

  it("a revision's page without a count points to its import's diff", () => {
    expect(words({ kind: "unknown", importRunId: "run-4" })).toEqual({
      line: "This page can't show whether rev 4 breaks anything in use. Check its import's diff before you stage.",
      checkbox: "I've checked rev 4's diff",
      reason: "Check rev 4's diff first.",
    });
  });
});
