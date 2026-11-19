import type { RouteLocationRaw } from "vue-router";
import { formatCount, plural } from "@/ui";
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
  // U61 (ux 366240d64): approved but booking never started, or a booking run that stopped. These
  // keep their words past the first window (the plan is approved); only the mark turns crit.
  if (a.plan?.state === "approved") return `Plan for ${d} is approved but booking hasn't started`;
  if (a.plan?.state === "interrupted") return `Booking for ${d} stopped`;
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
  const stalled = stalledEvidence(a, now);
  if (stalled) return stalled;
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

/**
 * ux 366240d64 / 11fe550bf: 'R41 was approved at 22:10Z, but booking hasn't started. …' and
 * 'Booking for R41 stopped with 12 of 41 passes booked; its last progress was at 22:14Z. …'.
 */
function stalledEvidence(a: Attention, now: Date): string | null {
  const p = a.plan;
  if (!p) return null;
  if (p.state === "approved") {
    const at = p.approved_at ? ` at ${short(p.approved_at, now)}` : "";
    return `${rev(a)} was approved${at}, but booking hasn't started. Nothing is booked for ${requirements(a)} until it does.`;
  }
  if (p.state !== "interrupted") return null;
  const b = p.booking;
  const last = b?.last_progress_at
    ? `; its last progress was at ${short(b.last_progress_at, now)}`
    : "";
  if (!b || b.reserved === 0)
    return `Booking for ${rev(a)} stopped before any pass was booked${last}.`;
  return `Booking for ${rev(a)} stopped with ${b.reserved} of ${b.total} passes booked${last}. The other ${b.total - b.reserved} aren't booked until it continues.`;
}

/** #268: the passes a Book would send, from the server (never counted here); undefined: older. */
const bookable = (a: Attention) => a.plan?.booking?.bookable;
const stalledPlan = (a: Attention) =>
  a.plan?.state === "approved" || a.plan?.state === "interrupted";

/**
 * Book (POST …/execute) for whoever the server lets book (U61; #268, ux): 'Book 40 passes' when
 * booking hasn't started, 'Book the other 29' when it stopped. Nothing left to book: no command,
 * the row says why (ca-security). An older server without the count keeps Start / Continue.
 */
export function bookingCommand(a: Attention): QueueItem["command"] | null {
  const s = a.plan?.state;
  if (a.viewer_can_book !== true || !stalledPlan(a)) return null;
  const n = bookable(a);
  if (n === 0) return null;
  const label =
    n === undefined
      ? s === "approved"
        ? "Start booking"
        : "Continue booking"
      : s === "approved"
        ? `Book ${plural(n, "pass", "passes")}`
        : `Book the other ${formatCount(n)}`;
  return { label, kind: "book", targets: [a] };
}

/**
 * #268 (ux): every remaining pass's booking window has closed, so there's nothing to book. The line
 * stands in for the action; K1's action is the button.
 */
function closedLine(a: Attention): string {
  const b = a.plan?.booking;
  const left = b ? b.total - b.reserved : null;
  const which =
    left === 1
      ? `${rev(a)}'s only remaining pass`
      : left !== null && left > 1
        ? `all ${formatCount(left)} of ${rev(a)}'s remaining passes`
        : `all of ${rev(a)}'s remaining passes`;
  return `The booking window has closed for ${which}, so nothing can be booked.`;
}

/** K1's next step for a day: Draft a new plan before it starts, Plan the rest once it has. */
function k1Action(a: Attention, now: Date): Readonly<{ label: string; to: RouteLocationRaw }> {
  const day = a.day ?? "";
  const started = now.toISOString().slice(0, 10) >= day;
  return {
    label: started
      ? `Plan the rest of ${dayLabel(a.day)}…`
      : `Draft a new plan for ${dayLabel(a.day)}…`,
    to: { name: "ops.contacts.plan", query: { day } },
  };
}

/** The one action (U61): Review / Open plan / Plan <day> / Plan the rest of <day>. */
export function coverageAction(a: Attention): Readonly<{ label: string; to: RouteLocationRaw }> {
  const day = a.day ?? "";
  const d = dayLabel(a.day);
  const planDay: RouteLocationRaw = { name: "ops.contacts.plan", query: { day } };
  const stalled = a.plan?.state === "approved" || a.plan?.state === "interrupted";
  if (crit(a) && !stalled) return { label: `Plan the rest of ${d}`, to: planDay };
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
  const nothingLeft = stalledPlan(a) && bookable(a) === 0;
  const action = nothingLeft ? k1Action(a, now) : coverageAction(a);
  const book = bookingCommand(a);
  return {
    ...base,
    ...(book ? { command: book } : {}),
    // crit ◆ once the first window opens unplanned (the server ranks P1/P2).
    ...(crit(a) ? { state: "crit" as const } : {}),
    key,
    title: coverageTitle(a),
    titleTo: action.to,
    sentence: nothingLeft ? closedLine(a) : coverageEvidence(a, viewerId, now),
    meta: coverageMeta(a, now),
    action,
    ...(!crit(a) && a.first_window_at ? { due: { label: "", at: a.first_window_at } } : {}),
    // A review for an approver is the row's point; make it primary.
    ...(action.label === "Review" ? { primary: true } : {}),
  };
}
