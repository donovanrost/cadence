import type { MissionId } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { fetchLibrary, fetchLibraryItem } from "./api.ts";

/** The library list (D21), refetched on `dashboards`. */
export function useLibraryList(missionId: Ref<MissionId>, q: Ref<string>, page: Ref<number>) {
  const query = useRemoteQuery(
    computed(() => ({ m: missionId.value, q: q.value, p: page.value })),
    ({ m, q: text, p }, signal) => fetchLibrary(m, { q: text, page: p }, signal),
  );
  useMissionInvalidation(missionId, ["dashboards"], query.refetch);
  return query;
}

/** One item at a version (latest when null), refetched on `dashboards`. */
export function useLibraryItem(
  missionId: Ref<MissionId>,
  itemId: Ref<string | null>,
  version: Ref<number | null>,
) {
  const query = useRemoteQuery(
    computed(() =>
      itemId.value ? { m: missionId.value, id: itemId.value, v: version.value } : null,
    ),
    ({ m, id, v }, signal) => fetchLibraryItem(m, id, v, signal),
  );
  useMissionInvalidation(missionId, ["dashboards"], query.refetch);
  return query;
}
