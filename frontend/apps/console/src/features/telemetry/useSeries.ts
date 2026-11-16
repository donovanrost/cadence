import { computed, onScopeDispose, shallowRef, watch, type Ref } from "vue";
import {
  useRemoteQuery,
  type ApiResult,
  type MissionId,
  type RemoteState,
  type Scid,
  type SpacecraftId,
} from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { FLEET_TELEMETRY_GAP_MS, throttle, type FleetSpacecraft } from "@/features/fleet/index.ts";
import { fetchHistory, type History } from "@/features/investigate/index.ts";
import type { SeriesKey } from "./selection.ts";
import { resolveWindow, type WindowSel } from "./window.ts";

export type SeriesData = Readonly<{ key: SeriesKey; sc: FleetSpacecraft; history: History }>;

/** A re-read failed while an earlier read of the same selection is still shown (ux, §11c(D)). */
export type RefreshFailed = Readonly<{ at: Date; readAt: Date }>;

type Request = Readonly<{
  m: MissionId;
  w: WindowSel;
  series: readonly { scid: Scid; id: SpacecraftId; p: string }[];
}>;

/**
 * History for every selected series in one read: all succeed together or the first failure is
 * shown (one chart, one state). Unknown SCIDs are skipped. Telemetry hints refetch at most every
 * 10 s, like the fleet.
 */
export function useSeries(
  missionId: Ref<MissionId>,
  series: Ref<readonly SeriesKey[]>,
  fleet: Ref<readonly FleetSpacecraft[]>,
  window: Ref<WindowSel>,
) {
  const byScid = computed(() => new Map(fleet.value.map((sc) => [sc.scid, sc])));
  const key = computed(() => {
    const resolved = series.value.flatMap((s) => {
      const sc = byScid.value.get(s.scid);
      return sc ? [{ scid: s.scid, id: sc.id, p: s.pointId }] : [];
    });
    if (resolved.length === 0) return null;
    const request: Request = { m: missionId.value, w: window.value, series: resolved };
    return request;
  });

  const query = useRemoteQuery(key, async (request, signal): Promise<ApiResult<SeriesData[]>> => {
    const range = resolveWindow(request.w, new Date());
    const span = { from: new Date(range.from), to: new Date(range.to) };
    const results = await Promise.all(
      request.series.map((s) => fetchHistory(request.m, s.p, s.id, span, signal)),
    );
    const data: SeriesData[] = [];
    for (const [i, result] of results.entries()) {
      const s = request.series[i];
      const sc = s ? byScid.value.get(s.scid) : undefined;
      if (!result.ok) return result;
      if (s && sc) data.push({ key: { scid: s.scid, pointId: s.p }, sc, history: result.value });
    }
    return { ok: true, value: data };
  });

  const throttled = throttle(query.refetch, FLEET_TELEMETRY_GAP_MS);
  useMissionInvalidation(missionId, ["telemetry"], throttled.call);
  onScopeDispose(throttled.cancel);

  /**
   * A failed re-read keeps the last plot of the SAME selection (ux U78-D: "Couldn't refresh at
   * …; showing data read at …" + Try again) instead of dropping it; a new selection starts over.
   */
  const last = shallowRef<Extract<RemoteState<SeriesData[]>, { status: "ready" }> | null>(null);
  const failedAt = shallowRef<Date | null>(null);
  watch(
    () => JSON.stringify(key.value),
    () => {
      last.value = null;
      failedAt.value = null;
    },
  );
  watch(query.state, (s) => {
    if (s.status === "ready") {
      last.value = s;
      failedAt.value = null;
    } else if (s.status === "failed" && last.value) failedAt.value = new Date();
  });
  const state = computed((): RemoteState<SeriesData[]> => {
    const s = query.state.value;
    // Kept through a failure and through Try again's reload; a new selection resets `last`.
    return s.status !== "ready" && last.value ? last.value : s;
  });
  const refreshFailed = computed((): RefreshFailed | null =>
    failedAt.value && last.value ? { at: failedAt.value, readAt: last.value.receivedAt } : null,
  );
  return { state, refreshFailed, refetch: query.refetch };
}
