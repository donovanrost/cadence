import { computed, type Ref } from "vue";
import { useRemoteQuery, type MissionId } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useFleet } from "@/features/fleet/index.ts";
import { fetchStations } from "../api.ts";
import { isHandStarted } from "../handStarted.ts";
import type { HistoryQuery, HistoryRow } from "./history.ts";
import type { HistoryNames } from "./words.ts";

/** History's names: the filters' options (fleet, stations), a row's spacecraft, the filter words. */
export function useHistoryLookups(missionId: Ref<MissionId>, query: Ref<HistoryQuery>) {
  const fleet = useFleet(missionId);
  const stations = useRemoteQuery(missionId, (id, signal) => fetchStations(id, signal));
  useMissionInvalidation(missionId, ["configuration"], stations.refetch);

  const byId = computed(() => {
    const s = fleet.state.value;
    return new Map((s.status === "ready" ? s.value.spacecraft : []).map((sc) => [sc.id, sc]));
  });
  /** The fleet row's name, else the row's own; a deleted spacecraft keeps its rows (contacts.md). */
  function spacecraftName(r: HistoryRow): string {
    const known = !isHandStarted(r) && r.spacecraft_id ? byId.value.get(r.spacecraft_id) : null;
    // A hand-started contact whose endpoints map to no spacecraft, or several, has none (api).
    return known?.name ?? r.spacecraft?.name ?? (isHandStarted(r) ? "—" : "Deleted spacecraft");
  }
  const spacecraftOptions = computed(() =>
    [...byId.value.values()].map((sc) => ({ value: sc.id, label: sc.name })),
  );
  const stationOptions = computed(() =>
    stations.state.value.status === "ready"
      ? stations.state.value.value.stations.map((s) => ({
          value: s.id,
          label: s.display_name ?? s.code ?? s.id,
        }))
      : [],
  );
  const label = (options: readonly { value: string; label: string }[], id: string | null) =>
    id === null ? null : (options.find((o) => o.value === id)?.label ?? id);
  const names = computed<HistoryNames>(() => ({
    states: query.value.states,
    spacecraft: label(spacecraftOptions.value, query.value.spacecraftId),
    station: label(stationOptions.value, query.value.station),
  }));
  return { byId, spacecraftName, spacecraftOptions, stationOptions, names };
}
