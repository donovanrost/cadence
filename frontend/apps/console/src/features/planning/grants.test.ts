import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api";
import { blankGrant, grantBody, grantFailure } from "./grants.ts";

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
