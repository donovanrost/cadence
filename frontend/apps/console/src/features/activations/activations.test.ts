import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api";
import { decidedLine, decideFailure, decisionLine, type ActivationRequest } from "./api.ts";

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
    const failed = { ...request, execution: { state: "failed" as const, error: "runtime busy" } };
    expect(decidedLine("approve", { request: failed, outcome: "needs_review" })).toEqual({
      tone: "caution",
      text: "Approved, but it didn't apply: runtime busy.",
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
});
