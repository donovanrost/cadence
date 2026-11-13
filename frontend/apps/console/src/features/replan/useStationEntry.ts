import type { MissionId } from "@/api/index.ts";
import { computed, ref, watch, type Ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import { paramText } from "@/shell";
import { fetchStations } from "@/features/stations/index.ts";
import { useNow } from "@/ui";
import { fetchAvailability, fetchStationImpact, outageWindow } from "./station.ts";

/**
 * K2 station-down entry (`contacts/replan/:stationId`, S7): the station's availability and outage
 * window, the bookings it hits, and the live plan to repair (the impact read's `plans`). Once
 * found it goes into `?plan=`
 * so the plan-based flow (useReplan) takes over unchanged.
 */
export function useStationEntry(missionId: Readonly<Ref<MissionId>>) {
  const route = useRoute();
  const router = useRouter();
  const now = useNow();
  const stationId = computed(() =>
    typeof paramText(route.params, "stationId") === "string"
      ? paramText(route.params, "stationId")
      : null,
  );
  const availability = useRemoteQuery(
    () => (stationId.value ? { missionId: missionId.value, stationId: stationId.value } : null),
    fetchAvailability,
  );
  const stations = useRemoteQuery(() => (stationId.value ? missionId.value : null), fetchStations);
  const stationName = computed(() => {
    const s = stations.state.value;
    return s.status === "ready"
      ? (s.value.find((x) => x.id === stationId.value)?.display_name ?? "Station")
      : "Station";
  });
  const window = computed(() =>
    availability.state.value.status === "ready"
      ? outageWindow(availability.state.value.value, now.value)
      : null,
  );
  const span = computed(() => {
    const w = window.value;
    if (!w) return null;
    return {
      from: w.from,
      to: w.to ?? w.eta ?? new Date(Date.parse(w.from) + 86_400_000).toISOString(),
    };
  });
  const impact = useRemoteQuery(
    () =>
      stationId.value && span.value
        ? { missionId: missionId.value, stationId: stationId.value, ...span.value }
        : null,
    fetchStationImpact,
  );
  /** Whether a plan to repair was found ("found" also writes it into ?plan=). */
  const resolved = ref<"resolving" | "none" | "found">("resolving");

  watch(
    () => impact.state.value,
    (i) => {
      if (i.status !== "ready") return;
      // One plan normally; with several, repair the latest revision that booked hit passes.
      // Plans whose bookings the outage hits or already cost; repair the latest revision.
      const best =
        [...i.value.lost.plans, ...i.value.plans].sort(
          (a, b) => (b.version ?? 0) - (a.version ?? 0),
        )[0]?.id ?? null;
      resolved.value = best ? "found" : "none";
      if (best && route.query.plan !== best)
        void router.replace({ query: { ...route.query, plan: best } }).catch(() => undefined);
    },
    { immediate: true },
  );

  return { stationId, stationName, availability: availability.state, resolved, span };
}
