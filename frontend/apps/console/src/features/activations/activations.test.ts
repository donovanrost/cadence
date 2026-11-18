import { describe, expect, it } from "vite-plus/test";
import { missionId as missionIdReader } from "@/api/index.ts";
import type { ApiError } from "@/api";
import {
  applyCodes,
  applySentence,
  decidedLine,
  decideFailure,
  decisionLine,
  decisionText,
  fetchActivations,
  notApplied,
  resumeFailure,
  type ActivationRequest,
} from "./api.ts";

/** Fixtures: plans/activations.md (proposed 11-13). */
const request: ActivationRequest = {
  id: "act_1",
  kind: "telemetry_decom",
  app: { key: "telemetry_decom", name: "Telemetry decom" },
  summary: "Decom composition for 3 spacecraft",
  binding_set: { id: "bs_1", version: 4 },
  requested_by: { kind: "user", id: "u1", name: "Mira K." },
  requested_at: "2026-11-13T02:10:00Z",
  state: "approval_pending",
  decision: null,
  execution: null,
  can_decide: true,
  superseded_by: undefined,
  superseded_at: undefined,
};

describe("app activation approvals (L10)", () => {
  it("says what an approve did, including an apply that failed", () => {
    expect(decidedLine("approve", { request, outcome: "applied" })).toEqual({
      tone: "nominal",
      text: "Approved and applied.",
    });
    // U41: no sentence and no known code reads as the generic failure.
    const failed = {
      ...request,
      execution: {
        state: "failed" as const,
        since: undefined,
        error_code: undefined,
        retryable: undefined,
        error: null,
      },
    };
    expect(decidedLine("approve", { request: failed, outcome: "needs_review" })).toEqual({
      tone: "caution",
      text: "Approved, but it didn't apply. Applying failed.",
    });
    expect(decidedLine("reject", { request, outcome: undefined }).text).toBe(
      "Rejected. Nothing changes.",
    );
  });

  const decided = {
    ...request,
    state: "approved" as const,
    decision: {
      state: "approved" as const,
      by: { kind: "user" as const, id: "u2", name: "Ada L." },
      at: "2026-11-13T02:20:00Z",
      reason: "looks right" as string | null,
      source: undefined,
      subject: undefined,
      separated_from: undefined,
      admin_mode: undefined as boolean | null | undefined,
    },
  };

  it("reads a decided request's line", () => {
    expect(decisionLine(request)).toBeNull();
    expect(decisionText(decided)).toMatch(/^Approved by Ada L\. on 11-13.*: looks right$/);
    const withdrawn = {
      ...decided,
      state: "withdrawn" as const,
      decision: { ...decided.decision, state: "withdrawn" as const, reason: "not needed." },
    };
    expect(decisionText(withdrawn)).toBe("Withdrawn by Ada L. at 11-13 02:20Z: not needed.");
  });

  it("words the four-eyes record's new decisions (U89, P3 #227)", () => {
    // An approve's comment is optional (P3 ruling 3): no dangling colon.
    expect(decisionText({ ...decided, decision: { ...decided.decision, reason: null } })).toBe(
      "Approved by Ada L. on 11-13 02:20Z",
    );
    // not_required: the setting's words, never "direct".
    const notRequired = {
      ...decided,
      decision: { ...decided.decision, state: "not_required" as const, reason: null },
    };
    expect(decisionText(notRequired)).toBe(
      "Applied Decom composition for 3 spacecraft without a second person's approval, as this mission's setting allows.",
    );
    // ADMIN MODE goes right after the decider's name, only when true.
    const admin = decisionLine({ ...decided, decision: { ...decided.decision, admin_mode: true } });
    expect(admin?.[1]).toEqual({ actor: { name: "Ada L.", adminMode: true } });
    const member = decisionLine({
      ...decided,
      decision: { ...decided.decision, admin_mode: false },
    });
    expect(member?.[1]).toEqual({ actor: { name: "Ada L.", adminMode: false } });
  });

  it("explains a refused decision", () => {
    const refused = (kind: "forbidden" | "conflict", code: string): ApiError =>
      kind === "forbidden"
        ? { kind, code, message: "Refused." }
        : { kind, code, message: "Refused.", details: null };
    expect(decideFailure(refused("forbidden", "self_approval_forbidden"))).toBe(
      "You requested this. Someone else approves it.",
    );
    expect(decideFailure(refused("conflict", "not_pending"))).toContain("already decided");
    expect(decideFailure(refused("forbidden", "not_requester"))).toBe(
      "Only the person who requested it can withdraw it.",
    );
  });

  it("words an approved activation that didn't apply (U41)", () => {
    const exec = (
      error_code: (typeof applyCodes)[number] | "unrecognized",
      error: string | null,
    ) => ({
      ...request,
      state: "approved" as const,
      execution: {
        state: "failed" as const,
        since: "2026-11-13T02:14:00Z",
        error_code,
        error,
        retryable: error_code !== "spacecraft_configuration_review_stale",
      },
    });
    expect(notApplied(exec("activation_execution_interrupted", null))).toEqual({
      text: "Approved, but it didn't apply. Applying was cut off: Cadence lost its database connection partway. Since 11-13 02:14Z.",
      retry: true,
      next: null,
    });
    const stale = notApplied(
      exec(
        "spacecraft_configuration_review_stale",
        "EARENDIL-312's configuration changed after it was reviewed, so the reviewed version can't be applied.",
      ),
    );
    expect(stale?.retry).toBe(false);
    expect(stale?.text).toContain("EARENDIL-312's configuration changed");
    expect(stale?.next).toBe("Request activation again so the current version can be approved.");
    expect(applySentence(exec("unrecognized", null).execution)).toBe("Applying failed.");
    // U88: domain makes it non-retryable; the request-again step, no Retry apply.
    const orphan = exec("mission_model_revision_not_in_catalog", null);
    expect(notApplied({ ...orphan, execution: { ...orphan.execution, retryable: false } })).toEqual(
      {
        text: "Approved, but it didn't apply. The catalog doesn't list the revision this request names, so it can't be applied. Since 11-13 02:14Z.",
        retry: false,
        next: "Request activation again so the current version can be approved.",
      },
    );
    expect(notApplied(request)).toBeNull();
    // ux: unknown retryability says neither Retry nor "Request activation again".
    const unknown = exec("activation_execution_interrupted", null);
    expect(
      notApplied({ ...unknown, execution: { ...unknown.execution, retryable: undefined } }),
    ).toMatchObject({
      retry: false,
      next: null,
    });
    // api: a stalled apply is still in_progress, with no code and the U41 sentence set.
    const stalled = {
      ...request,
      state: "approved" as const,
      execution: {
        state: "in_progress" as const,
        since: "2026-11-13T02:14:00Z",
        error_code: null,
        error: "Applying didn't finish, and nothing is working on it now.",
        retryable: true,
      },
    };
    expect(notApplied(stalled)).toMatchObject({
      text: "Approved, but it didn't apply. Applying didn't finish, and nothing is working on it now. Since 11-13 02:14Z.",
      retry: true,
    });
    expect(notApplied({ ...stalled, execution: { ...stalled.execution, error: null } })).toBeNull();
    expect(
      resumeFailure({
        kind: "conflict",
        code: "not_resumable",
        message: "x",
        details: { error_code: "approved_activation_content_mismatch" },
      }),
    ).toBe(
      "This can't be retried: What would be applied now differs from what was approved, so it wasn't applied. Request activation again so the current version can be approved.",
    );
    expect(
      resumeFailure({
        kind: "conflict",
        code: "nothing_to_resume",
        message: "x",
        details: { state: "succeeded" },
      }),
    ).toBe("It already applied.");
  });

  it("reads api's contract example (activations.md, be59d4f32)", async () => {
    const row = {
      id: "activation_request_1",
      kind: null,
      app: null,
      summary: "Decom composition for 3 spacecraft",
      binding_set: { id: "bs_1", version: 4 },
      requested_by: { kind: "user", id: "u1", name: "Mira K." },
      requested_at: "2026-11-13T02:10:00Z",
      state: "approved",
      decision: null,
      execution: {
        state: "failed",
        since: "2026-11-13T02:14:00Z",
        error_code: "spacecraft_configuration_review_stale",
        error:
          "A spacecraft's configuration changed after it was reviewed, so the reviewed version can't be applied.",
        retryable: false,
      },
      can_decide: false,
    };
    const original = globalThis.fetch;
    globalThis.fetch = async () =>
      new Response(JSON.stringify({ data: { requests: [row], next: null, permissions: [] } }), {
        status: 200,
      });
    try {
      const r = await fetchActivations(
        { missionId: missionIdReader("m"), state: "decided" },
        new AbortController().signal,
      );
      expect(r.ok && r.value.requests[0]?.execution?.retryable).toBe(false);
      expect(r.ok && r.value.requests[0]?.kind).toBeNull();
    } finally {
      globalThis.fetch = original;
    }
  });

  it("reads a born-approved request's not_required decision with the record's fields (P3 #227)", async () => {
    const row = {
      id: "activation_request_2",
      kind: "spacecraft_configuration",
      app: null,
      summary: "EARENDIL-004 configuration v4",
      binding_set: { id: "bs_2", version: 4 },
      requested_by: { kind: "user", id: "u1", name: "Mira K." },
      requested_at: "2026-11-18T02:10:00Z",
      state: "approved",
      decision: {
        state: "not_required",
        by: { kind: "user", id: "u1", name: "Mira K." },
        at: "2026-11-18T02:10:00Z",
        reason: null,
        source: { kind: "change_set_review", id: "rev_9" },
        subject: { version: 4, digest: "sha256:cd" },
        separated_from: [],
        admin_mode: false,
      },
      execution: null,
      can_decide: false,
    };
    const original = globalThis.fetch;
    globalThis.fetch = async () =>
      new Response(JSON.stringify({ data: { requests: [row], next: null, permissions: [] } }), {
        status: 200,
      });
    try {
      const r = await fetchActivations(
        { missionId: missionIdReader("m"), state: "decided" },
        new AbortController().signal,
      );
      const decision = r.ok ? r.value.requests[0]?.decision : null;
      expect(decision).toMatchObject({
        state: "not_required",
        source: { kind: "change_set_review", id: "rev_9" },
        subject: { version: 4 },
        admin_mode: false,
      });
    } finally {
      globalThis.fetch = original;
    }
  });
});
