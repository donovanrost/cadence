import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api";
import { activeBody, grantOf, proposalBody } from "./grant-fixtures.ts";
import { approveFailure, issueFailure, narrowFailure, rejectFailure } from "./grant-refusals.ts";
import {
  decideOffer,
  issuedLine,
  narrowedLine,
  sheetWords,
  stateLine,
  waitingLine,
} from "./grant-words.ts";

/** ux U105 (#283): the grant words, each from the read or the refusal, never computed. */
const refusal = (
  kind: "conflict" | "forbidden" | "invalid",
  code: string,
  details?: unknown,
): ApiError => ({
  kind,
  code,
  message: "x",
  details,
});
const proposal = grantOf(proposalBody);
const nameless = grantOf(proposalBody, { service_identity: { id: "svc_9", name: null } });
const NOT = " Your approval wasn't recorded.";

describe("row state lines (U105)", () => {
  it("proposed, an undecided proposal that expired, rejected and withdrawn", () => {
    expect(stateLine(proposal)).toBe(
      "Proposed by Mira K. at 11-19 06:40Z · decide by 11-22 06:40Z",
    );
    expect(stateLine(grantOf(proposalBody, { state: "expired" }))).toBe(
      "Proposed by Mira K. at 11-19 06:40Z; no one decided it in time.",
    );
    // An active grant past valid_until keeps today's line (approved_at set).
    expect(stateLine(grantOf(activeBody, { state: "expired" }))).toBeNull();
    expect(
      stateLine(
        grantOf(proposalBody, {
          state: "rejected",
          rejected_by: { id: "u2", name: "Ana R." },
          rejected_at: "2026-11-19T06:52:00Z",
          rejection_reason: "Too wide",
        }),
      ),
    ).toBe("Rejected by Ana R. at 11-19 06:52Z: Too wide");
    expect(stateLine(grantOf(proposalBody, { state: "rejected" }))).toBe("Rejected.");
    expect(
      stateLine(
        grantOf(proposalBody, {
          state: "withdrawn",
          withdrawn_by: { id: "u2", name: "Ana R." },
          withdrawn_at: "2026-11-19T07:05:00Z",
        }),
      ),
    ).toBe("Withdrawn at 11-19 07:05Z, when Ana R. revoked the grant it would replace.");
    expect(stateLine(grantOf(proposalBody, { state: "withdrawn" }))).toBe(
      "Withdrawn: the grant it would replace was revoked.",
    );
    expect(stateLine(grantOf(activeBody))).toBeNull();
  });

  it("a proposer who isn't named drops the name, never shows an id", () => {
    const g = grantOf(proposalBody, { proposed_by: { id: null, name: null } });
    expect(stateLine(g)).toBe("Proposed at 11-19 06:40Z · decide by 11-22 06:40Z");
  });
});

describe("Waiting for approval (U105)", () => {
  it("the line, and who decides for a viewer who isn't an admin", () => {
    expect(waitingLine(proposal)).toBe(
      "Proposed by Mira K. at 11-19 06:40Z: Night shift. It takes effect once another org admin approves it. If no one decides by 11-22 06:40Z, it expires.",
    );
    const watcher = grantOf(proposalBody, {
      viewer_can_decide: false,
      cannot_decide_because: "not_admin",
    });
    expect(waitingLine(watcher)).toMatch(/ Org admins approve grants\.$/);
    expect(decideOffer(watcher)).toEqual({ kind: "watch" });
  });

  const offer = (because: string, details: unknown = null, base = proposalBody) =>
    decideOffer(
      grantOf(base, {
        viewer_can_decide: false,
        cannot_decide_because: because,
        cannot_decide_details: details,
      }),
    );

  it("A6: each reason from the server, Approve off with it, Reject kept", () => {
    expect(decideOffer(proposal)).toEqual({ kind: "act", blocked: null });
    expect(offer("proposer")).toEqual({
      kind: "act",
      blocked: { text: "You proposed this grant, so another org admin approves it." },
    });
    expect(offer("accountable", { grantee: { id: "svc_1", name: "Nightly planner" } })).toEqual({
      kind: "act",
      blocked: {
        text: "You're accountable for Nightly planner, so another org admin approves its grant.",
      },
    });
    expect(offer("authors_unknown", { service: { id: "svc_1", name: "Nightly planner" } })).toEqual(
      {
        kind: "act",
        blocked: {
          text: "Nightly planner has no one recorded as accountable for it, so its grant can't be approved yet. An org admin records who's accountable in People › Service identities.",
        },
      },
    );
    expect(offer("policy_changed")).toEqual({
      kind: "act",
      blocked: {
        text: "The mission's approval setting changed after this grant was proposed, so it can't be approved. It has to be proposed again.",
      },
    });
    expect(offer("not_a_person")).toEqual({ kind: "watch" });
    expect(offer("not_proposed")).toEqual({ kind: "none" });
    expect(offer("paused")).toEqual({
      kind: "act",
      blocked: {
        text: "You can't approve this grant, so another org admin approves it.",
        code: "paused",
      },
    });
    expect(decideOffer(grantOf(activeBody))).toEqual({ kind: "none" });
  });

  it("a nameless service reads 'the service identity this grant is for' in a sentence", () => {
    const accountable = decideOffer(
      grantOf(proposalBody, {
        service_identity: { id: "svc_9", name: null },
        viewer_can_decide: false,
        cannot_decide_because: "accountable",
        cannot_decide_details: { grantee: { id: "svc_9", name: null } },
      }),
    );
    expect(accountable).toEqual({
      kind: "act",
      blocked: {
        text: "You're accountable for the service identity this grant is for, so another org admin approves it.",
      },
    });
    expect(issuedLine(grantOf(activeBody, { service_identity: { id: "svc_9", name: null } }))).toBe(
      "Granted. The service identity this grant is for can act under it until 12-19 06:40Z.",
    );
  });
});

describe("approve refusals (U105)", () => {
  const said = (e: ApiError, viewer: string | null = "u3") => approveFailure(e, proposal, viewer);

  it("separation: why, nothing recorded, then Approve stays off with the up-front line", () => {
    const proposed = said(
      refusal("forbidden", "automation_grant_self_approval_forbidden", { because: "proposed" }),
    );
    expect(proposed.text).toBe(
      `Not approved: you proposed this grant, so another org admin approves it.${NOT}`,
    );
    expect(proposed.disable?.text).toBe(
      "You proposed this grant, so another org admin approves it.",
    );
    const acc = said(
      refusal("forbidden", "automation_grant_self_approval_forbidden", {
        because: "accountable",
        grantee: { id: "svc_1", name: "Nightly planner" },
      }),
    );
    expect(acc.text).toBe(
      `Not approved: you're accountable for Nightly planner, so another org admin approves its grant.${NOT}`,
    );
    const unknown = said(
      refusal("forbidden", "automation_grant_approver_authors_unknown", {
        service: { id: "svc_1", name: "Nightly planner" },
      }),
    );
    expect(unknown.text).toContain(
      "Not approved: Nightly planner has no one recorded as accountable for it",
    );
    expect(unknown.text.endsWith(NOT)).toBe(true);
  });

  it("not proposed: decided (by the viewer, by someone else) and by state", () => {
    const decided = (by: unknown, state = "active") =>
      said(
        refusal("conflict", "automation_grant_not_proposed", {
          state,
          decided_by: by,
          decided_at: "2026-11-19T06:52:00Z",
        }),
      ).text;
    expect(decided("u3")).toBe(
      "You already approved this grant at 11-19 06:52Z. Reload to see it.",
    );
    expect(decided({ id: "u2", name: "Ana R." })).toBe(
      "This grant was already approved by Ana R. at 11-19 06:52Z, so your approval wasn't recorded. Reload to see it.",
    );
    expect(decided("u2", "rejected")).toBe(
      "This grant was already rejected at 11-19 06:52Z, so your approval wasn't recorded. Reload to see it.",
    );
    const by = (state: string) =>
      said(refusal("conflict", "automation_grant_not_proposed", { state })).text;
    expect(by("expired")).toBe(
      `Not approved: no one decided this grant in time, so it expired.${NOT} It has to be proposed again.`,
    );
    expect(by("rejected")).toContain("this grant was already rejected");
    expect(by("active")).toContain("this grant was already approved");
    expect(by("revoked")).toContain("this grant was revoked");
    expect(by("withdrawn")).toContain("this proposal was withdrawn");
  });

  it("setting changed, a stale read, person-only, capability, duplicate, legacy, unknown", () => {
    const policy = said(
      refusal("conflict", "approval_policy_changed", { kind: "automation_grants" }),
    );
    expect(policy.text).toBe(
      `Not approved: the mission's approval setting changed after this grant was proposed.${NOT} It has to be proposed again.`,
    );
    expect(policy.disable?.text).toContain("It has to be proposed again.");
    expect(said(refusal("conflict", "grant_changed")).text).toContain(
      "this grant changed after you opened it",
    );
    expect(said(refusal("forbidden", "authenticated_user_required")).text).toBe(
      `Not approved: only a person can approve a grant, not a service identity.${NOT}`,
    );
    expect(said(refusal("forbidden", "automation_grant_capability_required")).text).toContain(
      "this grant lets Nightly planner do something you can't do yourself",
    );
    expect(said(refusal("conflict", "duplicate_operation")).text).toBe(
      "Not approved: Cadence matched this to an earlier, different request, so your approval wasn't recorded. Reload and try again.",
    );
    expect(said(refusal("conflict", "automation_grant_legacy")).text).toContain(
      "it can only be revoked",
    );
    expect(said(refusal("conflict", "something_new"))).toEqual({
      text: `Not approved: Cadence refused this approval.${NOT}`,
      code: "something_new",
    });
  });
});

describe("reject and narrow refusals (U105)", () => {
  it("reject: person-only, legacy, duplicate, already decided, unknown", () => {
    expect(rejectFailure(refusal("forbidden", "authenticated_user_required")).text).toBe(
      "Not rejected: only a person can reject a grant, not a service identity. Nothing changed.",
    );
    expect(rejectFailure(refusal("conflict", "automation_grant_legacy")).text).toContain(
      "so it can only be revoked. Nothing changed.",
    );
    expect(rejectFailure(refusal("conflict", "duplicate_operation")).text).toContain(
      "so nothing changed. Reload and try again.",
    );
    expect(
      rejectFailure(refusal("conflict", "automation_grant_not_proposed", { state: "active" })).text,
    ).toBe("Not rejected: this grant was already approved, so nothing changed. Reload to see it.");
    expect(rejectFailure(refusal("conflict", "nope"))).toEqual({
      text: "Not rejected: Cadence refused this rejection, so nothing changed.",
      code: "nope",
    });
  });

  it("narrow: the widening fields by the sheet's labels; an unknown field as a code only", () => {
    const g = grantOf(activeBody);
    expect(
      narrowFailure(
        refusal("invalid", "automation_grant_not_narrower", {
          fields: ["maximum_contacts", "cost_x"],
        }),
        g,
      ),
    ).toEqual({
      text: "Not narrowed: this change gives Nightly planner more than it has now (Contacts per plan, at most), so it needs approval. Propose it as a new grant instead.",
      code: "cost_x",
    });
    expect(narrowFailure(refusal("invalid", "automation_grant_not_narrower"), g).text).toBe(
      "Not narrowed: this change gives Nightly planner more than it has now, so it needs approval. Propose it as a new grant instead.",
    );
    expect(narrowFailure(refusal("invalid", "automation_grant_narrow_unchanged"), g).text).toBe(
      "Not narrowed: these values are the ones the grant has now, so nothing changed. Choose less than it allows, or cancel.",
    );
    expect(narrowFailure(refusal("conflict", "automation_grant_legacy"), g).text).toBe(
      "Not narrowed: this grant was made before Cadence checked grants against the mission's approval setting, so it can only be revoked. Nothing changed. To change it, propose a new grant.",
    );
    expect(narrowFailure(refusal("forbidden", "authenticated_user_required"), g).text).toContain(
      "only a person can narrow a grant",
    );
  });
});

describe("the grant sheet follows the approval setting (U105)", () => {
  it("propose under independent or unread; grant at once under direct", () => {
    expect(sheetWords("independent", "Nightly planner")).toMatchObject({
      title: "Propose a grant",
      commit: "Propose grant",
      line: "It takes effect once another org admin approves it. Until then Nightly planner can't act under it.",
    });
    expect(sheetWords(null, null).line).toBe(
      "It takes effect once another org admin approves it. Until then the service identity can't act under it.",
    );
    expect(sheetWords("direct", "Nightly planner")).toMatchObject({
      title: "Grant automation",
      commit: "Grant",
      line: "It takes effect at once. No second person's approval is needed, as this mission's setting allows.",
    });
  });

  it("the answer's line by its state", () => {
    expect(issuedLine(proposal)).toBe(
      "Proposed. It takes effect once another org admin approves it. If no one decides by 11-22 06:40Z, it expires.",
    );
    expect(issuedLine(grantOf(activeBody))).toBe(
      "Granted. Nightly planner can act under it until 12-19 06:40Z.",
    );
    expect(issuedLine(grantOf(activeBody, { state: "revoked" }))).toBe(
      "Cadence didn't confirm the grant. Reload to see it.",
    );
    expect(issueFailure(refusal("forbidden", "authenticated_user_required"), false, null)).toBe(
      "Not proposed: only a person can propose a grant, not a service identity.",
    );
    expect(
      issueFailure(
        refusal("forbidden", "automation_grant_capability_required"),
        true,
        "Nightly planner",
      ),
    ).toContain(
      "Not granted: this grant would let Nightly planner do something you can't do yourself",
    );
    expect(narrowedLine(grantOf(activeBody))).toBe(
      "Narrowed. Nightly planner can now plan and submit, planning up to 48h 00m ahead, 40 contacts per plan, 2 at once, until 12-19 06:40Z.",
    );
    // ca-ux on #514: one contact reads singular.
    expect(narrowedLine(grantOf({ ...activeBody, maximum_contacts: 1 }))).toContain(
      "1 contact per plan",
    );
    expect(nameless.service_identity.name).toBeNull();
  });

  // #519 (ca-ux): the actions as a sentence list, the horizon as a duration.
  it("lists three actions as a sentence and words an odd horizon as a duration", () => {
    const g = grantOf(activeBody, {
      allowed_actions: ["plan", "repair", "submit"],
      maximum_horizon_seconds: 5_400,
    });
    expect(narrowedLine(g)).toContain(
      "can now plan, repair and submit, planning up to 1h 30m ahead",
    );
    expect(narrowedLine(grantOf(activeBody, { allowed_actions: ["plan"] }))).toContain(
      "can now plan, planning",
    );
  });

  // #499: `approved` is a resume reason; on a proposal the panel keeps its code, unworded.
  it("reads an `approved` reason on a proposal as one it doesn't word", () => {
    expect(
      decideOffer(
        grantOf(proposalBody, { viewer_can_decide: false, cannot_decide_because: "approved" }),
      ),
    ).toEqual({
      kind: "act",
      blocked: {
        text: "You can't approve this grant, so another org admin approves it.",
        code: "approved",
      },
    });
  });
});
