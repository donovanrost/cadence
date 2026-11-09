import { computed, ref, watch, type Ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import { fetchPasses } from "@/features/contacts/index.ts";
import { fetchStations } from "@/features/stations/index.ts";
import { useNow } from "@/ui";
import { fetchAvailability, fetchStationImpact, outageWindow } from "./station.ts";

/**
 * K2 station-down entry (`contacts/replan/:stationId`, S7): the station's availability and outage
 * window, the bookings it hits, and the live plan to repair, chosen as the plan most of those
 * bookings belong to (api: reservation_ids → passes' plan.id). Once found it goes into `?plan=`
 * so the plan-based flow (useReplan) takes over unchanged.
 */
export function useStationEntry(missionId: Readonly<Ref<string>>) {
  const route = useRoute();
  const router = useRouter();
  const now = useNow();
  const stationId = computed(() =>
    typeof route.params.stationId === "string" ? route.params.stationId : null,
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
  const passes = useRemoteQuery(
    () =>
      span.value
        ? {
            missionId: missionId.value,
            from: new Date(span.value.from),
            to: new Date(span.value.to),
          }
        : null,
    (k, signal) => fetchPasses(k.missionId, { from: k.from, to: k.to }, signal),
  );
  /** Whether a plan to repair was found ("found" also writes it into ?plan=). */
  const resolved = ref<"resolving" | "none" | "found">("resolving");

  watch(
    () => [impact.state.value, passes.state.value] as const,
    ([i, p]) => {
      if (i.status !== "ready" || p.status !== "ready") return;
      const hit = new Set(i.value.reservation_ids);
      const counts = new Map<string, number>();
      for (const pass of p.value.passes)
        if (hit.has(pass.id) && pass.plan)
          counts.set(pass.plan.id, (counts.get(pass.plan.id) ?? 0) + 1);
      const best = [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;
      resolved.value = best ? "found" : "none";
      if (best && route.query.plan !== best)
        void router.replace({ query: { ...route.query, plan: best } }).catch(() => undefined);
    },
    { immediate: true },
  );

  return { stationId, stationName, availability: availability.state, resolved };
}
