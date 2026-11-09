import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchEpisodes } from "./episodes.ts";

/** Active alarm episodes (both tabs Active / Acknowledged), refetched on any episode change. */
export function useActiveEpisodes(missionId: Ref<string>) {
  const query = useRemoteQuery(missionId, (id, signal) =>
    fetchEpisodes(id, { state: "active" }, signal),
  );
  useMissionInvalidation(missionId, ["alarms"], query.refetch);
  return query;
}

/** Cleared episodes, loaded only while the Cleared tab is open. */
export function useClearedEpisodes(missionId: Ref<string>, open: Ref<boolean>) {
  const query = useRemoteQuery(
    computed(() => (open.value ? missionId.value : null)),
    (id, signal) => fetchEpisodes(id, { state: "cleared" }, signal),
  );
  useMissionInvalidation(missionId, ["alarms"], () => {
    if (open.value) query.refetch();
  });
  return query;
}
