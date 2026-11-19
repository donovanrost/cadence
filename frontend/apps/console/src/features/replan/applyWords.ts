import { plural } from "@/ui";
import { coverage, type PlanDetail } from "@/features/scheduling/index.ts";
import type { ReviewAct } from "@/features/scheduling/review-run.ts";

export type ApplyWords = Readonly<{
  act: ReviewAct;
  label: string;
  title: string;
  confirm: string;
}>;

/**
 * #257 (U97): Re-plan's Apply. Under "Applies without approval" an org admin's one act sends the
 * proposal and approves it; everyone else (and a missing or unknown setting) requests approval. An
 * org admin on a proposal that already waits approves it (approve only). `requests`: what Apply
 * sends (U28: moves and adds).
 */
export function applyWords(plan: PlanDetail, isAdmin: boolean, requests: number): ApplyWords {
  const gaps = coverage(plan).gaps;
  const sends = plural(requests, "booking request");
  if (isAdmin && plan.state === "pending_approval")
    return {
      act: "approve",
      label:
        gaps > 0
          ? `Accept ${plural(gaps, "gap")}, approve and apply`
          : "Approve and apply the proposal",
      title: "Approve and apply the proposal",
      confirm: `This approves the proposal and sends ${sends}.`,
    };
  if (isAdmin && plan.approval_setting === "direct")
    return {
      act: "submit_approve",
      label:
        gaps > 0
          ? `Accept ${plural(gaps, "gap")}, approve and apply`
          : "Approve and apply the proposal",
      title: "Approve and apply the proposal",
      confirm: `This sends the proposal and approves it, and sends ${sends}.`,
    };
  return {
    act: "submit",
    label:
      gaps > 0
        ? `Accept ${plural(gaps, "gap")} and request approval`
        : "Request approval for the proposal",
    title: "Request approval for the proposal",
    confirm:
      "This sends the proposal for approval; another org admin approves it before anything is booked.",
  };
}
