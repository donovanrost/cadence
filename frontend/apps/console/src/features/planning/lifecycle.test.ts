import { describe, expect, it } from "vite-plus/test";
import { missionId as missionIdReader } from "@/api/index.ts";
import type { ApiError } from "@/api";
import { fetchTemplate } from "./api.ts";
import { stateChangedLine, transitionFailure, verbsFor } from "./lifecycle.ts";

/** Fixtures: plans/planning-verbs.md L2, as api agreed 11-13. */
const detail = {
  id: "tpl_1",
  name: "Block 1 daily",
  state: "paused",
  version: 3,
  target: { profile_id: "p1" },
  applies_to: "profile Earendil Block 1",
  applies_to_count: 12,
  rule_summary: "2 contacts a day",
  priority: "routine",
  document: {},
  versions: [{ version: 3, created_at: "2026-11-10T09:00:00Z", actor: null }],
  state_changed: {
    state: "paused",
    at: "2026-11-12T14:03:00Z",
    actor: { kind: "user", id: "u1", name: "Mira K." },
    reason: "provider outage",
  },
};

async function decoded(body: unknown) {
  const original = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({ data: body }), { status: 200 });
  try {
    return await fetchTemplate(
      { missionId: missionIdReader("m"), templateId: "tpl_1" },
      new AbortController().signal,
    );
  } finally {
    globalThis.fetch = original;
  }
}

describe("template lifecycle (L2)", () => {
  it("offers active ↔ paused and close, nothing once closed", () => {
    expect(verbsFor("active")).toEqual(["pause", "close"]);
    expect(verbsFor("paused")).toEqual(["activate", "close"]);
    expect(verbsFor("closed")).toEqual([]);
  });

  it("says the last move, and nothing while active since create", async () => {
    const r = await decoded(detail);
    expect(r.ok && stateChangedLine(r.value)).toMatch(
      /^Paused by Mira K\. on 11-12.*: provider outage$/,
    );
    const fresh = await decoded({ ...detail, state: "active", state_changed: null });
    expect(fresh.ok && stateChangedLine(fresh.value)).toBeNull();
  });

  it("words a refused move", () => {
    const conflict = (code: string, details: unknown): ApiError => ({
      kind: "conflict",
      code,
      message: "Refused.",
      details,
    });
    expect(
      transitionFailure(conflict("template_transition_not_allowed", { state: "closed" })),
    ).toBe("It's closed now, so it can't change. Reload to see it.");
    expect(transitionFailure(conflict("version_conflict", { expected_version: 4 }))).toContain(
      "Someone changed this template",
    );
  });
});
