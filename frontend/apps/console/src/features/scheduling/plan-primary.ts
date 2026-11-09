import type { RouteLocationRaw } from "vue-router";
import { plural } from "@/ui";
import { coverage, spacecraftNotCovered } from "./coverage.ts";
import type { PlanDetail } from "./api.ts";

/**
 * The one primary per plan state (ScheduleFlow "K1 plan states"): a sheet, an execute call, a
 * link, a disabled action with its reason, or nothing.
 */
export type PlanPrimary =
  | { kind: "sheet"; label: string; confirm: string }
  | { kind: "execute"; label: string }
  | { kind: "link"; label: string; to: RouteLocationRaw }
  | { kind: "blocked"; label: string; reason: string }
  | { kind: "none"; note: string | null };

export function planPrimary(plan: PlanDetail, isAdmin: boolean): PlanPrimary {
  const n = plan.counts.passes;
  const gaps = coverage(plan).gaps;
  switch (plan.state) {
    case "draft": {
      if (plan.conflicts.length > 0)
        return {
          kind: "blocked",
          label: "Submit",
          reason: `${plural(plan.conflicts.length, "conflict")}. Move or remove a pass to submit.`,
        };
      if (n === 0) return { kind: "blocked", label: "Submit", reason: "The draft has no passes." };
      const label = isAdmin
        ? gaps > 0
          ? `Accept ${plural(gaps, "gap")} and submit`
          : `Submit and book ${plural(n, "pass", "passes")}`
        : gaps > 0
          ? `Accept ${plural(gaps, "gap")} and request approval`
          : "Request approval";
      const confirm = isAdmin
        ? `This approves the plan and books ${n} passes with the providers.`
        : "An organization admin reviews it before anything is booked.";
      return { kind: "sheet", label, confirm };
    }
    case "pending_approval":
      return isAdmin
        ? {
            kind: "sheet",
            label:
              gaps > 0
                ? `Accept ${plural(gaps, "gap")}, approve and book`
                : `Approve and book ${plural(n, "pass", "passes")}`,
            confirm: `This approves the plan and books ${n} passes with the providers.`,
          }
        : { kind: "none", note: "Waiting for an organization admin to approve." };
    case "approved":
      return { kind: "execute", label: `Book ${plural(n, "pass", "passes")}` };
    case "interrupted":
      return { kind: "execute", label: "Continue booking" };
    case "executing":
      return {
        kind: "none",
        note: "Booking with the providers. Confirmations arrive on this plan.",
      };
    case "partially_reserved":
    case "failed":
      return {
        kind: "link",
        label: "Re-plan after provider changes",
        to: { name: "ops.contacts.replan", query: { plan: plan.id } },
      };
    case "reserved":
      return { kind: "link", label: "Open Contacts", to: { name: "ops.contacts" } };
    case "canceled":
    case "superseded":
      return { kind: "none", note: "This plan is no longer current." };
  }
}

/** Header mono tail per plan state. */
export function planHeaderTail(plan: PlanDetail): string {
  switch (plan.state) {
    case "draft": {
      if (plan.conflicts.length > 0) return plural(plan.conflicts.length, "conflict");
      const c = coverage(plan);
      return c.spacecraft > 0 ? spacecraftNotCovered(c.spacecraft) : "ready";
    }
    case "pending_approval":
      return "waiting for an admin";
    case "approved":
      return "approved";
    case "executing":
      return "booking";
    case "interrupted":
      return "booking stopped";
    case "reserved":
      return "booked";
    case "partially_reserved":
      return "partly booked";
    case "failed":
      return "booking failed";
    case "canceled":
      return "canceled";
    case "superseded":
      return "superseded";
  }
}
