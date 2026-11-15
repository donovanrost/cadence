import type { RouteLocationRaw } from "vue-router";
import { formatCount } from "@/ui";
import { short, type Attention } from "./attention.ts";
import type { QueueItem } from "./queue.ts";

/**
 * plan_coverage (ux U61; domain 47aabe3ba, api's wire, fe-setup's reader): a UTC day whose first
 * contact window nears with no approved plan, so NOTHING IS BOOKED for it. One item per day; the
 * countdown (due = the first window) raises it, and it turns crit once that window opens. Nothing to
 * acknowledge: the item goes when the day gets an approved plan, has nothing left, or ends.
 */

/** "11-16" from the item's `YYYY-MM-DD`. */
export const dayLabel = (day: string | null | undefined) => (day ? day.slice(5, 10) : "this day");

const names = (people: readonly Readonly<{ name: string | null }>[] | null | undefined) => {
  const n = (people ?? []).map((p) => p.name).filter((x): x is string => !!x);
  return n.length <= 1 ? (n[0] ?? null) : `${n.slice(0, -1).join(", ")} or ${n.at(-1) ?? ""}`;
};
const rev = (a: Attention) => (a.plan ? `R${a.plan.revision}` : "the plan");
const requirements = (a: Attention) =>
  `${dayLabel(a.day)}'s ${formatCount(a.requirements_count ?? 0)} requirements`;
const crit = (a: Attention) => a.severity === "crit";
const sentBack = (a: Attention) => a.plan?.state === "draft" && a.plan.sent_back != null;

export function coverageTitle(a: Attention): string {
  const d = dayLabel(a.day);
  if (crit(a)) return `${d} started with no approved plan`;
  if (!a.plan) return `${d} has no plan yet`;
  if (a.plan.state === "pending_approval") return `Plan for ${d} is awaiting approval`;
  if (sentBack(a)) return `Plan for ${d} was sent back`;
  return `Plan for ${d} is still a draft`;
}

/** `FIRST WINDOW 00:00Z · 1,512 REQUIREMENTS`; the row's live T− countdown follows it. */
export function coverageMeta(a: Attention, now: Date = new Date()): string | null {
  const parts = [
    a.first_window_at ? `First window ${short(a.first_window_at, now)}` : null,
    a.requirements_count != null ? `${formatCount(a.requirements_count)} requirements` : null,
  ].filter((p): p is string => p !== null);
  return parts.length ? parts.join(" · ").toUpperCase() : null;
}

/** Whether the viewer wrote the pending plan: they get the self-approval line. */
const isAuthor = (a: Attention, viewerId: string | null) =>
  viewerId !== null && a.plan?.author?.id === viewerId;

export function coverageEvidence(
  a: Attention,
  viewerId: string | null = null,
  now: Date = new Date(),
): string {
  const d = dayLabel(a.day);
  if (crit(a)) {
    const opened = a.first_window_at ? ` at ${short(a.first_window_at, now)}` : "";
    const open = formatCount(a.open_requirements_count ?? a.requirements_count ?? 0);
    const rest = `a new plan for the rest of the day can still book its ${open} open requirements.`;
    const head = `${d}'s first window opened${opened} and nothing is booked.`;
    return a.plan?.state === "pending_approval"
      ? `${head} ${rev(a)} can't be approved now; ${rest}`
      : `${head} ${rest.charAt(0).toUpperCase()}${rest.slice(1)}`;
  }
  if (!a.plan) return `Nothing is planned or booked for ${requirements(a)}.`;
  if (a.plan.state === "pending_approval") {
    const since = a.plan.submitted_at ? ` since ${short(a.plan.submitted_at, now)}` : "";
    const who = names(a.approvers);
    // A name may end in its own stop ("Owen P."); don't double it.
    // ux: who it waits on is the point, so the sentence stays even without names.
    const waiting = who
      ? ` Waiting on an org admin: ${who.replace(/\.$/, "")}.`
      : " Waiting on an org admin.";
    const self = isAuthor(a, viewerId) ? " You can't approve your own plan." : "";
    return `${rev(a)} has waited for approval${since}. Nothing is booked for ${requirements(a)} until it's approved.${waiting}${self}`;
  }
  const sb = a.plan.sent_back;
  if (sb) {
    const by = sb.by?.name ?? "A reviewer";
    const comment = sb.comment ? `: “${sb.comment.trim()}”` : ".";
    return `${by} sent ${rev(a)} back at ${short(sb.at, now)}${comment} Nothing is booked for ${requirements(a)} until a new plan is approved.`;
  }
  const author = a.plan.author?.name ? ` (${a.plan.author.name})` : "";
  return `${rev(a)}${author} hasn't been submitted. Nothing is booked for ${requirements(a)} until a plan is approved.`;
}

/** The one action (U61): Review / Open plan / Plan <day> / Plan the rest of <day>. */
export function coverageAction(a: Attention): Readonly<{ label: string; to: RouteLocationRaw }> {
  const day = a.day ?? "";
  const d = dayLabel(a.day);
  const planDay: RouteLocationRaw = { name: "ops.contacts.plan", query: { day } };
  if (crit(a)) return { label: `Plan the rest of ${d}`, to: planDay };
  if (!a.plan) return { label: `Plan ${d}`, to: planDay };
  const open: RouteLocationRaw = { name: "ops.contacts.plan", query: { day, plan: a.plan.id } };
  const review = a.plan.state === "pending_approval" && a.viewer_can_approve === true;
  return { label: review ? "Review" : "Open plan", to: open };
}

export function coverageRow(
  base: Pick<QueueItem, "priority" | "state" | "spacecraftIds">,
  key: string,
  a: Attention,
  viewerId: string | null = null,
  now: Date = new Date(),
): QueueItem {
  const action = coverageAction(a);
  return {
    ...base,
    // crit ◆ once the first window opens unplanned (the server ranks P1/P2).
    ...(crit(a) ? { state: "crit" as const } : {}),
    key,
    title: coverageTitle(a),
    titleTo: action.to,
    sentence: coverageEvidence(a, viewerId, now),
    meta: coverageMeta(a, now),
    action,
    ...(!crit(a) && a.first_window_at ? { due: { label: "", at: a.first_window_at } } : {}),
    // A review for an approver is the row's point; make it primary.
    ...(action.label === "Review" ? { primary: true } : {}),
  };
}
