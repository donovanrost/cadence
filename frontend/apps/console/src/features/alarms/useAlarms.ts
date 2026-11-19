import type { MissionId } from "@/api/index.ts";
import { shallowRef, watch, type Ref } from "vue";
import type { RemoteState } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchEpisodePage, type Episodes } from "./episodes.ts";

export type EpisodePages = Episodes & Readonly<{ next: string | null }>;
type Episode = Episodes["episodes"][number];
const dedupe = (rows: readonly Episode[]) => [...new Map(rows.map((r) => [r.id, r])).values()];

/**
 * One state's episodes in pages (A6d, ux U72): the first page on load, Load more by cursor, rows
 * that move between pages deduped silently, and on a live change a reload from the first page up
 * to the count already shown, so a skipped row comes back by itself.
 */
function useEpisodePages(
  missionId: Ref<MissionId>,
  which: "active" | "cleared",
  open: Ref<boolean>,
) {
  const state = shallowRef<RemoteState<EpisodePages>>({ status: "loading" });
  const busy = shallowRef(false);
  let generation = 0;

  async function load(upTo = 0) {
    const mine = ++generation;
    let first: Episodes | null = null;
    const rows: Episode[] = [];
    let cursor: string | null = null;
    do {
      const r = await fetchEpisodePage(missionId.value, which, cursor);
      if (mine !== generation) return;
      if (!r.ok) {
        if (state.value.status !== "ready" || upTo === 0)
          state.value = { status: "failed", error: r.error };
        return;
      }
      first ??= r.value.value;
      rows.push(...r.value.value.episodes);
      cursor = r.value.nextCursor;
    } while (cursor && rows.length < upTo);
    if (first)
      state.value = {
        status: "ready",
        value: { ...first, episodes: dedupe(rows), next: cursor },
        receivedAt: new Date(),
      };
  }

  async function more() {
    const s = state.value;
    if (s.status !== "ready" || !s.value.next || busy.value) return;
    busy.value = true;
    const mine = generation;
    try {
      const r = await fetchEpisodePage(missionId.value, which, s.value.next);
      if (mine !== generation || !r.ok) return;
      state.value = {
        status: "ready",
        value: {
          ...s.value,
          episodes: dedupe([...s.value.episodes, ...r.value.value.episodes]),
          next: r.value.nextCursor,
        },
        receivedAt: new Date(),
      };
    } finally {
      busy.value = false;
    }
  }

  const run = (p: Promise<unknown>): void => {
    p.catch((e: unknown) => console.error("Alarms failed", e));
  };
  watch(
    () => (open.value ? missionId.value : null),
    (id) => {
      if (id === null) return;
      state.value = { status: "loading" };
      run(load());
    },
    { immediate: true },
  );
  useMissionInvalidation(missionId, ["alarms"], () => {
    const s = state.value;
    if (open.value) run(load(s.status === "ready" ? s.value.episodes.length : 0));
  });
  return {
    state,
    busy,
    more: () => run(more()),
    refetch: () => run(load()),
  };
}

/** Active alarm episodes (both tabs New / Acknowledged), refreshed on any episode change. */
export const useActiveEpisodes = (missionId: Ref<MissionId>) =>
  useEpisodePages(missionId, "active", shallowRef(true));

/** Cleared episodes, loaded only while the Cleared tab (or the empty state) needs them. */
export const useClearedEpisodes = (missionId: Ref<MissionId>, open: Ref<boolean>) =>
  useEpisodePages(missionId, "cleared", open);
