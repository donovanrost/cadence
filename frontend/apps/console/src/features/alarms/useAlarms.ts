import type { MissionId } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchEpisodes } from "./episodes.ts";
import { NO_FILTERS, type EpisodeFilters } from "./filters.ts";

/**
 * Active alarm episodes (both tabs Active / Acknowledged), refetched on any episode change. The
 * spacecraft and severity filters go to the server (ux U69 A6), so its 200 cap stays honest.
 */
export function useActiveEpisodes(
  missionId: Ref<MissionId>,
  filters: Ref<EpisodeFilters> = computed(() => NO_FILTERS),
) {
  const query = useRemoteQuery(
    computed(() => ({ id: missionId.value, ...filters.value })),
    ({ id, ...f }, signal) => fetchEpisodes(id, { state: "active", ...f }, signal),
  );
  useMissionInvalidation(missionId, ["alarms"], query.refetch);
  return query;
}

/** Cleared episodes, loaded only while the Cleared tab is open. */
export function useClearedEpisodes(
  missionId: Ref<MissionId>,
  open: Ref<boolean>,
  filters: Ref<EpisodeFilters> = computed(() => NO_FILTERS),
) {
  const query = useRemoteQuery(
    computed(() => (open.value ? { id: missionId.value, ...filters.value } : null)),
    ({ id, ...f }, signal) => fetchEpisodes(id, { state: "cleared", ...f }, signal),
  );
  useMissionInvalidation(missionId, ["alarms"], () => {
    if (open.value) query.refetch();
  });
  return query;
}
