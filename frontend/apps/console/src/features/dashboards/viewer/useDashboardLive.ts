import { computed, shallowRef, type Ref } from "vue";
import { useChannelEvent, useChannelSubscription } from "@/live";
import type { Runtime } from "../api.ts";
import {
  applyPush,
  versionEvent,
  viewPush,
  type LiveBoard,
  type VersionEvent,
} from "../model/live-merge.ts";

/**
 * Live step 2 (C1, api-ops 30295106): the dashboard channel drives the board; step 1's
 * invalidation-driven D5 data refetch is retired for the viewer and present mode.
 */
export const LIVE_PUSH = true;

/**
 * Live push for one dashboard (C1): joins `dashboard:<m>:<d>`, subscribes with the viewer's runtime
 * and refresh (view:set on change, via useChannelSubscription), applies `view` pushes in `seq`
 * order and resubscribes on a gap. `paused` (editing) unsubscribes but stays joined, so `version`
 * events (someone saved) still arrive.
 */
export function useDashboardLive(
  missionId: Readonly<Ref<string>>,
  dashboardId: Readonly<Ref<string>>,
  runtime: Readonly<Ref<Runtime>>,
  refreshMs: Readonly<Ref<number | null>>,
  paused: Readonly<Ref<boolean>>,
) {
  const topic = computed(() =>
    LIVE_PUSH && dashboardId.value ? `dashboard:${missionId.value}:${dashboardId.value}` : null,
  );
  const subscribed = computed(() => (paused.value ? null : topic.value));
  const board = shallowRef<LiveBoard | null>(null);
  const version = shallowRef<VersionEvent | null>(null);
  let lastSeq = 0;

  const sub = useChannelSubscription(subscribed, {
    subscribe: [
      "view:subscribe",
      () => ({
        runtime: {
          from: runtime.value.from || null,
          to: runtime.value.to || null,
          spacecraft_id: runtime.value.spacecraftId || null,
        },
        refresh_ms: refreshMs.value,
      }),
    ],
    unsubscribe: ["view:unsubscribe", {}],
    update: "view:set",
  });
  const restart = () => {
    board.value = null;
    lastSeq = 0;
    sub.resubscribe();
  };
  useChannelEvent(subscribed, "view", viewPush, {
    onEvent: (push) => {
      if (!push.full && push.seq !== lastSeq + 1) return restart();
      const applied = applyPush(board.value, push);
      if (!applied.ok) return restart();
      board.value = applied.board;
      lastSeq = push.seq;
    },
    // A new channel process starts from a full push after the (re)subscribe.
    onResync: () => {
      board.value = null;
      lastSeq = 0;
    },
  });
  useChannelEvent(topic, "version", versionEvent, {
    onEvent: (event) => {
      version.value = event;
    },
  });

  /** The pushed board (null until the first full push, or when the dashboard has no current version). */
  const snapshot = computed(() =>
    subscribed.value === null ? null : (board.value?.snapshot ?? null),
  );
  return { snapshot, version };
}
