import { describeApiError, type ApiError } from "@/api";

/** K2's known rejections in words (S8 / S5 / CP), falling back to the server's message. */
export function replanErrorText(error: ApiError): string {
  const code = "code" in error && typeof error.code === "string" ? error.code : null;
  switch (code) {
    case "plan_not_repairable":
      return "This plan can't be re-planned now: only executing, partially reserved or failed plans can.";
    case "planning_not_set_up":
      return "Contact planning isn't set up: the scheduler needs an active policy and contact rules. Open Setup › Contact planning.";
    case "fleet_planning_requirement_not_active":
      return "A contact rule this plan depends on isn't active any more. Check Setup › Contact planning, then try again.";
    case "inputs_changed":
      return "The plan's inputs changed while proposing. Try again.";
    case "plan_changed":
      return "The proposal changed since you opened it. It has been reloaded; review it and apply again.";
    case "plan_not_ready":
      return "The proposal isn't ready to apply: resolve its conflicts or acknowledge the gaps.";
    case null:
    default:
      return describeApiError(error);
  }
}
