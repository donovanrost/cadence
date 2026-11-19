import type { MissionId } from "@/api/index.ts";
import { computed, onScopeDispose, shallowRef, watch, type Ref } from "vue";
import { useRemoteQuery, type RemoteState } from "@/api/index.ts";
import {
  useChannelEvent,
  useChannelSubscription,
  useConnection,
  useMissionInvalidation,
} from "@/live/index.ts";
import { fetchFleet, type Fleet } from "./api.ts";
import { applyFleetPush, fleetPushReader } from "./live.ts";

/**
 * Telemetry invalidations arrive every 500 ms while feeds run, and the fleet read is ~300 KB, so
 * refetches are spaced at least this far apart. A hint inside the gap schedules one trailing
 * refetch, so the last change is never dropped.
 */
export const FLEET_REFETCH_GAP_MS = 2_000;
/** Telemetry hints only move freshness (last heard, stale), so they refetch at most this often (api ops.md). */
export const FLEET_TELEMETRY_GAP_MS = 10_000;

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
/**
 * `missionId: null` pauses (e.g. the palette outside a mission). With `live` (default) the fleet
 * comes from the opt-in `fleet` push (full snapshot, then deltas) and GET /fleet is only the
 * first paint and the fallback: on a seq gap or inconsistent delta it resubscribes, and while the
 * socket is down it polls. Overlays that open over a screen (the palette) pass `live: false` so
 * closing them doesn't unsubscribe the screen underneath.
 */
export function useFleet(
  missionId: Readonly<Ref<MissionId | null>>,
  options: Readonly<{ live?: boolean }> = {},
): FleetHandle {
  const query = useRemoteQuery(missionId, (id, signal) => fetchFleet(id, signal));
  const pushed = shallowRef<{ fleet: Fleet; seq: number; at: Date } | null>(null);
  const throttled = throttle(query.refetch, FLEET_REFETCH_GAP_MS);
  /** While pushes arrive, invalidation hints don't refetch the fleet (realtime.md). */
  const refetchUnlessLive = () => {
    if (pushed.value === null) throttled.call();
  };
  // State changes (limit transitions, configuration, commanding) refetch promptly; telemetry,
  // which fires every 500 ms under live feeds, only refreshes freshness every 10 s.
  useMissionInvalidation(
    missionId,
    ["alarms", "limits", "spacecraft", "commanding"],
    refetchUnlessLive,
  );
  const telemetry = throttle(refetchUnlessLive, FLEET_TELEMETRY_GAP_MS);
  useMissionInvalidation(missionId, ["telemetry"], telemetry.call);

  if (options.live !== false) {
    const topic = computed(() => (missionId.value ? `mission:${missionId.value}` : null));
    const { resubscribe } = useChannelSubscription(topic, {
      subscribe: ["fleet:subscribe", {}],
      unsubscribe: ["fleet:unsubscribe", {}],
    });
    const restart = () => {
      pushed.value = null;
      resubscribe();
    };
    useChannelEvent(topic, "fleet", fleetPushReader, {
      onEvent: (push) => {
        const current = pushed.value;
        const result = applyFleetPush(current?.fleet ?? null, current?.seq ?? 0, push);
        if (result.ok) pushed.value = { fleet: result.fleet, seq: result.seq, at: new Date() };
        else restart();
      },
      // A rejoin starts a new channel process: the helper resubscribes and seq restarts at 1.
      onResync: () => {
        pushed.value = null;
      },
      onMalformed: restart,
    });
    watch(missionId, () => {
      pushed.value = null;
    });
  }

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
      if (now !== "live") {
        pushed.value = null;
        poll = setInterval(throttled.call, FLEET_POLL_OFFLINE_S * 1000);
      }
      // Hints were missed while offline; reconnect resync also refetches, the throttle merges them.
      else if (before === "offline") throttled.call();
    },
    { immediate: true },
  );
  onScopeDispose(() => {
    throttled.cancel();
    telemetry.cancel();
    stopPoll();
  });
  const state = computed<RemoteState<Fleet>>(() => {
    const live = pushed.value;
    return live ? { status: "ready", value: live.fleet, receivedAt: live.at } : query.state.value;
  });
  return { state, refetch: query.refetch };
}
