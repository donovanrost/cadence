import { onScopeDispose, watch, type Ref } from "vue";
import { useRemoteQuery, type RemoteState } from "@/api/index.ts";
import { useConnection, useMissionInvalidation } from "@/live/index.ts";
import { fetchFleet, type Fleet } from "./api.ts";

/**
 * Telemetry invalidations arrive every 500 ms while feeds run, and the fleet read is ~300 KB, so
 * refetches are spaced at least this far apart. A hint inside the gap schedules one trailing
 * refetch, so the last change is never dropped.
 */
export const FLEET_REFETCH_GAP_MS = 2_000;

/** Without a live socket there are no invalidation hints, so the snapshot is polled instead. */
export const FLEET_POLL_OFFLINE_S = 30;

export type FleetHandle = Readonly<{
  state: Readonly<Ref<RemoteState<Fleet>>>;
  refetch: () => void;
}>;

/** Leading + trailing throttle that owns its timer; `cancel` drops a scheduled call. */
export function throttle(run: () => void, gapMs: number, clock: () => number = Date.now) {
  let last = -Infinity;
  let timer: ReturnType<typeof setTimeout> | null = null;
  return {
    call: () => {
      if (timer !== null) return;
      const wait = last + gapMs - clock();
      if (wait <= 0) {
        last = clock();
        run();
        return;
      }
      timer = setTimeout(() => {
        timer = null;
        last = clock();
        run();
      }, wait);
    },
    cancel: () => {
      if (timer !== null) clearTimeout(timer);
      timer = null;
    },
  };
}

/** The fleet snapshot for one mission, refetched (throttled) on mission invalidations. */
/** `missionId: null` pauses (e.g. the palette outside a mission). */
export function useFleet(missionId: Readonly<Ref<string | null>>): FleetHandle {
  const query = useRemoteQuery(missionId, (id, signal) => fetchFleet(id, signal));
  const throttled = throttle(query.refetch, FLEET_REFETCH_GAP_MS);
  useMissionInvalidation(
    missionId,
    ["telemetry", "limits", "spacecraft", "commanding"],
    throttled.call,
  );
  const connection = useConnection();
  let poll: ReturnType<typeof setInterval> | null = null;
  const stopPoll = () => {
    if (poll !== null) clearInterval(poll);
    poll = null;
  };
  watch(
    connection,
    (now, before) => {
      stopPoll();
      if (now !== "live") poll = setInterval(throttled.call, FLEET_POLL_OFFLINE_S * 1000);
      // Hints were missed while offline; reconnect resync also refetches, the throttle merges them.
      else if (before === "offline") throttled.call();
    },
    { immediate: true },
  );
  onScopeDispose(() => {
    throttled.cancel();
    stopPoll();
  });
  return { state: query.state, refetch: query.refetch };
}
