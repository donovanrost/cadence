import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { importRunReader, rolloutTarget } from "./importRun.ts";

const run = (diff: unknown) => ({
  id: "catalog_import_run_1",
  status: "succeeded",
  started_at: "2026-11-10T10:00:00Z",
  completed_at: "2026-11-10T10:00:04Z",
  file: { name: "earendil.xtce", format_label: "XTCE", size_bytes: 1024 },
  failure_reason: null,
  declaration_count: 547,
  diagnostics: [],
  revision: { id: "rev3", number: 3, label: null, composition_id: "comp3" },
  base_revision: { id: "rev2", number: 2 },
  diff,
  permissions: [],
});

describe("rolloutTarget (C3 pins the revision's composition; D3, #544)", () => {
  const read = (revision: unknown) => {
    const r = decode(importRunReader, { ...run(null), revision });
    if (!r.ok) throw new Error(r.error.message);
    return r.value;
  };

  it("is the revision and its composition", () => {
    expect(
      rolloutTarget(read({ id: "rev3", number: 3, label: null, composition_id: "comp3" })),
    ).toEqual({
      id: "rev3",
      number: 3,
      compositionId: "comp3",
    });
  });

  it("is null without a revision, or without a composition to pin", () => {
    expect(rolloutTarget(read(null))).toBeNull();
    expect(
      rolloutTarget(read({ id: "rev3", number: 3, label: null, composition_id: null })),
    ).toBeNull();
  });
});

describe("importRunReader diff (api cab661fe)", () => {
  it("reads added/removed items with a null change, and truncated", () => {
    const r = decode(
      importRunReader,
      run({
        summary: {
          commands: { before: 10, after: 11, added: 1, changed: 3, removed: 0 },
          telemetry: { before: 5, after: 5, added: 0, changed: 0, removed: 0 },
          unchanged: 11,
          total_before: 15,
          breaking: 0,
        },
        changes: [
          { op: "added", kind: "command", name: "/commands/PING", change: null, breaking: false },
          {
            op: "changed",
            kind: "command",
            name: "/commands/SET_MODE",
            change: "verifiers/Accepted on board: added (+1 more)",
            breaking: false,
          },
        ],
        truncated: true,
      }),
    );
    if (!r.ok) throw r.error;
    expect(r.value.diff?.changes[0]?.change).toBeNull();
    expect(r.value.diff?.truncated).toBe(true);
    expect(r.value.base_revision?.number).toBe(2);
  });
});

describe("kindTile (Catalog.md C1 strip)", () => {
  it("shows before→after with +added ~changed −removed, or no changes", async () => {
    const { kindTile } = await import("./importRun.ts");
    expect(kindTile({ before: 212, after: 218, added: 7, changed: 4, removed: 1 })).toEqual({
      value: "212→218",
      caption: "+7 ~4 −1",
    });
    expect(kindTile({ before: 27, after: 27, added: 0, changed: 3, removed: 0 })).toEqual({
      value: "27",
      caption: "~3",
    });
    expect(kindTile({ before: 5, after: 5, added: 0, changed: 0, removed: 0 }).caption).toBe(
      "no changes",
    );
  });
});
