import type { ApiError, RemoteState } from "@/api";
import type { Draft, PlanDetail, PlanSummary } from "./api.ts";

/**
 * K1 view state (plans/scheduling.md "K1 state model", ux ScheduleFlow "K1 plan states").
 * Derived from the reads; screens switch on `kind` exhaustively.
 */
export type PlanView =
  | { kind: "loading" }
  | { kind: "failed"; error: ApiError }
  | { kind: "not_set_up"; missing: readonly string[] }
  | { kind: "no_draft"; last: PlanSummary | null }
  | { kind: "drafting"; phase: string | null; startedAt: string | null }
  | { kind: "interrupted"; phase: string | null }
  | { kind: "draft_failed"; message: string }
  | { kind: "plan"; plan: PlanDetail; fromRun: boolean };

/** Plans that represent the day's current state (superseded/canceled ones are history). */
export function currentPlan(plans: readonly PlanSummary[]): PlanSummary | null {
  return plans.find((p) => p.state !== "superseded" && p.state !== "canceled") ?? null;
}

export function planView(
  input: Readonly<{
    notSetUp: readonly string[] | null;
    runId: string | null;
    draft: RemoteState<Draft> | null;
    plans: RemoteState<{ plans: readonly PlanSummary[] }>;
    plan: RemoteState<PlanDetail> | null;
  }>,
): PlanView {
  if (input.notSetUp) return { kind: "not_set_up", missing: input.notSetUp };
  if (input.runId && input.draft) {
    const d = input.draft;
    if (d.status === "loading") return { kind: "loading" };
    if (d.status === "failed") return { kind: "failed", error: d.error };
    const { run, plan } = d.value;
    switch (run.state) {
      case "queued":
      case "running":
        return { kind: "drafting", phase: run.phase, startedAt: run.started_at };
      case "interrupted":
        return { kind: "interrupted", phase: run.phase };
      case "failed":
      case "canceled":
        return {
          kind: "draft_failed",
          message:
            run.failure?.message ??
            (run.state === "canceled" ? "The draft was canceled." : "Drafting failed."),
        };
      case "completed":
      case "partial":
        return plan
          ? { kind: "plan", plan, fromRun: true }
          : { kind: "draft_failed", message: "The draft finished without a plan." };
    }
  }
  if (input.plans.status === "loading") return { kind: "loading" };
  if (input.plans.status === "failed") return { kind: "failed", error: input.plans.error };
  if (!currentPlan(input.plans.value.plans))
    return { kind: "no_draft", last: input.plans.value.plans[0] ?? null };
  const p = input.plan;
  if (!p || p.status === "loading") return { kind: "loading" };
  if (p.status === "failed") return { kind: "failed", error: p.error };
  return { kind: "plan", plan: p.value, fromRun: false };
}
