import { computed, onScopeDispose, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchAlarms, fetchEpisode, fetchEpisodes } from "@/features/alarms/index.ts";
import { FLEET_REFETCH_GAP_MS, throttle } from "@/features/fleet/index.ts";
import { fetchEvents } from "@/features/timeline/index.ts";
import { fetchHistory, fetchLimitIntervals } from "./api.ts";
import { rangeWindow, type RangeKey } from "./model.ts";

type Key = Readonly<Record<string, string>>;
/** Query keys are strings so the watcher in useRemoteQuery compares them by value. */
const keyOf = (parts: Key | null) => (parts === null ? null : JSON.stringify(parts));
const parse = (key: string): Key => {
  // Sound: every key passed to parse was produced by keyOf from a Record<string, string>.
  return JSON.parse(key) as Key;
};

/** Active alarms of one spacecraft (B1, title tag). Refetch on limit-state transitions. */
export function useSpacecraftAlarms(missionId: Ref<string>, spacecraftId: Ref<string | null>) {
  const key = computed(() =>
    keyOf(spacecraftId.value ? { m: missionId.value, sc: spacecraftId.value } : null),
  );
  const query = useRemoteQuery(key, (k, signal) => {
    const { m = "", sc = "" } = parse(k);
    return fetchAlarms(m, { state: "active", spacecraftId: sc }, signal);
  });
  useMissionInvalidation(missionId, ["alarms", "limits"], query.refetch);
  return query;
}

/** Active alarms on one point across the mission (B4 sisters). */
export function usePointAlarms(missionId: Ref<string>, pointId: Ref<string | null>) {
  const key = computed(() =>
    keyOf(pointId.value ? { m: missionId.value, p: pointId.value } : null),
  );
  const query = useRemoteQuery(key, (k, signal) => {
    const { m = "", p = "" } = parse(k);
    return fetchAlarms(m, { state: "active", q: p }, signal);
  });
  useMissionInvalidation(missionId, ["alarms", "limits"], query.refetch);
  return query;
}

/**
 * History + limit intervals for the chart. The window is computed when each fetch starts and
 * read back from the response (`from`/`to`), so a refetch slides the window forward.
 */
export function usePointTrend(
  missionId: Ref<string>,
  spacecraftId: Ref<string | null>,
  pointId: Ref<string | null>,
  range: Ref<RangeKey>,
) {
  const key = computed(() =>
    keyOf(
      spacecraftId.value && pointId.value
        ? { m: missionId.value, sc: spacecraftId.value, p: pointId.value, r: range.value }
        : null,
    ),
  );
  const history = useRemoteQuery(key, (k, signal) => {
    const { m = "", sc = "", p = "", r = "6h" } = parse(k);
    return fetchHistory(m, p, sc, toWindow(r), signal);
  });
  const intervals = useRemoteQuery(key, (k, signal) => {
    const { m = "", sc = "", p = "", r = "6h" } = parse(k);
    return fetchLimitIntervals(m, p, sc, toWindow(r), signal);
  });
  const throttled = throttle(history.refetch, FLEET_REFETCH_GAP_MS);
  useMissionInvalidation(missionId, ["telemetry"], throttled.call);
  useMissionInvalidation(missionId, ["limits"], intervals.refetch);
  onScopeDispose(throttled.cancel);
  return { history, intervals };
}

function toWindow(range: string) {
  const window = rangeWindow(range === "1h" || range === "24h" ? range : "6h", new Date());
  return { from: new Date(window.from), to: new Date(window.to) };
}

/** Alarm episodes of one spacecraft (lifecycle: status, ack, assignee) and the viewer's permissions. */
export function useSpacecraftEpisodes(missionId: Ref<string>, spacecraftId: Ref<string | null>) {
  const key = computed(() =>
    keyOf(spacecraftId.value ? { m: missionId.value, sc: spacecraftId.value } : null),
  );
  const query = useRemoteQuery(key, (k, signal) => {
    const { m = "", sc = "" } = parse(k);
    return fetchEpisodes(m, { spacecraftId: sc }, signal);
  });
  useMissionInvalidation(missionId, ["alarms"], query.refetch);
  return query;
}

/** One episode with its events (B2 and the escalation notice). */
export function useEpisodeDetail(missionId: Ref<string>, episodeId: Ref<string | null>) {
  const key = computed(() =>
    keyOf(episodeId.value ? { m: missionId.value, e: episodeId.value } : null),
  );
  const query = useRemoteQuery(key, (k, signal) => {
    const { m = "", e = "" } = parse(k);
    return fetchEpisode(m, e, signal);
  });
  useMissionInvalidation(missionId, ["alarms"], query.refetch);
  return query;
}

/** The spacecraft's mission events over the last 24 h (B2), newest first. */
export function useSpacecraftEvents(missionId: Ref<string>, spacecraftId: Ref<string | null>) {
  const key = computed(() =>
    keyOf(spacecraftId.value ? { m: missionId.value, sc: spacecraftId.value } : null),
  );
  const query = useRemoteQuery(key, (k, signal) => {
    const { m = "", sc = "" } = parse(k);
    const to = new Date();
    return fetchEvents(
      m,
      { from: new Date(to.getTime() - 86_400_000), to, spacecraftId: sc },
      signal,
    );
  });
  useMissionInvalidation(missionId, ["events", "alarms"], query.refetch);
  return query;
}
