import { plural } from "@/ui";
import type { PlanDetail } from "./api.ts";

/** What the callout needs of a plan: the server's execution counts (#793, api cf3cd37a). */
type BookedPlan = Readonly<{ execution: PlanDetail["execution"] }>;

/** K1/K2 interrupted execution: the callout and whether anything is left to continue. */
export type BookingStopped = Readonly<{
  text: string;
  tone: "info" | "stale";
  /** Requests not yet sent; null when the plan has no execution counts. 0 = nothing to continue. */
  left: number | null;
}>;

/** The provider(s) to wait on, by the names the server lists for the plan's bookings. */
function waitingOn(names: readonly string[]): string {
  if (names.length === 1) return names[0] ?? "the provider";
  return names.length > 1 ? "the providers" : "the provider";
}

/**
 * U20 + ux 1a906155 (ScheduleFlow K1 table), from the plan's `execution` counts: exact at any
 * fleet size (#793), never counted in the client. Nothing left to send reads as waiting on the
 * provider. A plan without counts (it hasn't executed) says only what is known.
 */
export function bookingStopped(plan: BookedPlan): BookingStopped {
  const e = plan.execution;
  if (!e)
    return { text: "Booking stopped before every request went out.", tone: "stale", left: null };
  const who = waitingOn(e.provider_names);
  if (e.never_sent > 0)
    return {
      text: `Booking stopped. ${plural(e.sent, "request")} went out; ${e.never_sent} didn't.`,
      tone: "stale",
      left: e.never_sent,
    };
  const what = e.sent === 1 ? "The request went out" : `All ${e.sent} requests went out`;
  return { text: `${what} · waiting for ${who} to confirm.`, tone: "info", left: 0 };
}
