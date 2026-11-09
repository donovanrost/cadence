import { describeApiError, type ApiError } from "@/api";

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
  plan_not_editable: "This plan can't be edited in its current state.",
  plan_not_submittable: "This plan can't be submitted in its current state.",
  plan_not_resumable: "Booking can't be resumed for this plan.",
  draft_not_interrupted: "This draft is still running; there's nothing to continue.",
};

export function planErrorText(error: ApiError): string {
  const code = "code" in error ? error.code : null;
  return (code && MESSAGES[code]) ?? describeApiError(error);
}
