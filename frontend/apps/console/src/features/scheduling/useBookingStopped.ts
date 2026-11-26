import { computed, type Ref } from "vue";
import type { PlanDetail } from "./api.ts";
import { bookingStopped, type BookingStopped } from "./booking.ts";

/**
 * The execution callout for `plan`, from its own execution counts (#793): the plan read refetches
 * on `contacts` and `contact_plans` invalidations, so no passes read is needed. DECISIONS #52:
 * `interrupted` means some requests never went out (stale line + Continue); `executing` with every
 * request out is waiting on the provider and keeps the "All N went out · waiting for X to confirm"
 * info line. Null otherwise.
 */
export function useBookingStopped(plan: Readonly<Ref<PlanDetail | null>>) {
  return computed<BookingStopped | null>(() => {
    const p = plan.value;
    if (p?.state !== "interrupted" && p?.state !== "executing") return null;
    const result = bookingStopped(p);
    // Still sending: the footer's "Booking with the providers" note says it; no callout.
    return p.state === "executing" && result.left !== 0 ? null : result;
  });
}
