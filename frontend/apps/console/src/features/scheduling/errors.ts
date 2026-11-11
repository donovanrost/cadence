import { describeApiError, outcomeUnknown, type ApiError } from "@/api";

/** Plain words for scheduling refusals the planner can act on; anything else falls back. */
const MESSAGES: Readonly<Record<string, string>> = {
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
  contact_plan_version_already_decided:
    "This version was already decided (it was sent back), so it can't be submitted again as it is. Change the plan, then submit the new version.",
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
  const code = "code" in error ? error.code : null;
  return (code && MESSAGES[code]) ?? describeApiError(error);
}

/** 409 plan_superseded: the draft's rules changed on read (U27); the screen shows the superseded state. */
export function isPlanSuperseded(error: ApiError): boolean {
  return error.kind === "conflict" && error.code === "plan_superseded";
}
