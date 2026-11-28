import { formatCount, formatShort } from "@/ui";
import type { AffectedGroup } from "./api.ts";

/**
 * E2c (#546, #1054): the words for a withdrawn revision's GO'd requests still waiting to go out,
 * so the person who withdrew it can open one and abort it.
 */

/** "On EARENDIL-001, EARENDIL-002 and 3 more"; a craft with no name is "Unknown spacecraft" (U25). */
export function craftLine(g: AffectedGroup): string {
  const names = g.spacecraft.map((s) => s.name?.trim() || "Unknown spacecraft");
  const more = g.spacecraft_count - names.length;
  if (more > 0) return `On ${names.join(", ")} and ${formatCount(more)} more`;
  if (names.length <= 1) return names.length ? `On ${names[0]}` : "";
  return `On ${names.slice(0, -1).join(", ")} and ${names.at(-1) ?? ""}`;
}

/** "GO at 11-27 10:02Z". */
export const goLine = (g: AffectedGroup) => `GO at ${formatShort(new Date(g.go_at))}`;

/** The panel's meta: "3 requests", "50 of 64 shown". */
export function affectedMeta(shown: number, total: number): string {
  if (shown < total) return `${formatCount(shown)} of ${formatCount(total)} shown`;
  return total === 1 ? "1 request" : `${formatCount(total)} requests`;
}

export const AFFECTED_INTRO =
  "These requests had their GO before the approval was withdrawn, and their uplinks to these craft haven't gone out. An unattended release now refuses them; open a request to abort it.";

export const AFFECTED_NONE = "No request with a GO is waiting to go out on craft that run it.";
