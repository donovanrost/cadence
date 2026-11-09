import { plural } from "@/ui";
import type { PlanDetail } from "./api.ts";

/** What the count needs of a plan and of a passes read (contacts' `Passes` fits). */
type BookedPlan = Pick<PlanDetail, "id" | "passes">;
type PassesRead = Readonly<{
  from: string;
  to: string;
  truncated: boolean;
  passes: readonly Readonly<{ plan: Readonly<{ id: string }> | null }>[];
}>;

/**
 * U20 (ux ScheduleFlow, K1 and K2): the stale line for an interrupted execution. Counts only when
 * the passes read covers every request the plan sends (not truncated, every unlocked pass inside
 * its window); otherwise it says what is known. (Moved from K2's replan/applied.ts.)
 */
export function bookingStoppedText(plan: BookedPlan, read: PassesRead | null): string {
  const unknown = "Booking stopped before every request went out.";
  const wanted = plan.passes.filter((p) => !p.locked);
  if (!read || read.truncated || wanted.length === 0) return unknown;
  const from = Date.parse(read.from);
  const to = Date.parse(read.to);
  const covered = wanted.every((p) => {
    const t = Date.parse(p.starts_at);
    return t >= from && t < to;
  });
  if (!covered) return unknown;
  const out = read.passes.filter((p) => p.plan?.id === plan.id).length;
  const left = Math.max(wanted.length - out, 0);
  return `Booking stopped. ${plural(out, "request")} went out; ${left} didn't.`;
}

/** The passes-read window covering every request the plan sends, or null when it sends none. */
export function bookingWindow(plan: BookedPlan): { from: string; to: string } | null {
  const wanted = plan.passes.filter((p) => !p.locked);
  if (wanted.length === 0) return null;
  const starts = wanted.map((p) => Date.parse(p.starts_at));
  return {
    from: new Date(Math.min(...starts)).toISOString(),
    to: new Date(Math.max(...starts) + 1).toISOString(),
  };
}
