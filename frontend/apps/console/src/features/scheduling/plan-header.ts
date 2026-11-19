import { runPhaseText } from "./api.ts";
import { planHeaderTail } from "./plan-primary.ts";
import type { PlanView } from "./plan-state.ts";

/** Header mono line per state (ScheduleFlow "K1 plan states"). */
export function headerFor(v: PlanView, d: string): string {
  switch (v.kind) {
    case "not_set_up":
      return "Contact plan · not set up";
    case "no_draft":
      return `Contact plan · ${d} · no draft`;
    case "drafting":
      return `Drafting · ${v.phase ? runPhaseText(v.phase) : "queued"}`;
    case "interrupted":
      return "Drafting stopped";
    case "draft_failed":
    case "failed":
      return `Contact plan · ${d}`;
    case "loading":
      return `Contact plan · ${d}`;
    case "plan":
      return v.plan.superseded
        ? `Contact plan · R${v.plan.version} draft · superseded`
        : // ScheduleFlow K1 table: 'R41 DRAFT · READY', otherwise 'R41 · <tail>' (the tail names
          // the state), so the line stays short enough not to truncate (qa: the U30 count was cut).
          `Contact plan · R${v.plan.version}${v.plan.state === "draft" ? " draft" : ""} · ${planHeaderTail(v.plan)}`;
  }
}
