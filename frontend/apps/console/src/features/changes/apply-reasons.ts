import type { Preview } from "./actions.ts";
import { itemLine } from "./itemLines.ts";

/**
 * #310 (Changes.md K3; ca-ux 11-20): Apply's disabled reasons that name what stops it (A6).
 * - A NO-GO names its first item, as the checks word it: "Can't apply yet: <the NO-GO's line>".
 * - Without the apply capability, who can apply. Today a person who can stage can always apply
 *   (both need operate_mission), so this is the defensive line for a missing capability; it names
 *   no role, since U104 keeps role words to Org admin and Mission admin.
 */
export function noGoReason(preview: Preview, act: "apply" | "request_review" = "apply"): string {
  const item = preview.checks.find((c) => c.verdict === "no_go")?.items[0];
  // U79 (ca-ux, #554): the reason names the act its button names.
  const lead = act === "apply" ? "Can't apply yet" : "Can't send for review yet";
  return `${lead}: ${item ? itemLine(item) : "a check says NO-GO."}`;
}

export const cannotApplyLine = (missionName: string) =>
  `You can't apply changes on ${missionName}, so someone who can operate it applies them.`;
