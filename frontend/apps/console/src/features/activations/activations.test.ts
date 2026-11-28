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
  requestedLine,
  resumeFailure,
  type ActivationRequest,
} from "./api.ts";

/** Fixtures: plans/activations.md (proposed 11-13). */
const request: ActivationRequest = {
  id: "act_1",
  kind: "spacecraft_configuration",
  summary: "Spacecraft configuration for 3 spacecraft",
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
  // #319 (U94/U95 'After Approve', ca-ux; U20): the line comes from the answer, one per branch.
  const exec = (state: "in_progress" | "succeeded" | "failed", finished_at?: string) => ({
    state,
    since: undefined,
    finished_at,
    error_code: undefined,
    retryable: undefined,
    error: null,
  });
  const approve = (
    execution: ReturnType<typeof exec> | null,
    outcome: "applied" | "needs_review" | undefined,
  ) => decidedLine("approve", { request: { ...request, execution }, outcome });

  it("a failed apply: crit, with U41's sentence (no code reads as the generic failure)", () => {
    expect(approve(exec("failed"), "needs_review")).toEqual({
      tone: "crit",
      text: "Approved, but it didn't apply. Applying failed.",
      failed: true,
    });
  });

  it("needs_review without a failure: couldn't confirm, never 'didn't apply'", () => {
    // No error and no code: nothing after the sentence (never U41's 'Applying failed.', ca-ux #419).
    expect(approve(exec("in_progress"), "needs_review")).toEqual({
      tone: "caution",
      text: "Approved, but Cadence couldn't confirm that it applied.",
      failed: true,
    });
    expect(approve(null, "needs_review").text).toBe(
      "Approved, but Cadence couldn't confirm that it applied.",
    );
    // With a code, U41's sentence for it follows.
    const code: (typeof applyCodes)[number] = "activation_execution_interrupted";
    const interrupted = { ...exec("in_progress"), error_code: code };
    expect(
      decidedLine("approve", {
        request: { ...request, execution: interrupted },
        outcome: "needs_review",
      }).text,
    ).toMatch(/^Approved, but Cadence couldn't confirm that it applied\. \S/);
  });

  it("still applying: says so, as a status", () => {
    expect(approve(exec("in_progress"), undefined)).toEqual({
      tone: "info",
      text: "Approved. It's applying now.",
      failed: false,
    });
  });

  it("applied only when the answer says applied and the apply succeeded, with its time", () => {
    expect(approve(exec("succeeded"), "applied")).toEqual({
      tone: "nominal",
      text: "Approved and applied.",
      failed: false,
    });
    expect(approve(exec("succeeded", "2026-11-19T03:46:12Z"), "applied").text).toBe(
      "Approved and applied at 03:46Z.",
    );
  });

  it("anything else claims nothing: no execution, or applied without a succeeded apply", () => {
    const neutral = {
      tone: "info",
      text: "Approved. Cadence hasn't confirmed that it applied yet. Reload to see it.",
      failed: false,
    };
    expect(approve(null, "applied")).toEqual(neutral);
    expect(approve(null, undefined)).toEqual(neutral);
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

  const applied = {
    execution: {
      state: "succeeded" as const,
      since: undefined,
      finished_at: "2026-11-13T02:31:00Z" as string | null | undefined,
      error_code: undefined,
      retryable: undefined,
      error: null,
    },
  };

  it("reads a decided request's line", () => {
    expect(decisionLine(request)).toBeNull();
    expect(decisionText(decided)).toMatch(/^Approved by Ada L\. at 11-13.*: looks right$/);
    const withdrawn = {
      ...decided,
      state: "withdrawn" as const,
      decision: { ...decided.decision, state: "withdrawn" as const, reason: "not needed." },
    };
    expect(decisionText(withdrawn)).toBe("Withdrawn by Ada L. at 11-13 02:20Z: not needed.");
    // No reason: the line ends at the time, never ": ." (ux, #227).
    expect(decisionText({ ...withdrawn, decision: { ...withdrawn.decision, reason: null } })).toBe(
      "Withdrawn by Ada L. at 11-13 02:20Z.",
    );
    expect(decisionText({ ...withdrawn, decision: { ...withdrawn.decision, reason: "  " } })).toBe(
      "Withdrawn by Ada L. at 11-13 02:20Z.",
    );
  });

  it("words the four-eyes record's new decisions (U89, P3 #227)", () => {
    // An approve's comment is optional (P3 ruling 3): no dangling colon.
    expect(decisionText({ ...decided, decision: { ...decided.decision, reason: null } })).toBe(
      "Approved by Ada L. at 11-13 02:20Z",
    );
    // not_required: the setting's words, never "direct", and only once the apply succeeded.
    const notRequired = {
      ...decided,
      decision: { ...decided.decision, state: "not_required" as const, reason: null },
    };
    // Not applied yet, applying, or failed: the line claims only the decision (ux U89, 11-18).
    const decisionOnly =
      "No second person's approval was needed, as this mission's setting allows · 11-13 02:20Z";
    expect(decisionText(notRequired)).toBe(decisionOnly);
    for (const state of ["in_progress", "failed"] as const)
      expect(decisionText({ ...notRequired, execution: { ...applied.execution, state } })).toBe(
        decisionOnly,
      );

    // Applied carries the apply's finish time, never the decision's (U20); none until api sends it.
    expect(decisionText({ ...notRequired, ...applied })).toBe(
      "Applied Spacecraft configuration for 3 spacecraft at 11-13 02:31Z without a second person's approval, as this mission's setting allows.",
    );
    expect(
      decisionText({
        ...notRequired,
        execution: { ...applied.execution, finished_at: undefined },
      }),
    ).toBe(
      "Applied Spacecraft configuration for 3 spacecraft without a second person's approval, as this mission's setting allows.",
    );
    // ADMIN MODE goes right after the decider's name, only when true.
    const admin = decisionLine({ ...decided, decision: { ...decided.decision, admin_mode: true } });
    const actorOf = (parts: ReturnType<typeof decisionLine>) => parts?.find((p) => "actor" in p);
    expect(actorOf(admin)).toEqual({ actor: { name: "Ada L.", adminMode: true } });
    const member = decisionLine({
      ...decided,
      decision: { ...decided.decision, admin_mode: false },
    });
    expect(actorOf(member)).toEqual({ actor: { name: "Ada L.", adminMode: false } });
    // #308 (U25): a decider with no name drops, the act and time stay; ADMIN MODE follows the verb.
    const nameless = decisionLine({
      ...decided,
      decision: { ...decided.decision, by: null, admin_mode: true },
    });
    expect(nameless?.map((p) => ("text" in p ? p.text : `[${p.actor.name}]`)).join("")).toMatch(
      /^Approved\[\] at 11-13 02:20Z/,
    );
    expect(actorOf(nameless)).toEqual({ actor: { name: "", adminMode: true } });
    expect(
      decisionText({ ...decided, decision: { ...decided.decision, by: null, admin_mode: false } }),
    ).toMatch(/^Approved at 11-13 02:20Z/);
  });

  it("a request with no requester name shows the time alone (#308, U25, as U103)", () => {
    expect(requestedLine(request)).toBe("Mira K. · 11-13 02:10Z");
    expect(
      requestedLine({ ...request, requested_by: { kind: "user", id: "u1", name: null } }),
    ).toBe("11-13 02:10Z");
  });

  it("explains a refused decision", () => {
    const refused = (kind: "forbidden" | "conflict", code: string): ApiError =>
      kind === "forbidden"
        ? { kind, code, message: "Refused." }
        : { kind, code, message: "Refused.", details: null };
    // U94 (#275): the old code and the new one read the same requester line.
    for (const code of ["self_approval_forbidden", "activation_self_approval_forbidden"])
      expect(decideFailure(refused("forbidden", code))).toBe(
        "Not approved: you requested this, so another person approves it. Your approval wasn't recorded.",
      );
    const via = (via_service: unknown): ApiError => ({
      kind: "forbidden",
      code: "activation_self_approval_forbidden",
      message: "Refused.",
      details: { via_service },
    });
    // #280: through a service identity the person is accountable for; nameless, never its id.
    expect(decideFailure(via({ id: "svc_1", name: "Nightly planner" }))).toBe(
      "Not approved: Nightly planner, a service identity you're accountable for, requested this, so another person approves it. Your approval wasn't recorded.",
    );
    expect(decideFailure(via({ id: "svc_1", name: null }))).toBe(
      "Not approved: a service identity you're accountable for requested this, so another person approves it. Your approval wasn't recorded.",
    );
    expect(decideFailure(via(null))).toContain("Not approved: you requested this");
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
        finished_at: undefined,
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
        finished_at: undefined,
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
      summary: "Spacecraft configuration for 3 spacecraft",
      binding_set: { id: "bs_1", version: 4 },
      requested_by: { kind: "user", id: "u1", name: "Mira K." },
      requested_at: "2026-11-13T02:10:00Z",
      state: "approved",
      decision: null,
      execution: {
        state: "failed",
        since: "2026-11-13T02:14:00Z",
        finished_at: undefined,
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

  it("reads a decision whose record fields are all null, or all absent (fe-ops, #227)", async () => {
    const decided = (extra: Record<string, unknown>) => ({
      id: "activation_request_3",
      kind: "spacecraft_configuration",
      summary: "EARENDIL-004 configuration v5",
      binding_set: { id: "bs_3", version: 5 },
      requested_by: { kind: "user", id: "u1", name: "Mira K." },
      requested_at: "2026-11-18T02:10:00Z",
      state: "approved",
      decision: {
        state: "approved",
        by: { kind: "user", id: "u2", name: "Ada L." },
        at: "2026-11-18T02:12:00Z",
        ...extra,
      },
      execution: null,
      can_decide: false,
    });
    const nulls = {
      reason: null,
      source: null,
      subject: null,
      separated_from: null,
      admin_mode: null,
    };
    // api 11-18: (B)'s workspace sends source kind spacecraft_configuration; others read as text.
    const workspace = { source: { kind: "spacecraft_configuration", id: "rev_12" } };
    const other = { source: { kind: "plan_review", id: "p1" } };
    const original = globalThis.fetch;
    globalThis.fetch = async () =>
      new Response(
        JSON.stringify({
          data: {
            requests: [decided(nulls), decided({}), decided(workspace), decided(other)],
            next: null,
            permissions: [],
          },
        }),
        { status: 200 },
      );
    try {
      const r = await fetchActivations(
        { missionId: missionIdReader("m"), state: "decided" },
        new AbortController().signal,
      );
      expect(r.ok).toBe(true);
      const rows = r.ok ? r.value.requests : [];
      expect(rows.map((x) => x.decision?.source?.kind ?? null)).toEqual([
        null,
        null,
        "spacecraft_configuration",
        { unrecognized: "plan_review" },
      ]);
      for (const row of rows.slice(0, 2))
        expect(decisionText(row)).toBe("Approved by Ada L. at 11-18 02:12Z");
    } finally {
      globalThis.fetch = original;
    }
  });
});
