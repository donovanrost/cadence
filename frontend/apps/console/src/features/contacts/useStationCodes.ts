import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchStations } from "./api.ts";
import type { StationLookup } from "./readiness.ts";

/**
 * Station ref → code and provider name from the mission's stations index (U33: a pass named by
 * ground_station_ref reads "KIR 02:31Z", and its group line names the provider). null until the
 * index loads, or for an unknown ref.
 */
export function useStationCodes(missionId: Ref<string | null>): StationLookup {
  const query = useRemoteQuery(missionId, (id, signal) => fetchStations(id, signal));
  useMissionInvalidation(missionId, ["configuration", "stations"], query.refetch);
  const byId = computed(() => {
    const s = query.state.value;
    // Keyed by id and by code, so a contact that names only its station code still resolves.
    const rows = s.status === "ready" ? s.value.stations : [];
    return new Map([
      ...rows.map((st) => [st.id, st] as const),
      ...rows.flatMap((st) => (st.code ? [[st.code, st] as const] : [])),
    ]);
  });
  const get = (ref: string | null | undefined) => (ref ? byId.value.get(ref) : undefined);
  return {
    code: (ref) => get(ref)?.code ?? null,
    provider: (ref) => get(ref)?.provider ?? null,
  };
}
