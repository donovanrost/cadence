import { describe, expect, it } from "vite-plus/test";
import { missionId as missionIdReader } from "@/api/index.ts";
import { fetchProviders } from "./api.ts";
import {
  addBody,
  blankAdd,
  checkSentence,
  grantLine,
  healthLine,
  revokedSentence,
  type ProviderCheck,
} from "./providers.ts";

/** Fixtures: setup.md "Mission providers (L12)" (api-ops 4f81a1d0d). */
const row = {
  id: "prov_1",
  name: "Northlight",
  provider_type: "reflect_orbital",
  account: { id: "acc_1", name: "Northlight prod" },
  status: { lifecycle_state: "active", last_validated_at: null, last_synced_at: null },
  station_count: 4,
  version: 2,
  policy_mode: "approval_required",
  grant: { id: "g1", version: 3, state: "active" },
  health: {
    validate: { status: "healthy", checked_at: "2026-11-13T02:10:00Z", error: null },
    sync: { status: null, checked_at: null, error: null },
  },
};

async function decoded(body: unknown) {
  const original = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({ data: body }), { status: 200 });
  try {
    return await fetchProviders(missionIdReader("m"), new AbortController().signal);
  } finally {
    globalThis.fetch = original;
  }
}

describe("mission providers (L12)", () => {
  it("reads {providers, permissions}; a direct binding has no grant", async () => {
    const r = await decoded({
      providers: [row, { ...row, id: "prov_2", grant: null, account: null }],
      permissions: [],
    });
    expect(r.ok && r.value.providers[0]?.name).toBe("Northlight");
    expect(r.ok && r.value.canManage).toBe(false);
    expect(r.ok && r.value.providers[1]?.grant).toBeNull();
    // api-ops drift sweep: a direct binding has no account either.
    expect(r.ok && r.value.providers[1]?.account).toBeNull();
    const withL12 = await decoded({ providers: [row], permissions: ["providers.manage"] });
    expect(withL12.ok && withL12.value.canManage).toBe(true);
  });

  it("builds the add body; bounded mode needs a shortest pass", () => {
    const base = {
      ...blankAdd,
      grant: "g1",
      name: " Northlight ",
      mode: "approval_required" as const,
    };
    expect(addBody(base)).toEqual({
      ok: true,
      body: { grant_id: "g1", display_name: "Northlight", policy_mode: "approval_required" },
    });
    const bounded = { ...base, mode: "bounded_automatic" as const, substitutions: "SVB, NLT" };
    expect(addBody(bounded)).toEqual({
      ok: false,
      why: "Say the shortest pass worth keeping, in minutes.",
    });
    expect(addBody({ ...bounded, retainedMinutes: "5" })).toMatchObject({
      ok: true,
      body: {
        bounded: {
          approved_station_substitutions: ["SVB", "NLT"],
          minimum_retained_duration_seconds: 300,
        },
      },
    });
  });

  it("says what a validate or sync found", () => {
    const check = (
      ok: boolean,
      stations: number | null,
      message: string | null,
    ): ProviderCheck => ({
      provider: {
        ...row,
        status: { ...row.status, lifecycle_state: "active" },
        policy_mode: "approval_required",
        grant: null,
        health: {
          validate: { status: null, checked_at: null, error: null },
          sync: { status: null, checked_at: null, error: null },
        },
      },
      result: { ok, stations, message },
    });
    expect(checkSentence("validate", check(true, null, null))).toBe(
      "Validated: the provider answered.",
    );
    expect(checkSentence("sync", check(true, 12, null))).toBe("Synced 12 stations.");
    expect(
      checkSentence("validate", check(false, null, "The provider didn't answer in time.")),
    ).toBe("Validation failed: The provider didn't answer in time.");
    expect(checkSentence("sync", check(false, null, "unsupported_capability"))).toBe(
      "Sync failed: unsupported_capability.",
    );
    expect(healthLine({ status: null, checked_at: null, error: null })).toEqual({
      state: "off",
      text: "Never checked",
    });
  });

  it("words the account grant (ux SettingsAuditProviders.md)", () => {
    expect(grantLine(null).text).toBe("None: set up before account grants");
    expect(grantLine({ id: "g1", version: 3, state: "active" })).toEqual({
      text: "Active · v3",
      revoked: false,
    });
    expect(grantLine({ id: "g1", version: 3, state: "revoked" })).toEqual({
      text: "Revoked · v3",
      revoked: true,
    });
    expect(grantLine({ id: "g1", version: 3, state: "unrecognized" }).text).toBe("v3");
    expect(revokedSentence("Northlight prod")).toBe(
      "The organization revoked this mission's grant to Northlight prod, so this provider can't be used until it's added again from an active grant.",
    );
    expect(revokedSentence(null)).toContain("revoked this mission's grant, so");
  });
});
