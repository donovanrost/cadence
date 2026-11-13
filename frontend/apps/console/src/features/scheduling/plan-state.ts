import type { ApiError, RemoteState } from "@/api";
import type { DayDemand, Draft, PlanDetail, PlanSummary, RunPhase } from "./api.ts";

/**
 * K1 view state (plans/scheduling.md "K1 state model", ux ScheduleFlow "K1 plan states").
 * Derived from the reads; screens switch on `kind` exhaustively.
 */
export type PlanView =
  | { kind: "loading" }
  | { kind: "failed"; error: ApiError }
  | { kind: "not_set_up"; missing: readonly string[] }
  | { kind: "no_draft"; last: PlanSummary | null; demand: DayDemand | null }
  | { kind: "drafting"; phase: RunPhase | null; startedAt: string | null }
  /** `stoppedAt`: last recorded progress, so "stopped at or after" (api 413c8e18). */
  | { kind: "interrupted"; phase: RunPhase | null; stoppedAt?: string | null | undefined }
  | { kind: "draft_failed"; message: string }
  | { kind: "plan"; plan: PlanDetail; fromRun: boolean };

/** U28: K1 never opens a repair plan; repairs are proposed and applied in K2 (Re-plan). */
const dayPlans = (plans: readonly PlanSummary[]) => plans.filter((p) => p.repair_of === null);

/** Plans that represent the day's current state (superseded/canceled ones are history). */
export function currentPlan(plans: readonly PlanSummary[]): PlanSummary | null {
  return dayPlans(plans).find((p) => p.state !== "superseded" && p.state !== "canceled") ?? null;
}

/** U28: the day's open (not yet applied) repair proposal, newest first, for the K1 callout. */
export function openProposal(proposals: readonly PlanSummary[]): PlanSummary | null {
  return (
    proposals.find(
      (p) => p.repair_of !== null && (p.state === "draft" || p.state === "pending_approval"),
    ) ?? null
  );
}

/**
 * The plan K1 opens for a day: the current one, else the newest plan if it's a superseded draft
 * (shown dimmed with why, so the planner doesn't lose the work silently).
 */
export function planOfDay(plans: readonly PlanSummary[]): PlanSummary | null {
  const current = currentPlan(plans);
  if (current) return current;
  const newest = dayPlans(plans)[0];
  return newest && newest.state === "superseded" && newest.superseded ? newest : null;
}

export function planView(
  input: Readonly<{
    notSetUp: readonly string[] | null;
    runId: string | null;
    draft: RemoteState<Draft> | null;
    plans: RemoteState<{ plans: readonly PlanSummary[] }>;
    plan: RemoteState<PlanDetail> | null;
    demand?: DayDemand | null;
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
        return { kind: "interrupted", phase: run.phase, stoppedAt: run.stopped_at };
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
  if (!planOfDay(input.plans.value.plans))
    return {
      kind: "no_draft",
      last: dayPlans(input.plans.value.plans)[0] ?? null,
      demand: input.demand ?? null,
    };
  const p = input.plan;
  if (!p || p.status === "loading") return { kind: "loading" };
  if (p.status === "failed") return { kind: "failed", error: p.error };
  return { kind: "plan", plan: p.value, fromRun: false };
}
