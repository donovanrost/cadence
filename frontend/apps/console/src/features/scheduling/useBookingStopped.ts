import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchPasses } from "@/features/contacts/index.ts";
import { useMissionInvalidation } from "@/live";
import type { PlanDetail } from "./api.ts";
import { bookingStopped, bookingWindow, type BookingStopped } from "./booking.ts";

/**
 * The execution callout for `plan`, read from the passes over its unlocked passes (refetched on
 * `contacts` invalidations). DECISIONS #52: `interrupted` means some requests never went out
 * (stale line + Continue); `executing` with every request out is waiting on the provider and
 * keeps the "All N went out · waiting for X to confirm" info line. Null otherwise.
 */
export function useBookingStopped(
  missionId: Readonly<Ref<string>>,
  plan: Readonly<Ref<PlanDetail | null>>,
) {
  const watched = computed(() =>
    plan.value?.state === "interrupted" || plan.value?.state === "executing" ? plan.value : null,
  );
  // A string key, so a refetched plan (a new object) doesn't reload the passes read.
  const key = computed(() => {
    const w = watched.value ? bookingWindow(watched.value) : null;
    return w ? `${missionId.value}|${w.from}|${w.to}` : null;
  });
  const passes = useRemoteQuery(key, (k, signal) => {
    const [mission = "", from = "", to = ""] = k.split("|");
    return fetchPasses(mission, { from: new Date(from), to: new Date(to) }, signal);
  });
  useMissionInvalidation(missionId, ["contacts"], passes.refetch);
  return computed<BookingStopped | null>(() => {
    const p = watched.value;
    if (!p) return null;
    const result = bookingStopped(
      p,
      passes.state.value.status === "ready" ? passes.state.value.value : null,
    );
    // Still sending: the footer's "Booking with the providers" note says it; no callout.
    return p.state === "executing" && result.left !== 0 ? null : result;
  });
}
