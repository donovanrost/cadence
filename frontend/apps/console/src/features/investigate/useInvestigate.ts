import type { PointId } from "@/api/index.ts";
import { computed, onScopeDispose, type Ref } from "vue";
import { useRemoteQuery, type MissionId, type SpacecraftId } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchEpisode, fetchEpisodes, useAlarmPages } from "@/features/alarms/index.ts";
import { FLEET_REFETCH_GAP_MS, throttle } from "@/features/fleet/index.ts";
import { fetchEvents } from "@/features/timeline/index.ts";
import { fetchHistory, fetchLimitIntervals } from "./api.ts";
import { rangeWindow, type RangeKey } from "./model.ts";

const PAGE = 200;

/**
 * useRemoteQuery compares keys by value, so each key is a typed object (typing §12 A4) and the
 * MissionId stays one on its way to the request (§12C).
 */

/**
 * Active alarms of one spacecraft (B1, title tag), worst first, in pages: `more()` loads the next
 * 200, and the screen says when it holds only part of them (#827).
 */
export function useSpacecraftAlarms(missionId: Ref<MissionId>, spacecraftId: Ref<string | null>) {
  return useAlarmPages(missionId, () =>
    spacecraftId.value ? { state: "active", spacecraftId: spacecraftId.value, limit: PAGE } : null,
  );
}

/** The sisters' read: who, on which point, in which plane (null: nothing to ask). */
export type SisterQuery = Readonly<{ pointId: PointId; plane: number; spacecraftId: string }>;

/**
 * B4 sisters: the active alarms on one point in one plane, other than this spacecraft's, in pages.
 * The server filters by plane (the plane is its own spacecraft) and counts them (`total`); `limit`
 * 1 is a count. Never the mission's alarms.
 */
export function useSisterAlarms(
  missionId: Ref<MissionId>,
  sister: Ref<SisterQuery | null>,
  limit = PAGE,
) {
  return useAlarmPages(missionId, () =>
    sister.value
      ? {
          state: "active",
          pointId: sister.value.pointId,
          plane: sister.value.plane,
          excludeSpacecraftId: sister.value.spacecraftId,
          limit,
        }
      : null,
  );
}

/**
 * History + limit intervals for the chart. The window is computed when each fetch starts and
 * read back from the response (`from`/`to`), so a refetch slides the window forward.
 */
export function usePointTrend(
  missionId: Ref<MissionId>,
  spacecraftId: Ref<SpacecraftId | null>,
  pointId: Ref<PointId | null>,
  range: Ref<RangeKey>,
) {
  type TrendKey = Readonly<{ m: MissionId; sc: SpacecraftId; p: PointId; r: RangeKey }>;
  const key = computed((): TrendKey | null =>
    spacecraftId.value && pointId.value
      ? { m: missionId.value, sc: spacecraftId.value, p: pointId.value, r: range.value }
      : null,
  );
  const history = useRemoteQuery(key, (k, signal) =>
    fetchHistory(k.m, k.p, k.sc, toWindow(k.r), signal),
  );
  const intervals = useRemoteQuery(key, (k, signal) =>
    fetchLimitIntervals(k.m, k.p, k.sc, toWindow(k.r), signal),
  );
  const throttled = throttle(history.refetch, FLEET_REFETCH_GAP_MS);
  useMissionInvalidation(missionId, ["telemetry"], throttled.call);
  useMissionInvalidation(missionId, ["limits"], intervals.refetch);
  onScopeDispose(throttled.cancel);
  return { history, intervals };
}

function toWindow(range: RangeKey) {
  const window = rangeWindow(range, new Date());
  return { from: new Date(window.from), to: new Date(window.to) };
}

/** Alarm episodes of one spacecraft (lifecycle: status, ack, assignee) and the viewer's permissions. */
export function useSpacecraftEpisodes(missionId: Ref<MissionId>, spacecraftId: Ref<string | null>) {
  const key = computed(() =>
    spacecraftId.value ? { m: missionId.value, sc: spacecraftId.value } : null,
  );
  const query = useRemoteQuery(key, (k, signal) => {
    return fetchEpisodes(k.m, { spacecraftId: k.sc }, signal);
  });
  useMissionInvalidation(missionId, ["alarms"], query.refetch);
  return query;
}

/** One episode with its events (B2 and the escalation notice). */
export function useEpisodeDetail(missionId: Ref<MissionId>, episodeId: Ref<string | null>) {
  const key = computed(() => (episodeId.value ? { m: missionId.value, e: episodeId.value } : null));
  const query = useRemoteQuery(key, (k, signal) => {
    return fetchEpisode(k.m, k.e, signal);
  });
  useMissionInvalidation(missionId, ["alarms"], query.refetch);
  return query;
}

/** The spacecraft's mission events over the last 24 h (B2), newest first. */
export function useSpacecraftEvents(missionId: Ref<MissionId>, spacecraftId: Ref<string | null>) {
  const key = computed(() =>
    spacecraftId.value ? { m: missionId.value, sc: spacecraftId.value } : null,
  );
  const query = useRemoteQuery(key, (k, signal) => {
    const to = new Date();
    return fetchEvents(
      k.m,
      { from: new Date(to.getTime() - 86_400_000), to, spacecraftId: k.sc },
      signal,
    );
  });
  useMissionInvalidation(missionId, ["events", "alarms"], query.refetch);
  return query;
}
