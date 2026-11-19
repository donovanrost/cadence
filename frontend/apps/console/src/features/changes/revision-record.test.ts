import { describe, expect, it } from "vite-plus/test";
import { approvedBy, revisionHeader, submittedBy, type HeaderPart } from "./revision-record.ts";
import { revisionSummary } from "./shapes.ts";

/** Fixtures: dashboards' P3 shape diff (11-17) and ux U89. */
const mira = { kind: "user", id: "u1", name: "Mira K." };
const ana = { kind: "user", id: "u2", name: "Ana R." };
const owen = { kind: "user", id: "u3", name: "Owen P." };
const preP3 = {
  revision: 10,
  kind: "change_set",
  live: true,
  applied_at: "2026-11-17T09:12:00Z",
  applied_by: mira,
  reason: null,
  summary: null,
  entry_count: 2,
  change_set_id: "cs10",
  rolls_back_to: null,
  approvals: [{ actor: ana, comment: null, decided_at: "2026-11-17T09:11:00Z" }],
};
const record = { subject: { version: 3, digest: "sha256:ab" }, separated_from: ["u1", 7] };
const p3 = (approvals: readonly Record<string, unknown>[], appliedBy = ana) =>
  revisionSummary({ ...preP3, submitted_by: mira, applied_by: appliedBy, approvals });
const approval = (actor: typeof ana, extra: Record<string, unknown> = {}) => ({
  actor,
  comment: null,
  decided_at: "2026-11-17T09:11:00Z",
  decision: "approved",
  ...record,
  admin_mode: false,
  ...extra,
});
const text = (parts: readonly HeaderPart[]) =>
  parts.map((p) => ("text" in p ? p.text : p.actor.name)).join("");
const tagged = (parts: readonly HeaderPart[]) =>
  parts.flatMap((p) => ("actor" in p && p.actor.adminMode ? [p.actor.name] : []));

describe("the four-eyes record in change history (U89, P3 #227)", () => {
  it("reads a pre-P3 revision as today: applied_by is the submitter, entries are approvals", () => {
    const row = revisionSummary(preP3);
    expect(row.submitted_by).toBeUndefined();
    expect(submittedBy(row)?.name).toBe("Mira K.");
    expect(approvedBy(row)).toEqual({
      kind: "approvers",
      approvers: [{ name: "Ana R.", adminMode: false }],
    });
    expect(text(revisionHeader(row))).toBe(
      "Applied 2026-11-17 09:12:00Z by Mira K. · approved by Ana R.",
    );
  });

  it("decodes the record's fields and words an approver who applied (U89)", () => {
    const row = p3([approval(ana)]);
    expect(row.approvals[0]).toMatchObject({
      decision: "approved",
      subject: { version: 3, digest: "sha256:ab" },
      separated_from: ["u1", "7"],
      admin_mode: false,
    });
    expect(submittedBy(row)?.name).toBe("Mira K.");
    expect(text(revisionHeader(row))).toBe(
      "Submitted by Mira K. · approved and applied by Ana R. · 11-17 09:12Z",
    );
  });

  it("names the applier when it isn't the approver", () => {
    expect(text(revisionHeader(p3([approval(ana)], owen)))).toBe(
      "Submitted by Mira K. · approved by Ana R. · applied by Owen P. · 11-17 09:12Z",
    );
  });

  it("says no second approval was needed for not_required (never 'direct')", () => {
    const row = p3([approval(mira, { decision: "not_required" })], mira);
    expect(approvedBy(row)).toEqual({ kind: "not_needed" });
    const header = text(revisionHeader(row));
    expect(header).toBe(
      "Submitted and applied by Mira K. · 11-17 09:12Z · no second approval needed",
    );
    expect(header).not.toMatch(/direct/i);
  });

  it("tags only an approver who decided in admin mode", () => {
    const row = p3([approval(ana, { admin_mode: true }), approval(owen, { admin_mode: null })]);
    expect(tagged(revisionHeader(row))).toEqual(["Ana R."]);
    expect(approvedBy(row)).toEqual({
      kind: "approvers",
      approvers: [
        { name: "Ana R.", adminMode: true },
        { name: "Owen P.", adminMode: false },
      ],
    });
    expect(text(revisionHeader(row))).toContain("approved by Ana R. and Owen P. · applied by");
  });

  it("reads a decision value it doesn't know yet as text, not as an approval", () => {
    const row = p3([approval(ana, { decision: "countersigned" })]);
    expect(row.approvals[0]?.decision).toEqual({ unrecognized: "countersigned" });
    expect(approvedBy(row)).toEqual({ kind: "none" });
  });

  it("reads every new field null, or every one absent, without failing the list (fe-ops)", () => {
    const nulls = { decision: null, subject: null, separated_from: null, admin_mode: null };
    const nullRow = revisionSummary({
      ...preP3,
      submitted_by: null,
      approvals: [{ ...preP3.approvals[0], ...nulls }],
    });
    // A null decision is an approval, as an absent one is (pre-P3).
    expect(approvedBy(nullRow)).toEqual({
      kind: "approvers",
      approvers: [{ name: "Ana R.", adminMode: false }],
    });
    expect(submittedBy(nullRow)).toBeNull();
    // A null submitter drops its clause, as the table shows a dash.
    expect(text(revisionHeader(nullRow))).toBe(
      "Applied 2026-11-17 09:12:00Z by Mira K. · approved by Ana R.",
    );
    const absentRow = revisionSummary(preP3);
    expect(absentRow.approvals[0]).toMatchObject({
      decision: undefined,
      subject: undefined,
      separated_from: undefined,
      admin_mode: undefined,
    });
  });

  it("drops the applied-by clause when the applier is unknown", () => {
    const row = revisionSummary({
      ...preP3,
      submitted_by: mira,
      applied_by: null,
      approvals: [approval(ana)],
    });
    expect(text(revisionHeader(row))).toBe(
      "Submitted by Mira K. · approved by Ana R. · 11-17 09:12Z",
    );
  });

  it("still refuses a malformed record field", () => {
    expect(() => p3([approval(ana, { admin_mode: "yes" })])).toThrow();
    expect(() => p3([approval(ana, { separated_from: [{ id: "u1" }] })])).toThrow();
  });

  it("drops a person the server can't name; the act and the time stay (#308, U25)", () => {
    const nameless = { kind: "user", id: "u9", name: null };
    expect(
      text(
        revisionHeader(
          revisionSummary({
            ...preP3,
            submitted_by: nameless,
            applied_by: ana,
            approvals: [approval(ana)],
          }),
        ),
      ),
    ).toBe("Submitted · approved and applied by Ana R. · 11-17 09:12Z");
    expect(text(revisionHeader(p3([approval(nameless as typeof ana)], owen)))).toBe(
      "Submitted by Mira K. · approved · applied by Owen P. · 11-17 09:12Z",
    );
    expect(text(revisionHeader(p3([approval(ana), approval(nameless as typeof ana)], owen)))).toBe(
      "Submitted by Mira K. · approved by Ana R. · applied by Owen P. · 11-17 09:12Z",
    );
    expect(
      text(revisionHeader(revisionSummary({ ...preP3, applied_by: nameless, approvals: [] }))),
    ).toBe("Applied 2026-11-17 09:12:00Z");
  });

  it("names Cadence and service identities (U103, #371); a nameless approver in admin mode keeps its tag", () => {
    const system = { kind: "system", id: null, name: null };
    const service = { kind: "service", id: "svc-1", name: "Nightly planner" };
    expect(text(revisionHeader(p3([approval(service as typeof ana)], system as typeof ana)))).toBe(
      "Submitted by Mira K. · approved by Nightly planner (a service identity) · applied by Cadence · 11-17 09:12Z",
    );
    const nameless = { kind: "user", id: "u9", name: null };
    const row = p3([approval(nameless as typeof ana, { admin_mode: true })], owen);
    expect(tagged(revisionHeader(row))).toEqual([""]);
    expect(text(revisionHeader(row))).toBe(
      "Submitted by Mira K. · approved · applied by Owen P. · 11-17 09:12Z",
    );
  });
});
