import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchPasses } from "@/features/contacts/index.ts";
import type { PlanDetail } from "@/features/scheduling/index.ts";
import { impactOf } from "./impact.ts";

/** The live plan's lost bookings (passes read over the plan window), shared by A Impact and Propose. */
export function useLostBookings(
  missionId: Readonly<Ref<string>>,
  live: Readonly<Ref<PlanDetail | null>>,
) {
  const key = computed(() => {
    const w = live.value?.window;
    return w?.from && w.to
      ? { missionId: missionId.value, from: new Date(w.from), to: new Date(w.to) }
      : null;
  });
  const passes = useRemoteQuery(key, (k, signal) =>
    fetchPasses(k.missionId, { from: k.from, to: k.to }, signal),
  );
  const impact = computed(() => {
    const s = passes.state.value;
    return s.status === "ready" && live.value
      ? impactOf(s.value.passes, live.value.id, s.value.truncated)
      : null;
  });
  return {
    state: passes.state,
    refetch: passes.refetch,
    impact,
    hasWindow: computed(() => key.value !== null),
  };
}
