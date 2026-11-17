import { codeOf, decoders as d, detailsOf, type ApiError } from "@/api";
import { noneLeftLine } from "./windowMeta.ts";

const attemptLimit = d.object({ used: d.integer, max: d.integer });
import { planErrorText } from "@/features/scheduling/index.ts";

/** K2's known rejections in words (S8 / S5 / CP), falling back to the server's message. */
export function replanErrorText(error: ApiError): string {
  const code = codeOf(error);
  switch (code) {
    case "plan_not_repairable":
      return "This plan can't be re-planned now: only executing, partially reserved or failed plans can.";
    case "planning_not_set_up":
      return "Contact planning isn't set up: the scheduler needs an active policy and contact rules. Open Setup › Contact planning.";
    case "fleet_planning_requirement_not_active":
      return "A contact rule this plan depends on isn't active any more. Check Setup › Contact planning, then try again.";
    case "fleet_repair_horizon_exceeded":
      return "That re-plan window is longer than the policy's repair window. Re-plan a shorter span around the lost bookings, or raise the repair window in Setup › Contact planning › Policy.";
    case "fleet_repair_attempt_limit_exceeded": {
      // U76: the same line as the header's, from the refusal's own counts when it carries them.
      const a = detailsOf(error, attemptLimit);
      return a ? noneLeftLine(a) : "No re-plan attempts left. The planning policy sets the limit.";
    }
    case "fleet_repair_horizon_invalid":
      return "That re-plan window can't be used. Propose again around the lost bookings.";
    case "plan_superseded":
      return "Nothing was booked: the rules behind this proposal changed since it was made. Propose again.";
    case "inputs_changed":
      return "The plan's inputs changed while proposing. Try again.";
    case "plan_changed":
      return "The proposal changed since you opened it. It has been reloaded; review it and apply again.";
    case "plan_not_ready":
      return "The proposal isn't ready to apply: resolve its conflicts or acknowledge the gaps.";
    case null:
    default:
      return planErrorText(error);
  }
}
