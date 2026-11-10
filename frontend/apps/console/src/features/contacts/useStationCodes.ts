import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchStations } from "./api.ts";

/**
 * Station ref → code from the mission's stations index (U33: a pass named by ground_station_ref
 * reads "KIR 02:31Z"). null until the index loads or for an unknown ref.
 */
export function useStationCodes(missionId: Ref<string | null>) {
  const query = useRemoteQuery(missionId, (id, signal) => fetchStations(id, signal));
  useMissionInvalidation(missionId, ["configuration", "stations"], query.refetch);
  const codes = computed(() => {
    const s = query.state.value;
    return new Map(
      s.status === "ready" ? s.value.stations.map((st) => [st.id, st.code] as const) : [],
    );
  });
  return (ref: string | null | undefined): string | null =>
    ref ? (codes.value.get(ref) ?? null) : null;
}
