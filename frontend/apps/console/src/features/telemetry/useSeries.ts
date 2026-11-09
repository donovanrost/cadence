import { computed, onScopeDispose, type Ref } from "vue";
import { useRemoteQuery, type ApiResult } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { FLEET_TELEMETRY_GAP_MS, throttle, type FleetSpacecraft } from "@/features/fleet/index.ts";
import { fetchHistory, type History } from "@/features/investigate/index.ts";
import type { SeriesKey } from "./selection.ts";
import { resolveWindow, type WindowSel } from "./window.ts";

export type SeriesData = Readonly<{ key: SeriesKey; sc: FleetSpacecraft; history: History }>;

type Request = Readonly<{
  m: string;
  w: WindowSel;
  series: readonly { scid: number; id: string; p: string }[];
}>;

/**
 * History for every selected series in one read: all succeed together or the first failure is
 * shown (one chart, one state). Unknown SCIDs are skipped. Telemetry hints refetch at most every
 * 10 s, like the fleet.
 */
export function useSeries(
  missionId: Ref<string>,
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
    return JSON.stringify(request);
  });

  const query = useRemoteQuery(key, async (k, signal): Promise<ApiResult<SeriesData[]>> => {
    // Sound: k was produced by JSON.stringify(Request) above.
    const request = JSON.parse(k) as Request;
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
  return query;
}
