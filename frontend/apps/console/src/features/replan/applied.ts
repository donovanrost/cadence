import { plural } from "@/ui";
import type { Passes } from "@/features/contacts/index.ts";
import type { PlanDetail } from "@/features/scheduling/index.ts";

/**
 * An applied repair proposal books only: S8 keeps every committed pass locked, so moves and
 * adds are bookings and drops send nothing (no cancellations to name, ux rule (a)).
 */
export function bookingRequests(
  diff: Readonly<{ moved: readonly unknown[]; added: readonly unknown[] }>,
): number {
  return diff.moved.length + diff.added.length;
}

/**
 * ux (b) / U20: the stale line for an interrupted execution. Counts only when the passes read
 * covers every request the plan sends (not truncated, every unlocked pass inside its window);
 * otherwise say what is known.
 */
export function bookingStoppedText(plan: PlanDetail, read: Passes | null): string {
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
