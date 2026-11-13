import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api";
import {
  applyCodes,
  applySentence,
  decidedLine,
  decideFailure,
  decisionLine,
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
};

describe("app activation approvals (L10)", () => {
  it("says what an approve did, including an apply that failed", () => {
    expect(decidedLine("approve", { request, outcome: "applied" })).toEqual({
      tone: "nominal",
      text: "Approved and applied.",
    });
    // U20/U41: an uncoded reason is never shown raw.
    const failed = {
      ...request,
      execution: {
        state: "failed" as const,
        since: undefined,
        error_code: undefined,
        retryable: undefined,
        error: "runtime busy",
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

  it("reads a decided request's line", () => {
    expect(decisionLine(request)).toBeNull();
    const decided = {
      ...request,
      state: "approved" as const,
      decision: {
        state: "approved" as const,
        by: { kind: "user" as const, id: "u2", name: "Ada L." },
        at: "2026-11-13T02:20:00Z",
        reason: "looks right",
      },
    };
    expect(decisionLine(decided)).toMatch(/^Approved by Ada L\. on 11-13.*: looks right$/);
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
    expect(applySentence(exec("unrecognized", "SQL error 42").execution)).toBe("Applying failed.");
    expect(notApplied(request)).toBeNull();
    // ux: unknown retryability says neither Retry nor "Request activation again".
    const unknown = exec("apply_stalled", null);
    expect(
      notApplied({ ...unknown, execution: { ...unknown.execution, retryable: undefined } }),
    ).toMatchObject({
      retry: false,
      next: null,
    });
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
});
