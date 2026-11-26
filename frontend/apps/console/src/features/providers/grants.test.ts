import { organizationId as orgIdReader } from "@/api/index.ts";
import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api";
import {
  accountFailure,
  fetchAccountDetail,
  restrictionText,
  revokedLine,
  type AccountGrant,
} from "./grants.ts";

/** Fixtures: plans/providers.md L13 (proposed 11-13). */
const grant: AccountGrant = {
  id: "gr_1",
  version: 2,
  mission: { id: "m1", name: "Earendil" },
  state: "active",
  allowed_services: null,
  allowed_stations: ["SVB", "NLT"],
  max_quota: 40,
  reason: null,
  granted_by: { kind: "user", id: "u1", name: "Mira K." },
  granted_at: "2026-11-12T14:03:00Z",
  revoked_by: null,
  revoked_at: null,
  revoke_reason: null,
};

describe("provider-account grants (L13)", () => {
  it("says a grant's restrictions, or that it has none", () => {
    expect(restrictionText(grant)).toBe("Stations SVB, NLT · quota 40");
    expect(restrictionText({ ...grant, allowed_stations: null, max_quota: null })).toBe(
      "Everything the account allows",
    );
  });

  it("says what a revoke did to open bookings", () => {
    expect(revokedLine(0)).toBe("Revoked. No open bookings used it.");
    expect(revokedLine(3)).toBe("Revoked. 3 open bookings now need an operator's review.");
  });

  it("words stale evidence", () => {
    const conflict = (code: string): ApiError => ({
      kind: "conflict",
      code,
      message: "Refused.",
      details: null,
    });
    expect(accountFailure(conflict("account_changed"))).toContain("This account changed");
    expect(accountFailure(conflict("credential_already_revoked"))).toBe(
      "The credential is already revoked.",
    );
  });
});

describe("PA2 credential with nothing registered (api-ops drift sweep)", () => {
  it("reads status 'missing' with a null version", async () => {
    const original = globalThis.fetch;
    globalThis.fetch = async () =>
      new Response(
        JSON.stringify({
          data: {
            account: {
              id: "acc_1",
              version: 1,
              credential: { ref: "NL_KEY", version: null, status: "missing" },
              guardrails: { allowed_services: null, allowed_stations: null },
            },
            grants: [],
            permissions: [],
          },
        }),
        { status: 200 },
      );
    try {
      const r = await fetchAccountDetail(
        { orgId: orgIdReader("o"), accountId: "acc_1" },
        new AbortController().signal,
      );
      expect(r.ok && r.value.account.credential).toEqual({
        ref: "NL_KEY",
        version: null,
        status: "missing",
      });
    } finally {
      globalThis.fetch = original;
    }
  });
});
