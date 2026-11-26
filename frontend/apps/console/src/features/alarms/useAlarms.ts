import type { MissionId } from "@/api/index.ts";
import { computed, shallowRef, type Ref } from "vue";
import { usePagedQuery, type PageFetcher } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchEpisodePage, type Episodes } from "./episodes.ts";

type Episode = Episodes["episodes"][number];
/** A page's envelope besides its episodes: the mission-wide summary and the viewer's permissions. */
export type EpisodesMeta = Omit<Episodes, "episodes">;
type Key = Readonly<{ missionId: MissionId; which: "active" | "cleared" }>;

const fetchPage: PageFetcher<Key, Episode, EpisodesMeta> = async (key, cursor, signal) => {
  const r = await fetchEpisodePage(key.missionId, key.which, cursor, signal);
  if (!r.ok) return r;
  const { episodes, ...meta } = r.value.value;
  return { ok: true, value: { items: episodes, next: r.value.nextCursor, meta } };
};

/**
 * One state's episodes in pages (A6d, ux U72) through usePagedQuery: the first page on load, Load
 * more by cursor, and on a live `alarms` change a reload from the first page up to the rows shown.
 * Closed (`open` false), nothing is read.
 */
function useEpisodePages(
  missionId: Ref<MissionId>,
  which: "active" | "cleared",
  open: Ref<boolean>,
) {
  const key = computed<Key | null>(() =>
    open.value ? { missionId: missionId.value, which } : null,
  );
  const query = usePagedQuery(key, fetchPage, (episode) => episode.id);
  useMissionInvalidation(missionId, ["alarms"], query.refetch);
  return query;
}

/** Active alarm episodes (both tabs New / Acknowledged), refreshed on any episode change. */
export const useActiveEpisodes = (missionId: Ref<MissionId>) =>
  useEpisodePages(missionId, "active", shallowRef(true));

/** Cleared episodes, loaded only while the Cleared tab (or the empty state) needs them. */
export const useClearedEpisodes = (missionId: Ref<MissionId>, open: Ref<boolean>) =>
  useEpisodePages(missionId, "cleared", open);
