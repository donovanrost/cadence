import type { RouteLocationRaw } from "vue-router";
import { plural } from "@/ui";
import { coverage, spacecraftNotCovered } from "./coverage.ts";
import { isStationConflict } from "./unavailable.ts";
import { byAuthor, type PlanDetail } from "./api.ts";

/**
 * The one primary per plan state (ScheduleFlow "K1 plan states"): a sheet, an execute call, a
 * link, a disabled action with its reason, or nothing.
 */
export type PlanPrimary =
  | { kind: "sheet"; label: string; confirm: string }
  | { kind: "execute"; label: string }
  | { kind: "link"; label: string; to: RouteLocationRaw }
  | { kind: "redraft"; label: string }
  | { kind: "blocked"; label: string; reason: string }
  | { kind: "none"; note: string | null };

/**
 * `openRepairRun`: the run of an open K2 proposal repairing this plan (U28), which the re-plan
 * link opens. `requestsLeft`: from `bookingStopped` on an interrupted plan; 0 = nothing left to
 * send, so no Continue booking (ux 1a906155).
 */
export function planPrimary(
  plan: PlanDetail,
  isAdmin: boolean,
  options: Readonly<{ openRepairRun?: string | null; requestsLeft?: number | null }> = {},
): PlanPrimary {
  const openRepairRun = options.openRepairRun ?? null;
  const n = plan.counts.passes;
  const gaps = coverage(plan).gaps;
  switch (plan.state) {
    case "draft": {
      const overlaps = plan.conflicts.filter((c) => !isStationConflict(c)).length;
      const onDownStation = plan.conflicts
        .filter(isStationConflict)
        .flatMap((c) => c.snapshot_ids).length;
      if (overlaps > 0)
        return {
          kind: "blocked",
          label: "Submit",
          reason: `${plural(overlaps, "conflict")}. Move or remove a pass to submit.`,
        };
      if (onDownStation > 0)
        return {
          kind: "blocked",
          label: "Submit",
          reason: `${plural(onDownStation, "drafted pass", "drafted passes")} on a station that's down. Move or remove ${onDownStation === 1 ? "it" : "them"} to submit.`,
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
      return options.requestsLeft === 0
        ? { kind: "none", note: "Nothing left to send." }
        : { kind: "execute", label: "Continue booking" };
    case "executing":
      return {
        kind: "none",
        note: "Booking with the providers. Confirmations arrive on this plan.",
      };
    case "partially_reserved":
    case "failed":
      return openRepairRun
        ? {
            kind: "link",
            label: "Open the re-plan proposal",
            to: { name: "ops.contacts.replan", query: { plan: plan.id, run: openRepairRun } },
          }
        : {
            kind: "link",
            label: "Re-plan after provider changes",
            to: { name: "ops.contacts.replan", query: { plan: plan.id } },
          };
    case "reserved":
      return { kind: "link", label: "Open Contacts", to: { name: "ops.contacts" } };
    case "superseded":
      return { kind: "redraft", label: "Draft again with the current rules" };
    case "canceled":
      return { kind: "none", note: "This plan is no longer current." };
  }
}

/** Header mono tail per plan state. */
export function planHeaderTail(plan: PlanDetail): string {
  switch (plan.state) {
    case "draft": {
      const conflicts = plan.conflicts.length;
      if (conflicts > 0) return plural(conflicts, "conflict");
      const c = coverage(plan);
      const atRisk = plan.at_risk.flatMap((r) => r.snapshot_ids).length;
      const base = c.spacecraft > 0 ? spacecraftNotCovered(c.spacecraft) : "ready";
      return atRisk > 0 ? `${base} · ${atRisk} at risk` : base;
    }
    case "pending_approval":
      // ux: the approver needs the author (reviewer ≠ author).
      return plan.author
        ? `waiting for an admin · drafted${byAuthor(plan.author, "automatic draft")}`
        : "waiting for an admin";
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
