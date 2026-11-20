import { describe, expect, it } from "vite-plus/test";
import { decode, type ApiError } from "@/api";
import {
  blankGrant,
  grantBody,
  grantFailure,
  grantTag,
  grantsReader,
  identityName,
  untilText,
} from "./grants.ts";
import { activeBody, grantOf, proposalBody } from "./grant-fixtures.ts";

/** Fixtures: plans/planning-verbs.md L3, as api agreed 11-13. */
describe("automation grants (L3)", () => {
  const draft = {
    ...blankGrant,
    identity: "svc_1",
    hours: "48",
    contacts: "40",
    concurrency: "2",
    days: "30",
    reason: " Night shift ",
  };

  it("builds the POST body, horizon in seconds, with the policy version as evidence", () => {
    expect(grantBody(draft, 3)).toEqual({
      ok: true,
      body: {
        service_identity_id: "svc_1",
        maximum_horizon_seconds: 172_800,
        maximum_contacts: 40,
        maximum_execution_concurrency: 2,
        valid_days: 30,
        reason: "Night shift",
        policy_version: 3,
      },
    });
  });

  it("says why it can't go yet", () => {
    expect(grantBody(draft, null)).toEqual({ ok: false, why: "Activate a policy first." });
    expect(grantBody({ ...draft, identity: "" }, 3)).toEqual({
      ok: false,
      why: "Choose a service identity.",
    });
    expect(grantBody({ ...draft, contacts: "4.5" }, 3)).toEqual({
      ok: false,
      why: "Limits and days are whole numbers above 0.",
    });
    expect(grantBody({ ...draft, reason: "  " }, 3)).toEqual({
      ok: false,
      why: "Give a reason first.",
    });
  });

  it("words the evidence conflicts", () => {
    const conflict = (code: string): ApiError => ({
      kind: "conflict",
      code,
      message: "Refused.",
      details: null,
    });
    expect(grantFailure(conflict("policy_changed"))).toContain("The active policy changed");
    expect(grantFailure(conflict("grant_changed"))).toContain("This grant changed");
  });
});

// #283 readers first (mms-security): the grants read from today's server AND from #283's proposals.
describe("the grants read across #283", () => {
  const today = {
    id: "g1",
    service_identity: { id: "svc_1", name: "Nightly planner" },
    policy_version: 3,
    allowed_actions: ["plan", "submit"],
    maximum_horizon_seconds: 172_800,
    maximum_contacts: 40,
    maximum_execution_concurrency: 2,
    valid_from: "2026-11-19T06:40:00Z",
    valid_until: "2026-12-19T06:40:00Z",
    state: "active",
    approved_by: { kind: "user", id: "u1", name: "Ana R." },
    approved_at: "2026-11-19T06:40:00Z",
    reason: "Night shift",
    revoked_by: null,
    revoked_at: null,
    revocation_reason: "",
    sha256: "abc",
  };
  const proposal = {
    ...today,
    id: "g2",
    state: "proposed",
    valid_from: null,
    valid_until: null,
    approved_by: null,
    approved_at: null,
    revocation_reason: null,
    validity_seconds: 2_592_000,
    proposed_by: { id: null, name: null },
    proposed_at: "2026-11-19T06:40:00Z",
    proposal_expires_at: "2026-11-22T06:40:00Z",
    rejected_by: null,
    rejected_at: null,
    rejection_reason: null,
    withdrawn_by: null,
    withdrawn_at: null,
    replaces_grant_id: null,
    viewer_can_decide: false,
    cannot_decide_because: "accountable",
    cannot_decide_details: { grantee: { id: "svc_1", name: "Nightly planner" } },
  };
  const page = (grants: unknown[], extra: Record<string, unknown> = {}) => ({
    grants,
    service_identities: [],
    limits: {
      maximum_horizon_seconds: null,
      maximum_contacts: null,
      maximum_execution_concurrency: null,
    },
    policy_version: 3,
    permissions: ["grants.manage"],
    ...extra,
  });

  it("reads today's shape unchanged, the new keys as null", () => {
    const r = decode(grantsReader, page([today]));
    if (!r.ok) throw new Error(r.error.message);
    const [g] = r.value.grants;
    expect(g?.state).toBe("active");
    expect(g?.proposed_by).toBeNull();
    expect(g?.viewer_can_decide).toBeNull();
    expect(r.value.approval_setting).toBeNull();
    expect(g && untilText(g)).toMatch(/^12-19/);
  });

  it("reads a proposal: null dates, a non-member proposer, its tag and 'N days from approval'", () => {
    const r = decode(grantsReader, page([proposal], { approval_setting: "independent" }));
    if (!r.ok) throw new Error(r.error.message);
    const [g] = r.value.grants;
    if (!g) throw new Error("no grant");
    expect(g.valid_until).toBeNull();
    expect(g.proposed_by).toEqual({ kind: null, id: null, name: null });
    expect(g.cannot_decide_because).toBe("accountable");
    expect(g.cannot_decide_details?.grantee?.name).toBe("Nightly planner");
    expect(grantTag(g)).toEqual({ state: "caution", label: "PROPOSED" });
    expect(untilText(g)).toBe("30 days from approval");
    expect(r.value.approval_setting).toBe("independent");
  });

  it("words a proposal's validity exactly; a decided proposal without one reads a dash", () => {
    const until = (over: Record<string, unknown>) => {
      const r = decode(grantsReader, page([{ ...proposal, ...over }]));
      if (!r.ok) throw new Error(r.error.message);
      const [g] = r.value.grants;
      return g ? untilText(g) : null;
    };
    expect(until({ validity_seconds: 86_400 })).toBe("1 day from approval");
    expect(until({ validity_seconds: 129_600 })).toBe("36 hours from approval");
    expect(until({ validity_seconds: null })).toBe("Set at approval");
    for (const state of ["rejected", "withdrawn", "expired"]) expect(until({ state })).toBe("—");
  });

  it("tags every U105 state, and an unknown one as UNKNOWN without failing the read", () => {
    const tag = (state: string) => {
      const r = decode(grantsReader, page([{ ...proposal, state }]));
      if (!r.ok) throw new Error(r.error.message);
      const [g] = r.value.grants;
      return g ? grantTag(g).label : null;
    };
    expect(["rejected", "withdrawn", "revoked", "expired", "paused"].map(tag)).toEqual([
      "REJECTED",
      "WITHDRAWN",
      "REVOKED",
      "EXPIRED",
      "UNKNOWN",
    ]);
  });
});

// #497 (U105) and #499 readers first.
describe("the grants read after #497, and #499's suspension", () => {
  it("takes viewer_can_narrow, the pre-#283 mark and policy_changed", () => {
    const legacy = grantOf(activeBody, {
      viewer_can_narrow: false,
      issued_before_two_person_approval: true,
      proposed_by: null,
      proposed_at: null,
      proposal_expires_at: null,
    });
    expect(legacy.viewer_can_narrow).toBe(false);
    expect(legacy.issued_before_two_person_approval).toBe(true);
    expect(legacy.proposed_by).toBeNull();
    const changed = grantOf(proposalBody, {
      viewer_can_decide: false,
      cannot_decide_because: "policy_changed",
    });
    expect(changed.cannot_decide_because).toBe("policy_changed");
  });

  it("a suspended grant with its suspension object reads, tagged UNKNOWN (#499)", () => {
    const g = grantOf(activeBody, {
      state: "suspended",
      suspension: {
        at: "2026-11-20T01:00:00Z",
        by: { kind: "user", id: "u2", name: "Ana R." },
        settings_revision: 4,
      },
    });
    expect(grantTag(g)).toEqual({ state: "off", label: "UNKNOWN" });
  });

  it("a gone identity's name stands alone as 'Unknown service identity', never its id (U25)", () => {
    const g = grantOf(activeBody, { service_identity: { id: "svc_9", name: null } });
    expect(identityName(g)).toBe("Unknown service identity");
    expect(identityName(grantOf(activeBody))).toBe("Nightly planner");
  });
});
