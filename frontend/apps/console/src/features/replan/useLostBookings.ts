import type { MissionId } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchPasses } from "@/features/contacts/index.ts";
import type { PlanDetail } from "@/features/scheduling/index.ts";
import { impactOf } from "./impact.ts";

/** The live plan's lost bookings (passes read over the plan window), shared by A Impact and Propose. */
export function useLostBookings(
  missionId: Readonly<Ref<MissionId>>,
  live: Readonly<Ref<PlanDetail | null>>,
) {
  // A typed key of plain values: useRemoteQuery compares keys structurally (§12 A4), so a
  // refetched plan (a new object) with the same window doesn't reload the passes read.
  const key = computed(() => {
    const w = live.value?.window;
    return w?.from && w.to ? { m: missionId.value, from: w.from, to: w.to } : null;
  });
  const passes = useRemoteQuery(key, (k, signal) =>
    fetchPasses(k.m, { from: new Date(k.from), to: new Date(k.to) }, signal),
  );
  const impact = computed(() => {
    const s = passes.state.value;
    return s.status === "ready" && live.value ? impactOf(s.value.passes, live.value) : null;
  });
  return {
    state: passes.state,
    refetch: passes.refetch,
    impact,
    /** Every pass in the plan window (C · Changes names a covering separate booking from it). */
    passes: computed(() =>
      passes.state.value.status === "ready" ? passes.state.value.value.passes : [],
    ),
    hasWindow: computed(() => key.value !== null),
  };
}
