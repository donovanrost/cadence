import { computed, onScopeDispose, ref, shallowRef, watch, type Ref } from "vue";
import { useChannelEvent, useChannelSubscription, useConnection } from "@/live";
import type { DashboardId } from "@/api/index.ts";
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
  /** null: no dashboard to follow (Present between dashboards). */
  dashboardId: Readonly<Ref<DashboardId | null>>,
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
  // Leaving edit mode (or a new runtime topic) starts over: the board pushed before it is stale.
  watch(subscribed, () => {
    board.value = null;
    lastSeq = 0;
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
      if (push.full) settle();
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

  /**
   * A subscribe the server refused (its error reply doesn't reach this composable) or that never
   * answered: no full push within 5 s of (re)subscribing on a live socket. The screen then says the
   * board isn't live instead of showing the D5 snapshot as if it were.
   */
  const STALL_MS = 5_000;
  const connection = useConnection();
  const stalled = ref(false);
  let timer: ReturnType<typeof setTimeout> | null = null;
  function settle() {
    if (timer !== null) clearTimeout(timer);
    timer = null;
    stalled.value = false;
  }
  watch(
    [subscribed, connection, runtime, refreshMs],
    ([topicNow, link]) => {
      settle();
      if (topicNow === null || link !== "live") return;
      timer = setTimeout(() => {
        timer = null;
        stalled.value = true;
      }, STALL_MS);
    },
    { immediate: true, deep: true },
  );
  onScopeDispose(settle);

  /** The pushed board (null until the first full push); screens show it via `liveSnapshot`. */
  const pushed = computed(() => (subscribed.value === null ? null : board.value));
  return { board: pushed, version, stalled };
}
