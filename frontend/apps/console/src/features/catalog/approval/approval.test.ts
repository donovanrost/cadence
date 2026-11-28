import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId, type ApiError } from "@/api/index.ts";
import { modelRevisionReader } from "./api.ts";
import ApprovalPanel from "./ApprovalPanel.vue";
import { approvalTag, decisionFailure, kindWord, sectionLine } from "./words.ts";

// #260: the panel names the signed-in person for the already-approved line.
vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  useSession: () => ({ user: { id: "u-viewer" } }),
}));

/** ux U65 · catalog revision approval (api's wire 11-15). */
const comparison = {
  report_id: "rep-1",
  passed: true,
  against: { revision_id: "mm-3", catalog_revision_number: 3 },
  replay: {
    status: "not_run",
    reason: "qualification_corpus_required",
    cases: 0,
    failed_cases: [],
  },
  risk: "low",
  totals: { added: 3, removed: 0, changed: 1 },
  sections: [
    { kind: "command", added: 3, removed: 0, changed: 1 },
    { kind: "unit", added: 0, removed: 0, changed: 0 },
  ],
  affected_kinds: ["command"],
  changed_targets: ["command_encoding"],
  generated_at: "2026-11-15T09:00:00Z",
};
const wire = (o: Record<string, unknown> = {}) => ({
  id: "mm-4",
  status: "candidate",
  imported_at: "2026-11-14T22:10:00Z",
  imported_by: { id: "u-mira", name: "Mira K." },
  catalog_revision: { id: "cr-4", number: 4, label: "FSW 2.4", database_id: "db-1" },
  decision: null,
  viewer_can_decide: true,
  affected_groups: null,
  affected_groups_count: null,
  viewer_is_importer: false,
  cannot_decide_because: null,
  plans_ready: true,
  comparison,
  ...o,
});
const read = (o: Record<string, unknown> = {}) => {
  const r = decode(modelRevisionReader, wire(o));
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};
const mission = decode(missionId, "m-1");
if (!mission.ok) throw new Error(mission.error.message);
const key = { missionId: mission.value, revisionId: "mm-4" };
const panel = (o: Record<string, unknown> = {}) =>
  mount(ApprovalPanel, { props: { revision: read(o), modelKey: key } });
const text = (w: ReturnType<typeof panel>) => w.text().replace(/\s+/g, " ");

describe("the approval panel", () => {
  it("leads with replay not run, then the report, importer, plans and the decision", () => {
    const t = text(panel());
    expect(t).toContain("Approval · catalog rev 4");
    expect(t).toContain("AGAINST REV 3");
    expect(t.indexOf("Replay: not run. There's no qualification corpus")).toBeLessThan(
      t.indexOf("Comparison passed against rev 3"),
    );
    expect(t).toContain("RISK LOW");
    expect(t).toContain("Commands: 3 added · 1 changed");
    expect(t).not.toContain("Units");
    expect(t).toContain("Imported by Mira K. at 11-14 22:10Z.");
    expect(t).toContain("Runtime plans: Ready");
    expect(t).toContain("Approve rev 4");
    expect(t).toContain("Reject…");
  });

  it("with no report: Run comparison leads and Approve waits for it", () => {
    const w = panel({ comparison: null });
    expect(text(w)).toContain("No comparison has been run for rev 4 yet.");
    const approve = w.findAll("button").find((b) => b.text().startsWith("Approve rev 4"));
    expect(approve?.attributes("aria-disabled")).toBe("true");
    expect(approve?.text()).toContain("Run the comparison first.");
    expect(text(w)).not.toContain("Replay: not run");
  });

  it("the importer, under independent approval, reads why and gets no buttons", () => {
    const t = text(
      panel({
        viewer_can_decide: false,
        affected_groups: null,
        affected_groups_count: null,
        viewer_is_importer: true,
        cannot_decide_because: "self_approval",
      }),
    );
    expect(t).toContain("You imported this revision, so another org admin has to approve it.");
    expect(t).not.toContain("Approve rev 4");
  });

  it("says when the importer isn't recorded and plans aren't ready", () => {
    const t = text(panel({ imported_by: null, plans_ready: false }));
    expect(t).toContain("Importer not recorded");
    expect(t).toContain("Cadence doesn't know who imported this revision.");
    expect(t).toContain("Not ready yet");
  });

  it("C12 (#313): decided with nothing earlier, U90 keeps its short line, not the callout", () => {
    const decided = {
      status: "approved",
      viewer_can_decide: false,
      affected_groups: null,
      affected_groups_count: null,
      cannot_decide_because: "not_approvable",
      comparison: { ...comparison, against: null },
      decision: {
        kind: "approved",
        by: { id: "u-ana", name: "Ana R." },
        at: "2026-11-15T09:12:00Z",
        report_id: "rep-1",
        reason: null,
      },
    };
    const t = text(panel(decided));
    expect(t).toContain("Not compared: no earlier configuration.");
    expect(t).not.toContain("so there was nothing to compare it with");
    const pending = text(panel({ comparison: { ...comparison, against: null } }));
    expect(pending).toContain("so there was nothing to compare it with");
  });

  it("decided: one line with the reason, the report behind Show report", () => {
    const t = text(
      panel({
        status: "rejected",
        viewer_can_decide: false,
        affected_groups: null,
        affected_groups_count: null,
        cannot_decide_because: "not_approvable",
        decision: {
          kind: "rejected",
          by: { id: "u-ana", name: "Ana R." },
          at: "2026-11-15T09:12:00Z",
          report_id: null,
          reason: "Wrong FSW build.",
        },
      }),
    );
    expect(t).toContain("Rejected by Ana R. at 11-15 09:12Z: “Wrong FSW build.”");
    expect(t).toContain("Show report");
    expect(t).not.toContain("Comparison passed");
  });
});

describe("U65 words", () => {
  it("names kinds, drops zero counts, and reads an unknown kind from its key", () => {
    expect(read().comparison?.sections.map(sectionLine)).toEqual([
      "Commands: 3 added · 1 changed",
      null,
    ]);
    expect(kindWord({ unrecognized: "packet_layout" })).toBe("Packet layout");
  });

  it("tags rows and words the approve refusals", () => {
    expect(approvalTag("candidate")).toEqual({ label: "NEEDS APPROVAL", state: "caution" });
    expect(approvalTag("retired")).toBeNull();
    const refusal = (code: string) =>
      decisionFailure({ kind: "conflict", code, message: "x", details: null }, 3);
    expect(refusal("mission_model_comparison_not_passed").text).toBe(
      "Not approved: the comparison with rev 3 didn't pass. Your approval wasn't recorded.",
    );
    expect(refusal("mission_model_decision_reason_too_long").text).toBe(
      "Keep the reason under 2,000 characters.",
    );
    expect(refusal("mission_model_comparison_mismatch")).toEqual({
      text: "Not approved: the comparison is out of date. Your approval wasn't recorded. Run it again.",
      runAgain: true,
    });
  });
});

/** #312 (audit C1, C2): each refusal opens with its act; reject has its own lines. */
describe("approve and reject refusals open with their act (#312)", () => {
  const conflict = (code: string): ApiError => ({
    kind: "conflict",
    code,
    message: "x",
    details: null,
  });
  const forbidden: ApiError = { kind: "forbidden", code: "forbidden", message: "No." };

  it("approve: an org-admin refusal, and a code it doesn't word, with the code for Technical details", () => {
    expect(decisionFailure(forbidden, 3, "approve")).toEqual({
      text: "Not approved: only an org admin can approve this. Your approval wasn't recorded.",
      runAgain: false,
    });
    expect(decisionFailure(conflict("quorum_reached"), 3, "approve")).toEqual({
      text: "Not approved: Cadence refused this approval. Your approval wasn't recorded.",
      runAgain: false,
      code: "quorum_reached",
    });
  });

  it("reject: its own lines, never approve's", () => {
    const reject = (e: ApiError) => decisionFailure(e, 3, "reject").text;
    expect(reject(conflict("mission_model_revision_not_approvable"))).toBe(
      "Not rejected: this revision was already approved, rejected or replaced, so nothing changed.",
    );
    expect(reject(conflict("human_mission_model_approver_required"))).toBe(
      "Not rejected: only a person can reject a catalog revision, not a service identity. Nothing changed.",
    );
    expect(reject(forbidden)).toBe(
      "Not rejected: only an org admin can reject this. Nothing changed.",
    );
    // Approve-only refusals (the comparison, the catalog) fall to reject's fallback, with the code.
    expect(decisionFailure(conflict("mission_model_comparison_not_passed"), 3, "reject")).toEqual({
      text: "Not rejected: Cadence refused this rejection, so nothing changed.",
      runAgain: false,
      code: "mission_model_comparison_not_passed",
    });
    for (const code of [
      "mission_model_revision_not_approvable",
      "mission_model_comparison_mismatch",
      "mission_model_revision_not_in_catalog",
    ])
      expect(reject(conflict(code))).not.toMatch(/^Not approved/);
  });

  it("every approve refusal says the approval wasn't recorded (U95, #375); reject lines end 'nothing changed'", () => {
    const codes = [
      "mission_model_revision_not_in_catalog",
      "mission_model_self_approval_forbidden",
      "mission_model_comparison_not_passed",
      "mission_model_comparison_mismatch",
      "mission_model_runtime_plans_not_ready",
      "mission_model_revision_not_approvable",
      "human_mission_model_approver_required",
      "quorum_reached",
    ];
    for (const code of codes)
      expect(decisionFailure(conflict(code), 3, "approve").text).toMatch(
        /[Yy]our approval wasn't recorded\./,
      );
    expect(decisionFailure(forbidden, 3, "approve").text).toMatch(
      /Your approval wasn't recorded\.$/,
    );
    for (const e of [...codes.map(conflict), forbidden])
      expect(decisionFailure(e, 3, "reject").text).toMatch(/[Nn]othing changed\.$/);
  });

  it("the reason lines are the same for both acts", () => {
    for (const act of ["approve", "reject"] as const)
      expect(decisionFailure(conflict("mission_model_decision_reason_required"), 3, act).text).toBe(
        "Give a reason first.",
      );
  });
});

/** ux U88 (domain's orphan guard, 11-18): approve is refused; Reject stays to clear it. */
describe("a revision the catalog doesn't list (U88)", () => {
  const LINE =
    "The catalog doesn't list this revision, so it can't be approved. To approve it, import its file as a new catalog revision. Reject it to clear it from the queue.";
  const stubs = { RouterLink: { props: ["to"], template: "<a :data-to='to.name'><slot /></a>" } };
  const blockedPanel = (o: Record<string, unknown> = {}) =>
    mount(ApprovalPanel, {
      props: {
        revision: read({ catalog_revision: null, cannot_approve_because: "not_in_catalog", ...o }),
        modelKey: key,
      },
      global: { stubs },
    });

  it("Approve is off with the line and Open the catalog; Reject stays; no Run comparison", () => {
    const w = blockedPanel({ comparison: null });
    const t = text(w);
    expect(t).toContain(`${LINE} Open the catalog`);
    expect(w.find("a").attributes("data-to")).toBe("setup.catalog");
    const approve = w.findAll("button").find((b) => b.text().startsWith("Approve this revision"));
    expect(approve?.attributes("aria-disabled")).toBe("true");
    expect(approve?.attributes("title")).toBe(LINE);
    const reject = w.findAll("button").find((b) => b.text() === "Reject…");
    expect(reject?.attributes("aria-disabled")).toBeUndefined();
    expect(t).not.toContain("Run comparison");
  });

  it("an older server (field absent) or null leaves Approve as it was", () => {
    expect(text(panel())).not.toContain("The catalog doesn't list");
    expect(text(panel({ cannot_approve_because: null }))).not.toContain("The catalog doesn't list");
  });

  it("someone who can't decide reads that reason, not this one", () => {
    const t = text(blockedPanel({ viewer_can_decide: false, cannot_decide_because: "not_admin" }));
    expect(t).toContain("Org admins approve catalog revisions.");
    expect(t).not.toContain("The catalog doesn't list");
  });

  it("the 409 refusal words it and links the catalog, never the 503 words", () => {
    expect(
      decisionFailure(
        {
          kind: "conflict",
          code: "mission_model_revision_not_in_catalog",
          message: "x",
          details: null,
        },
        null,
      ),
    ).toEqual({
      text: "Not approved: the catalog doesn't list this revision. Your approval wasn't recorded. To approve it, import its file as a new catalog revision.",
      runAgain: false,
      openCatalog: true,
    });
  });
});

/** ux U90: a comparison with nothing earlier to compare against (against null). */
describe("no earlier configuration (U90)", () => {
  const first = (o: Record<string, unknown> = {}) => ({
    ...comparison,
    passed: true,
    against: null,
    sections: [
      { kind: "command", added: 1200, removed: 0, changed: 0 },
      { kind: "unit", added: 84, removed: 0, changed: 0 },
    ],
    ...o,
  });
  const CALLOUT =
    "There's no earlier configuration for this mission, so there was nothing to compare it with. All 1,284 declarations are new, and none has been checked against an earlier version.";

  it("never reads passed: caution verdict, meta, callout at the top, the line above Approve", () => {
    const w = panel({
      catalog_revision: { id: "cr-1", number: 1, label: null, database_id: "db-1" },
      comparison: first(),
    });
    const t = text(w);
    expect(t).toContain("NO EARLIER CONFIGURATION");
    expect(t).not.toContain("AGAINST REV");
    expect(t).toContain("Not compared: there's no earlier configuration");
    expect(t).not.toContain("Comparison passed");
    expect(w.find(".ap-mark--nominal").exists()).toBe(false);
    expect(t.indexOf(CALLOUT)).toBeGreaterThanOrEqual(0);
    expect(t.indexOf(CALLOUT)).toBeLessThan(t.indexOf("Replay: not run"));
    expect(t.indexOf("Approving it accepts every declaration as new.")).toBeLessThan(
      t.indexOf("Approve rev 1"),
    );
    expect(t).toContain("Reject…");
  });

  // C12 (#313; ux #305 §10) replaces U90's earlier "the callout stays": decided, it's U90's short
  // line, still above the decided line and never behind Show report.
  it("decided: U90's short line stays, not folded behind Show report (C12)", () => {
    const t = text(
      panel({
        status: "approved",
        viewer_can_decide: false,
        affected_groups: null,
        affected_groups_count: null,
        cannot_decide_because: "not_approvable",
        comparison: first(),
        decision: {
          kind: "approved",
          by: { id: "u-ana", name: "Ana R." },
          at: "2026-11-15T09:12:00Z",
          report_id: "rep-1",
          reason: null,
        },
      }),
    );
    expect(t).toContain("Not compared: no earlier configuration.");
    expect(t).not.toContain(CALLOUT);
    expect(t).not.toContain("Approving it accepts");
  });

  it("without a count it says every declaration; an earlier revision reads as before", () => {
    expect(text(panel({ comparison: first({ sections: [] }) }))).toContain(
      "Every declaration is new, and none has been checked against an earlier version.",
    );
    const t = text(panel());
    expect(t).toContain("Comparison passed against rev 3");
    expect(t).not.toContain("no earlier configuration");
  });
});
