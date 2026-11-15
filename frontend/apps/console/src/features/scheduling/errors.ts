import {
  decoders as d,
  describeApiError,
  detailsOf,
  isError,
  knownErrorCode,
  outcomeUnknown,
  type ApiError,
  type ErrorCode,
} from "@/api";
import { lifecycleRefusal } from "./lifecycle.ts";

/** U36 race: `details.decided_by` names who decided the version (api, once shipped). */
const decidedBy = d.object({ decided_by: d.object({ name: d.nullable(d.string) }) });

/** Plain words for scheduling refusals the planner can act on; anything else falls back. */
const MESSAGES: Readonly<Partial<Record<ErrorCode, string>>> = {
  fleet_planning_requirement_not_active:
    "Contact rules aren't active for this day. Check them in Setup › Contact planning.",
  planning_not_set_up:
    "Contact planning isn't set up yet: it needs a planning policy and at least one contact rule.",
  horizon_exceeds_policy:
    "This day is outside the planning policy's horizon. Pick a nearer day or extend the policy.",
  inputs_changed: "Planning inputs changed while you were drafting. Draft again.",
  fleet_repair_horizon_exceeded:
    "That re-plan window is longer than the planning policy allows. Narrow it to the lost bookings.",
  plan_changed: "Someone changed this plan meanwhile. It's reloaded; check it and try again.",
  plan_superseded:
    "Contact rules changed since this draft, so it's superseded and can't be submitted. Draft the day again.",
  plan_not_pending: "This plan isn't waiting for approval any more. It's reloaded.",
  plan_not_editable: "This plan can't be edited in its current state.",
  plan_not_submittable: "This plan can't be submitted in its current state.",
  plan_not_resumable: "Booking can't be resumed for this plan.",
  draft_not_interrupted: "This draft is still running; there's nothing to continue.",
};

/**
 * qa #19 (fe-setup's outcomeUnknown): every K1/K2 caller is a write that may have committed
 * before a 5xx, a dropped connection or a garbled answer. Say it's unclear; the plan is reloaded.
 */
const UNCLEAR =
  "Cadence didn't get a clear answer, so this may or may not have gone through. The plan is reloaded: check it before trying again.";

export function planErrorText(error: ApiError): string {
  if (outcomeUnknown(error)) return UNCLEAR;
  // U61: refusals with their own words (and an Open / Plan-the-rest action for the screen).
  const refusal = lifecycleRefusal(error);
  if (refusal) return refusal.text;
  // U36: after resubmission exists, this only means someone decided the version meanwhile.
  if (isError(error, "contact_plan_version_already_decided")) {
    const by = detailsOf(error, decidedBy)?.decided_by.name ?? null;
    const sentence = `This version was already decided${by ? ` by ${by}` : ""}`;
    return `${sentence}${sentence.endsWith(".") ? "" : "."} Reload to see it.`;
  }
  const code = knownErrorCode(error);
  return (code && MESSAGES[code]) ?? describeApiError(error);
}

/** 409 plan_superseded: the draft's rules changed on read (U27); the screen shows the superseded state. */
export function isPlanSuperseded(error: ApiError): boolean {
  return error.kind === "conflict" && isError(error, "plan_superseded");
}
