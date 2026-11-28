import { plural } from "@/ui";
import type { Group, GroupMember, GroupTarget } from "./show.ts";
import { memberStageWord, shortWhen } from "./words.ts";

/**
 * ux U75 (b383e4653, DECISIONS #97): a request has one expires_at, so its unreleased uplinks all
 * expire together (api: stage canceled, end_reason expired). Nothing is held.
 */
export const isExpired = (m: Pick<GroupMember, "stage" | "end_reason">) =>
  m.stage === "canceled" && m.end_reason === "expired";

/** A target whose own stage is an expired uplink (its tag reads 'Expired', its cell dashed). */
export const targetExpired = (t: GroupTarget) =>
  t.members.some((m) => m.stage === t.stage && isExpired(m));

/** A target's tag word: its stage, read with the end reason of the member at that stage. */
export const targetStageWord = (t: GroupTarget, group: Pick<Group, "state">) =>
  memberStageWord(t.stage, group.state, t.members.find((m) => m.stage === t.stage)?.end_reason);

export function expiryCounts(group: Group): { sent: number; expired: number; total: number } {
  // api's own counts (U75), so the line and the list row agree. null: nothing expired (#795: the
  // targets on screen are a page, never the whole request, so they aren't counted here).
  if (group.expiry)
    return { sent: group.expiry.sent, expired: group.expiry.expired, total: group.expiry.total };
  return { sent: 0, expired: 0, total: group.member_count };
}

/**
 * The request summary (ux U75): 'The request expired at 04:00Z after 2 of 5 uplinks went out. The
 * other 3 weren't sent.' / 'The request expired at 04:00Z before any uplink went out.'; null when
 * nothing expired.
 */
export function expirySummary(group: Group, now: Date = new Date()): string | null {
  const { sent, expired, total } = expiryCounts(group);
  if (expired === 0) return null;
  const at = group.expiry?.expires_at ?? group.release?.expires_at;
  // §4: the date when it isn't today (ux).
  const when = at ? ` at ${shortWhen(at, now)}` : "";
  if (sent === 0) return `The request expired${when} before any uplink went out.`;
  return `The request expired${when} after ${sent} of ${plural(total, "uplink")} went out. The other ${expired} weren't sent.`;
}
