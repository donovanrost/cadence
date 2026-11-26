import type { MissionId } from "@/api/index.ts";
import { computed, onScopeDispose, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchPasses } from "./passes-api.ts";

/** Changes arrive as `contacts` invalidations (S10); this only slides the window forward. */
export const WINDOW_SLIDE_MS = 5 * 60_000;

/**
 * Booked passes over a window that slides with now (`back` ms before, `ahead` ms after). Every
 * reservation change invalidates `contacts` (S10, db8c9953), so data refetches on that; a slow
 * timer moves the window so passes entering the horizon appear.
 */
export function usePasses(missionId: Ref<MissionId>, back: number, ahead: number | Ref<number>) {
  const span = computed(() => (typeof ahead === "number" ? ahead : ahead.value));
  const key = computed(() => ({ m: missionId.value, ms: span.value }));
  const query = useRemoteQuery(key, (k, signal) => {
    const t = Date.now();
    return fetchPasses(k.m, { from: new Date(t - back), to: new Date(t + k.ms) }, signal);
  });
  useMissionInvalidation(missionId, ["contacts"], query.refetch);
  const slide = setInterval(query.refetch, WINDOW_SLIDE_MS);
  onScopeDispose(() => clearInterval(slide));
  return query;
}
