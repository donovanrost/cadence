import { describe, expect, it } from "vite-plus/test";
import { diffMeta } from "@/features/catalog/importRun.ts";
import { groupedMeta } from "@/features/readiness/present.ts";
import { noGoReason } from "./add/stage.ts";
import { checkRows, type ReadinessCheck } from "./detail.ts";

/** #308: the Setup audit's rank-1 words (ux #305: C4, S3, S4, R1). */
describe("Setup words (#308)", () => {
  it("C4: a catalog diff says what it's against as 'rev 14', never 'r14' (U17)", () => {
    expect(diffMeta(14)).toBe("Against rev 14 · sorted by risk");
    expect(diffMeta(null)).toBe("Sorted by risk");
  });

  it("S3: a readiness check that isn't set up reads 'Not set up' with the not-set-up mark (U3)", () => {
    const check: ReadinessCheck = {
      key: "routing",
      status: "not_set_up",
      title: "No routing rule yet",
      body: "",
    };
    expect(checkRows([check])[0]).toMatchObject({ state: "off", verdict: "Not set up" });
  });

  it("S4: Stage counts the NO-GO checks; another refusal keeps its own sentence", () => {
    expect(noGoReason(2, "EARENDIL-7: SCID taken")).toBe("Fix 2 NO-GO checks first.");
    expect(noGoReason(1, "x")).toBe("Fix 1 NO-GO check first.");
    expect(noGoReason(0, "EARENDIL-7: unknown profile Block 2")).toBe(
      "EARENDIL-7: unknown profile Block 2",
    );
  });

  it("R1: grouped findings are 'findings', never 'items' (ux #317)", () => {
    expect(groupedMeta(3006, 4)).toBe("Grouped by cause · 3,006 findings → 4 lines");
    expect(groupedMeta(4, 4)).toBe("Grouped by cause · 4 lines");
  });
});
