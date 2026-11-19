import type { RouteLocationRaw } from "vue-router";
import { formatCount, plural } from "@/ui";
import { coverage, spacecraftNotCovered } from "./coverage.ts";
import { isStationConflict } from "./unavailable.ts";
import { unconfirmedTail } from "./unconfirmed.ts";
import { byAuthor, type PlanDetail } from "./api.ts";

/**
 * The one primary per plan state (ScheduleFlow "K1 plan states"): a sheet, an execute call, a
 * link, a disabled action with its reason, or nothing.
 */
export type PlanPrimary =
  | { kind: "sheet"; label: string; title: string; confirm: string }
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
      // U36: a sent-back draft is submitted again as is (the server cuts the next version).
      const again = plan.approval?.decision === "rejected";
      const label = isAdmin
        ? gaps > 0
          ? `Accept ${plural(gaps, "gap")} and submit${again ? " again" : ""}`
          : `Submit${again ? " again" : ""} and book ${plural(n, "pass", "passes")}`
        : gaps > 0
          ? `Accept ${plural(gaps, "gap")} and ${again ? "submit again" : "request approval"}`
          : again
            ? "Submit again"
            : "Request approval";
      const confirm = isAdmin
        ? `This approves the plan and books ${n} passes with the providers.`
        : "An organization admin reviews it before anything is booked.";
      return { kind: "sheet", label, title: sheetTitle(isAdmin, again), confirm };
    }
    case "pending_approval":
      return isAdmin
        ? {
            kind: "sheet",
            label:
              gaps > 0
                ? `Accept ${plural(gaps, "gap")}, approve and book`
                : `Approve and book ${plural(n, "pass", "passes")}`,
            title: sheetTitle(true, false),
            confirm: `This approves the plan and books ${n} passes with the providers.`,
          }
        : { kind: "none", note: "Waiting for an organization admin to approve." };
    case "approved":
      return { kind: "execute", label: `Book ${plural(n, "pass", "passes")}` };
    case "unconfirmed":
      // #52/U30: the server refuses Execute and nothing is re-sent; the callout says why.
      return { kind: "none", note: null };
    case "unrecognized":
      return { kind: "none", note: "This console doesn't know the plan's state yet." };
    case "interrupted":
      return options.requestsLeft === 0
        ? { kind: "none", note: null } // the info callout says it (ux: no second line)
        : { kind: "execute", label: "Continue booking" };
    case "executing":
      return {
        kind: "none",
        note: "Booking with the providers. Confirmations arrive on this plan.",
      };
    case "partially_reserved":
      // Mid-settle (qa): confirmations still arriving and nothing lost yet; nothing to re-plan.
      return plan.execution && plan.execution.uncertain > 0 && lost(plan.execution) === 0
        ? { kind: "none", note: null }
        : replanLink(plan.id, openRepairRun);
    case "failed":
      return replanLink(plan.id, openRepairRun);
    case "reserved":
      return { kind: "link", label: "Open Contacts", to: { name: "ops.contacts" } };
    case "superseded":
      return { kind: "redraft", label: "Draft again with the current rules" };
    case "canceled":
      return { kind: "none", note: "This plan is no longer current." };
  }
}

/**
 * The sheet's title names the act, as the button does, without the count (U36, ux): an admin
 * approves and books whatever the draft's round; anyone else asks for approval, or again.
 * With gaps the sheet titles itself 'Accept 2 gaps · …' instead.
 */
const sheetTitle = (isAdmin: boolean, again: boolean) =>
  isAdmin ? "Approve and book the plan" : again ? "Submit the plan again" : "Request approval";

/**
 * ux (b30600e7 follow-up): sending and confirming overlap. While requests still go out:
 * 'booking · 812 of 1,512 sent · 300 booked'; all sent: 'booking · 1,490 of 1,512 booked';
 * settled: '1,490 of 1,512 booked'.
 */
function bookingProgress(e: NonNullable<PlanDetail["execution"]>): string {
  const of = (n: number) => `${formatCount(n)} of ${formatCount(e.requested)}`;
  if (e.never_sent > 0)
    return `booking · ${of(e.sent)} sent${e.confirmed > 0 ? ` · ${formatCount(e.confirmed)} booked` : ""}`;
  return e.uncertain > 0 ? `booking · ${of(e.confirmed)} booked` : `${of(e.confirmed)} booked`;
}

/** K2 entry: the open proposal's run when there is one (U28), else a new re-plan. */
function replanLink(planId: string, openRepairRun: string | null): PlanPrimary {
  return openRepairRun
    ? {
        kind: "link",
        label: "Open the re-plan proposal",
        to: { name: "ops.contacts.replan", query: { plan: planId, run: openRepairRun } },
      }
    : {
        kind: "link",
        label: "Re-plan after provider changes",
        to: { name: "ops.contacts.replan", query: { plan: planId } },
      };
}

/** Bookings the provider rejected or lost: what a re-plan would act on. */
const lost = (e: NonNullable<PlanDetail["execution"]>) => e.rejected + e.failed;

/** Header mono tail per plan state, plus U30's `· 4 unconfirmed` on any state that has them. */
export function planHeaderTail(plan: PlanDetail): string {
  const unconfirmed = unconfirmedTail(plan);
  if (!unconfirmed) return stateTail(plan);
  return plan.state === "unconfirmed" || plan.state === "partially_reserved"
    ? unconfirmed
    : `${stateTail(plan)} · ${unconfirmed}`;
}

function stateTail(plan: PlanDetail): string {
  switch (plan.state) {
    case "draft": {
      const conflicts = plan.conflicts.length;
      if (conflicts > 0) return plural(conflicts, "conflict");
      const c = coverage(plan);
      const atRisk = plan.at_risk.flatMap((r) => r.snapshot_ids).length;
      const base = c.spacecraft > 0 ? spacecraftNotCovered(c.spacecraft) : "ready";
      return atRisk > 0 ? `${base} · ${atRisk} at risk` : base;
    }
    case "pending_approval": {
      // ux: the approver needs the author (reviewer ≠ author). U36: a later round says so.
      const state =
        (plan.submission?.round ?? 1) > 1
          ? plan.submission?.unchanged
            ? "resubmitted unchanged"
            : "resubmitted"
          : "waiting for an admin";
      return plan.author ? `${state} · drafted${byAuthor(plan.author, "automatic draft")}` : state;
    }
    case "approved":
      return "approved";
    case "executing":
      return plan.execution ? bookingProgress(plan.execution) : "booking";
    case "interrupted":
      // ScheduleFlow: 'BOOKING STOPPED · 812 OF 1,512' (sent of requested).
      return plan.execution
        ? `booking stopped · ${formatCount(plan.execution.sent)} of ${formatCount(plan.execution.requested)}`
        : "booking stopped";
    case "reserved":
      return "booked";
    case "partially_reserved":
      // Also the state while confirmations arrive (qa), so it reads as progress until settled.
      return plan.execution ? bookingProgress(plan.execution) : "partly booked";
    case "failed":
      return "booking failed";
    case "canceled":
      return "canceled";
    case "superseded":
      return "superseded";
    case "unconfirmed":
      return "unconfirmed";
    case "unrecognized":
      return "state not recognized";
  }
}
