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
  // A string key: every refetch of the live plan yields a new object, and an object key would
  // reload the passes read (and flash its loading state) each time.
  const key = computed(() => {
    const w = live.value?.window;
    return w?.from && w.to ? `${missionId.value}|${w.from}|${w.to}` : null;
  });
  const passes = useRemoteQuery(key, (k, signal) => {
    const [mission = "", from = "", to = ""] = k.split("|");
    return fetchPasses(mission, { from: new Date(from), to: new Date(to) }, signal);
  });
  const impact = computed(() => {
    const s = passes.state.value;
    return s.status === "ready" && live.value
      ? impactOf(s.value.passes, live.value, s.value.truncated)
      : null;
  });
  return {
    state: passes.state,
    refetch: passes.refetch,
    impact,
    hasWindow: computed(() => key.value !== null),
  };
}
