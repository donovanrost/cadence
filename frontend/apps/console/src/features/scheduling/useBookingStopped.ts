import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchPasses } from "@/features/contacts/index.ts";
import { useMissionInvalidation } from "@/live";
import type { PlanDetail } from "./api.ts";
import { bookingStopped, bookingWindow, type BookingStopped } from "./booking.ts";

/**
 * The interrupted-execution reading for `plan` (null unless it's interrupted): reads the passes
 * over the plan's unlocked passes and refetches on `contacts` invalidations.
 */
export function useBookingStopped(
  missionId: Readonly<Ref<string>>,
  plan: Readonly<Ref<PlanDetail | null>>,
) {
  const interrupted = computed(() => (plan.value?.state === "interrupted" ? plan.value : null));
  // A string key, so a refetched plan (a new object) doesn't reload the passes read.
  const key = computed(() => {
    const w = interrupted.value ? bookingWindow(interrupted.value) : null;
    return w ? `${missionId.value}|${w.from}|${w.to}` : null;
  });
  const passes = useRemoteQuery(key, (k, signal) => {
    const [mission = "", from = "", to = ""] = k.split("|");
    return fetchPasses(mission, { from: new Date(from), to: new Date(to) }, signal);
  });
  useMissionInvalidation(missionId, ["contacts"], passes.refetch);
  return computed<BookingStopped | null>(() =>
    interrupted.value
      ? bookingStopped(
          interrupted.value,
          passes.state.value.status === "ready" ? passes.state.value.value : null,
        )
      : null,
  );
}
