import type { MissionId } from "@/api/index.ts";
import { computed, onScopeDispose, ref, watch, type Ref } from "vue";
import { usePagedQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchDirectoryPage, type DirectoryMeta, type SpacecraftRow } from "./api.ts";

/** Typing settles this long before the filter asks the server. */
const DEBOUNCE_MS = 250;

/**
 * The Setup directory a page at a time (#796): the first page when the mission or the filter
 * changes, `more()` for the next, and a reload up to the rows shown on a live `spacecraft`
 * change. The filter runs on the server (`q`), debounced; the summary is the whole mission's, from
 * the server, whatever the filter.
 */
export function useSpacecraftDirectory(missionId: Ref<MissionId>, query: Ref<string>) {
  const settled = ref(query.value.trim());
  let timer: ReturnType<typeof setTimeout> | undefined;
  watch(query, (value) => {
    clearTimeout(timer);
    timer = setTimeout(() => (settled.value = value.trim()), DEBOUNCE_MS);
  });
  onScopeDispose(() => clearTimeout(timer));

  const key = computed(() => ({ missionId: missionId.value, query: settled.value }));
  const paged = usePagedQuery<
    Readonly<{ missionId: MissionId; query: string }>,
    SpacecraftRow,
    DirectoryMeta
  >(key, fetchDirectoryPage, (row) => row.id);
  useMissionInvalidation(missionId, ["spacecraft"], paged.refetch);
  return { ...paged, settledQuery: settled };
}

export type SpacecraftDirectoryPages = ReturnType<typeof useSpacecraftDirectory>;
