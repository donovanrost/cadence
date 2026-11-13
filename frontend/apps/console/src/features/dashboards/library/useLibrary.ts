import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { fetchLibrary, fetchLibraryItem } from "./api.ts";

/** The library list (D21), refetched on `dashboards`. */
export function useLibraryList(missionId: Ref<string>, q: Ref<string>, page: Ref<number>) {
  const query = useRemoteQuery(
    computed(() => JSON.stringify({ m: missionId.value, q: q.value, p: page.value })),
    (k, signal) => {
      // Sound: produced by JSON.stringify above.
      const { m, q: text, p } = JSON.parse(k) as { m: string; q: string; p: number };
      return fetchLibrary(m, { q: text, page: p }, signal);
    },
  );
  useMissionInvalidation(missionId, ["dashboards"], query.refetch);
  return query;
}

/** One item at a version (latest when null), refetched on `dashboards`. */
export function useLibraryItem(
  missionId: Ref<string>,
  itemId: Ref<string | null>,
  version: Ref<number | null>,
) {
  const query = useRemoteQuery(
    computed(() =>
      itemId.value
        ? JSON.stringify({ m: missionId.value, id: itemId.value, v: version.value })
        : null,
    ),
    (k, signal) => {
      // Sound: produced by JSON.stringify above.
      const { m, id, v } = JSON.parse(k) as { m: string; id: string; v: number | null };
      return fetchLibraryItem(m, id, v, signal);
    },
  );
  useMissionInvalidation(missionId, ["dashboards"], query.refetch);
  return query;
}
