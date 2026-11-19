import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { previewReader } from "./actions.ts";
import { conflictOps, conflictRow } from "./rebase.ts";

describe("conflictOps", () => {
  it("collects op ids flagged by the Conflicts check only", () => {
    const p = decode(previewReader, {
      verdict: "no_go",
      checks: [
        {
          key: "conflicts",
          verdict: "no_go",
          items: [{ kind: "spacecraft_profile", op_id: "op_1" }],
        },
        { key: "validation", verdict: "go", items: [{ kind: "spacecraft", op_id: "op_2" }] },
      ],
      effects: [],
    });
    if (!p.ok) throw p.error;
    expect([...conflictOps(p.value).keys()]).toEqual(["op_1"]);
    expect(conflictOps(null).size).toBe(0);
  });
});

describe("conflictRow (ux K1)", () => {
  const path = (label: string, base: unknown, live: unknown, staged: unknown) => ({
    path: label.toLowerCase(),
    label,
    unit: "bytes",
    format: null,
    base,
    live,
    staged,
    changed_in: 9,
    changed_by: { name: "Mira K." },
  });
  const item = (paths: unknown[]) => {
    const p = decode(previewReader, {
      verdict: "no_go",
      checks: [
        {
          key: "conflicts",
          verdict: "no_go",
          items: [{ kind: "spacecraft_profile", op_id: "op_1", paths }],
        },
      ],
      effects: [],
    });
    if (!p.ok) throw p.error;
    return p.value.checks[0]?.items ?? [];
  };
  it("says the precise fact for one field and labels the buttons with values", () => {
    const row = conflictRow(item([path("TM frame length", 900, 1200, 1115)]), "r8");
    expect(row.lines).toEqual([
      "TM frame length is 1,200 bytes now, not 900 bytes as r8 left it (changed in r9 by Mira K.). You staged 1,115 bytes.",
    ]);
    expect([row.keep, row.take]).toEqual(["Keep 1,115 bytes", "Take 1,200 bytes"]);
    expect(row.seeChecks).toBe(false);
  });
  it("counts three or more fields and points at the Conflicts check", () => {
    const row = conflictRow(
      item([path("A", 1, 2, 3), path("B", 1, 2, 3), path("C", 1, 2, 3)]),
      "r8",
    );
    expect(row).toMatchObject({
      lines: ["3 fields changed in live since this was staged"],
      seeChecks: true,
      keep: "Keep mine",
      take: "Take live",
    });
  });
});
