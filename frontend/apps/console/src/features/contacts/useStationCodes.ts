import type { MissionId } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import { useRemoteQuery, type StationId } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchStations, type GroundStation } from "./api.ts";
import type { StationInfo, StationLookup } from "./readiness.ts";

/**
 * The mission's stations index as code and provider name (U33: a pass named by
 * ground_station_ref reads "KIR 02:31Z", and its group line names the provider). null until the
 * index loads, or for an unknown station. Ids and provider refs are separate lookups (§12C).
 */
export function useStationCodes(missionId: Ref<MissionId | null>): StationLookup {
  const query = useRemoteQuery(missionId, (id, signal) => fetchStations(id, signal));
  useMissionInvalidation(missionId, ["configuration", "stations"], query.refetch);
  const rows = computed(() => {
    const s = query.state.value;
    return s.status === "ready" ? s.value.stations : [];
  });
  const byId = computed(
    () => new Map<StationId, GroundStation>(rows.value.map((st) => [st.id, st])),
  );
  // A provider ref is text: it matches a station id, else a code (a contact that names only its
  // station code still resolves).
  const byRef = computed(
    () =>
      new Map<string, GroundStation>([
        ...rows.value.flatMap((st) => (st.code ? [[st.code, st] as const] : [])),
        ...rows.value.map((st) => [String(st.id), st] as const),
      ]),
  );
  const info = (st: GroundStation | undefined): StationInfo | null =>
    st ? { code: st.code, provider: st.provider ?? null } : null;
  return {
    byId: (id) => (id ? info(byId.value.get(id)) : null),
    byRef: (ref) => (ref ? info(byRef.value.get(ref)) : null),
  };
}
