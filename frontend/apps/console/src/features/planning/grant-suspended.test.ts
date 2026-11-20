import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api";
import { activeBody, grantOf } from "./grant-fixtures.ts";
import {
  resumedLine,
  resumeFailure,
  resumeLine,
  resumeOffer,
  suspendedLine,
} from "./grant-suspended.ts";

/** ux U105 "Suspended" (#499): the row line, Resume…'s up-front reasons and its refusals. */
const suspension = (over: Record<string, unknown> = {}) => ({
  at: "2026-11-19T22:40:00Z",
  by: { kind: "user", id: "u1", name: "Mira K." },
  settings_revision: 4,
  level: "mission",
  ...over,
});
const suspended = (over: Record<string, unknown> = {}) =>
  grantOf(activeBody, {
    state: "suspended",
    suspension: suspension(),
    viewer_can_decide: true,
    cannot_decide_because: null,
    ...over,
  });
const nameless = { service_identity: { id: "svc_9", name: null } };
const refusal = (kind: "conflict" | "forbidden", code: string, details?: unknown): ApiError => ({
  kind,
  code,
  message: "x",
  details,
});

describe("the suspended row line (U105)", () => {
  it("names who changed which setting, and who resumes it by the setting in force", () => {
    expect(suspendedLine(suspended(), "independent")).toBe(
      "Suspended when Mira K. changed the mission's approval setting to Needs a second person's approval at 11-19 22:40Z. A second org admin resumes it.",
    );
    const org = suspended({ suspension: suspension({ level: "organization" }) });
    expect(suspendedLine(org, "independent")).toContain(
      "Mira K. changed the organization's approval setting to",
    );
    // A missing or unknown level claims neither.
    for (const level of [null, "fleet"])
      expect(suspendedLine(suspended({ suspension: suspension({ level }) }), null)).toContain(
        "changed the approval setting for this mission to",
      );
    // Back to direct: any org admin; unread: the stricter form.
    expect(suspendedLine(suspended(), "direct")).toMatch(/ An org admin resumes it\.$/);
    expect(suspendedLine(suspended(), null)).toMatch(/ A second org admin resumes it\.$/);
  });

  it("still says who resumes it when the suspension record is missing (ca-ux on #565)", () => {
    expect(suspendedLine(suspended({ suspension: null }), "independent")).toBe(
      "Suspended. A second org admin resumes it.",
    );
    expect(suspendedLine(suspended({ suspension: null }), "direct")).toBe(
      "Suspended. An org admin resumes it.",
    );
  });

  it("drops who when the saver isn't named", () => {
    const g = suspended({ suspension: suspension({ by: { kind: "user", id: null, name: null } }) });
    expect(suspendedLine(g, "independent")).toBe(
      "Suspended when the mission's approval setting changed to Needs a second person's approval at 11-19 22:40Z. A second org admin resumes it.",
    );
    expect(suspendedLine(suspended({ suspension: suspension({ by: null }) }), null)).toContain(
      "Suspended when the mission's approval setting changed to",
    );
    expect(suspendedLine(grantOf(activeBody), "independent")).toBeNull();
  });
});

describe("Resume… up front (A6, the server's flags only)", () => {
  const blocked = (because: string, details: unknown = null) => {
    const o = resumeOffer(
      suspended({
        viewer_can_decide: false,
        cannot_decide_because: because,
        cannot_decide_details: details,
      }),
    );
    return o.kind === "act" ? o.blocked : "none";
  };

  it("words each reason; not_admin offers nothing; an unknown one keeps its code", () => {
    expect(resumeOffer(suspended())).toEqual({ kind: "act", blocked: null });
    expect(resumeOffer(grantOf(activeBody))).toEqual({ kind: "none" });
    expect(blocked("approved")).toEqual({
      text: "You approved this grant, so another org admin resumes it.",
    });
    expect(blocked("proposer")).toEqual({
      text: "You proposed this grant, so another org admin resumes it.",
    });
    expect(blocked("accountable", { grantee: { id: "svc_1", name: "Nightly planner" } })).toEqual({
      text: "You're accountable for Nightly planner, so another org admin resumes its grant.",
    });
    expect(
      blocked("authors_unknown", { service: { id: "svc_1", name: "Nightly planner" } }),
    ).toEqual({
      text: "Nightly planner has no one recorded as accountable for it, so its grant can't be resumed yet. An org admin records who's accountable in People › Service identities.",
    });
    expect(blocked("not_admin")).toBe("none");
    expect(blocked("not_a_person")).toBe("none");
    expect(blocked("something_new")).toEqual({
      text: "You can't resume this grant, so another org admin resumes it.",
      code: "something_new",
    });
  });

  it("words policy_changed as the setting's change, never the viewer's refusal (ca-ux on #565)", () => {
    expect(
      resumeOffer(suspended({ viewer_can_decide: false, cannot_decide_because: "policy_changed" })),
    ).toEqual({
      kind: "act",
      blocked: {
        text: "The approval setting for this mission changed after this grant was suspended, so who can resume it may have changed. Reload to see it.",
      },
    });
  });

  it("words a nameless service by U105's form, never its id", () => {
    const o = resumeOffer(
      suspended({
        ...nameless,
        viewer_can_decide: false,
        cannot_decide_because: "accountable",
        cannot_decide_details: null,
      }),
    );
    expect(o).toEqual({
      kind: "act",
      blocked: {
        text: "You're accountable for the service identity this grant is for, so another org admin resumes it.",
      },
    });
    expect(resumeLine(suspended(nameless))).toBe(
      "It takes effect again at once. The service identity this grant is for can act under it until 12-19 06:40Z.",
    );
  });
});

describe("the resume answer and refusals (U105)", () => {
  it("claims a resume only on a confirmed state", () => {
    expect(resumedLine(grantOf(activeBody))).toBe(
      "Resumed. Nightly planner can act under it until 12-19 06:40Z.",
    );
    expect(resumedLine(suspended())).toBe(
      "Cadence didn't confirm that it resumed. Reload to see it.",
    );
  });

  it("words every refusal, each saying nothing changed", () => {
    const g = suspended();
    const said = (e: ApiError) => resumeFailure(e, g);
    const forbidden = (because: string, grantee?: unknown) =>
      said(refusal("forbidden", "automation_grant_self_approval_forbidden", { because, grantee }));
    expect(forbidden("approved")).toEqual({
      text: "Not resumed: you approved this grant, so another org admin resumes it. Nothing changed.",
      // ux on #570: while Resume stays off, its reason says it was refused.
      disable: { text: "Resume was refused. Reload to see the grant as it is now." },
    });
    expect(forbidden("proposed").text).toBe(
      "Not resumed: you proposed this grant, so another org admin resumes it. Nothing changed.",
    );
    expect(forbidden("accountable", { id: "svc_1", name: "Nightly planner" }).text).toBe(
      "Not resumed: you're accountable for Nightly planner, so another org admin resumes its grant. Nothing changed.",
    );
    expect(
      said(
        refusal("forbidden", "automation_grant_approver_authors_unknown", {
          service: { id: "svc_1", name: "Nightly planner" },
        }),
      ).text,
    ).toBe(
      "Not resumed: Nightly planner has no one recorded as accountable for it, so its grant can't be resumed yet. Nothing changed. An org admin records who's accountable in People › Service identities.",
    );
    expect(said(refusal("forbidden", "automation_grant_capability_required")).text).toBe(
      "Not resumed: this grant lets Nightly planner do something you can't do yourself, so you can't resume it. Nothing changed. Ask an org admin who can do everything it allows to resume it.",
    );
    // ux on #570: every separation refusal keeps Resume off with one reason; a retryable one doesn't.
    for (const code of [
      "automation_grant_self_approval_forbidden",
      "automation_grant_approver_authors_unknown",
      "automation_grant_capability_required",
    ])
      expect(said(refusal("forbidden", code)).disable?.text).toBe(
        "Resume was refused. Reload to see the grant as it is now.",
      );
    expect(said(refusal("conflict", "grant_changed")).disable).toBeUndefined();
    expect(said(refusal("conflict", "automation_grant_legacy")).text).toBe(
      "Not resumed: this grant was made before Cadence checked grants against the mission's approval setting, so it can only be revoked. Nothing changed. To change it, propose a new grant.",
    );
    const notSuspended = (state: string) =>
      said(refusal("conflict", "automation_grant_not_suspended", { state })).text;
    expect(notSuspended("expired")).toBe(
      "Not resumed: this grant's validity ended, so it can't be resumed. Nothing changed. To go on, propose a new grant.",
    );
    expect(notSuspended("active")).toBe(
      "Not resumed: it's active again. Nothing changed. Reload to see it.",
    );
    expect(notSuspended("revoked")).toBe(
      "Not resumed: it was revoked. Nothing changed. Reload to see it.",
    );
    expect(notSuspended("paused")).toBe(
      "Not resumed: it isn't suspended any more. Nothing changed. Reload to see it.",
    );
    expect(said(refusal("conflict", "grant_changed")).text).toBe(
      "Not resumed: the grant changed after you opened it. Nothing changed. Reload to see it, then resume it again.",
    );
    expect(said(refusal("forbidden", "authenticated_user_required")).text).toBe(
      "Not resumed: only a person can resume a grant, not a service identity. Nothing changed.",
    );
    expect(said(refusal("conflict", "duplicate_operation")).text).toBe(
      "Not resumed: Cadence matched this to an earlier, different request, so nothing changed. Reload and try again.",
    );
    expect(said(refusal("conflict", "something_new"))).toEqual({
      text: "Not resumed: Cadence refused this. Nothing changed.",
      code: "something_new",
    });
  });
});
