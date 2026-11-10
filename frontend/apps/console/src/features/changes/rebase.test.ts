import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { previewReader } from "./actions.ts";
import { conflictOps } from "./rebase.ts";

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
    expect([...conflictOps(p.value)]).toEqual(["op_1"]);
    expect(conflictOps(null).size).toBe(0);
  });
});
