import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import DiagnosticsPanel from "@/features/catalog/DiagnosticsPanel.vue";
import { modelRevisionReader } from "@/features/catalog/approval/api.ts";
import {
  cannotApproveLine,
  cannotDecideLine,
  unwordedBlockCode,
} from "@/features/catalog/approval/words.ts";
import { kindLabel } from "@/features/changes/index.ts";
import RuleStations from "@/features/profiles/RuleStations.vue";
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

describe("Setup words, part 1 (#308; mms-ux's table b–d)", () => {
  it("(b) a station a rule names but the list doesn't have reads 'Unknown station', never its id", () => {
    const w = mount(RuleStations, { props: { stations: [], modelValue: ["gs-missing"] } });
    expect(w.text()).toContain("Unknown station");
    expect(w.text()).not.toContain("gs-missing");
  });

  it("(c) diagnostics meta counts findings, never items", () => {
    const d = { severity: "warning" as const, code: "W1", message: "skipped", path: null };
    const w = mount(DiagnosticsPanel, { props: { diagnostics: [d, d], index: "C4" } });
    expect(w.text()).toContain("2 findings → 1 line");
    const one = mount(DiagnosticsPanel, { props: { diagnostics: [d], index: "C4" } });
    expect(one.text()).toContain("1 finding → 1 line");
  });

  it("(d) a kind sent as text reads its word; an unknown one reads 'Change'", () => {
    expect(kindLabel("spacecraft_route")).toBe("Extra route");
    expect(kindLabel("quantum_link")).toBe("Change");
  });

  it("(d) an unworded approval reason reads plainly, with its code for Technical details", () => {
    const read = (o: Record<string, unknown>) => {
      const r = decode(modelRevisionReader, {
        id: "mm-4",
        status: "candidate",
        imported_at: null,
        imported_by: null,
        catalog_revision: null,
        decision: null,
        viewer_can_decide: false,
        affected_groups: null,
        affected_groups_count: null,
        viewer_is_importer: false,
        cannot_decide_because: null,
        plans_ready: true,
        comparison: null,
        ...o,
      });
      if (!r.ok) throw new Error(r.error.message);
      return r.value;
    };
    const decide = read({ cannot_decide_because: "quorum_reached" });
    expect(cannotDecideLine(decide)).toBe("You can't approve or reject this revision.");
    expect(unwordedBlockCode(decide)).toBe("quorum_reached");
    const approve = read({ cannot_approve_because: "model_frozen" });
    expect(cannotApproveLine(approve)).toBe(
      "This revision can't be approved. Reject it to clear it from the queue.",
    );
    expect(unwordedBlockCode(approve)).toBe("model_frozen");
    expect(unwordedBlockCode(read({ cannot_decide_because: "not_admin" }))).toBeNull();
  });
});
