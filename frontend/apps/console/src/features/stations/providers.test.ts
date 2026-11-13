import { describe, expect, it } from "vite-plus/test";
import { fetchProviders } from "./api.ts";
import { addBody, blankAdd, checkSentence, healthLine, type ProviderCheck } from "./providers.ts";

/** Fixtures: plans/providers.md L12 (proposed 11-13) and today's GET /providers. */
const row = {
  id: "prov_1",
  name: "Northlight",
  provider_type: "reflect_orbital",
  account: { id: "acc_1", name: "Northlight prod" },
  status: { lifecycle_state: "active", last_validated_at: null, last_synced_at: null },
  station_count: 4,
};

async function decoded(body: unknown) {
  const original = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({ data: body }), { status: 200 });
  try {
    return await fetchProviders("m", new AbortController().signal);
  } finally {
    globalThis.fetch = original;
  }
}

describe("mission providers (L12)", () => {
  it("reads today's {providers} payload (it used to expect a bare array)", async () => {
    const r = await decoded({ providers: [row] });
    expect(r.ok && r.value.providers[0]?.name).toBe("Northlight");
    expect(r.ok && r.value.canManage).toBe(false);
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
        version: undefined,
        policy_mode: undefined,
        grant: undefined,
        health: undefined,
      },
      result: { ok, stations, message },
    });
    expect(checkSentence("validate", check(true, null, null))).toBe(
      "Validated: the provider answered.",
    );
    expect(checkSentence("sync", check(true, 12, null))).toBe("Synced 12 stations.");
    expect(checkSentence("sync", check(false, null, "unsupported_capability"))).toBe(
      "Sync failed: unsupported_capability.",
    );
    expect(healthLine(undefined)).toEqual({ state: "off", text: "Never checked" });
  });
});
