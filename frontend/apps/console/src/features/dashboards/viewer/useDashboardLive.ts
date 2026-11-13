import { computed, shallowRef, type Ref } from "vue";
import { useChannelEvent, useChannelSubscription } from "@/live";
import type { Runtime } from "../api.ts";
import { applyPush, versionEvent, viewPush, type VersionEvent } from "../model/live-merge.ts";
import type { WorkspaceSnapshot } from "../model/snapshot.ts";

/**
 * C1 is not served yet (api-ops builds it after L6/L5): until then the viewer stays on live step 1
 * (D5 refetch on invalidations). Flip when `dashboard:<m>:<d>` lands (plans/dashboards-live.md).
 */
export const LIVE_PUSH = false;

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
  /** The REST snapshot (D5) a first delta could apply to; normally the first push is full. */
  base: Readonly<Ref<WorkspaceSnapshot | null>>,
) {
  const topic = computed(() =>
    LIVE_PUSH && dashboardId.value ? `dashboard:${missionId.value}:${dashboardId.value}` : null,
  );
  const subscribed = computed(() => (paused.value ? null : topic.value));
  const snapshot = shallowRef<WorkspaceSnapshot | null>(null);
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
    snapshot.value = null;
    lastSeq = 0;
    sub.resubscribe();
  };
  useChannelEvent(subscribed, "view", viewPush, {
    onEvent: (push) => {
      if (!push.full && push.seq !== lastSeq + 1) return restart();
      const applied = applyPush(snapshot.value ?? base.value, push);
      if (!applied.ok) return restart();
      snapshot.value = applied.snapshot;
      lastSeq = push.seq;
    },
    // A new channel process starts from a full push after the (re)subscribe.
    onResync: () => {
      snapshot.value = null;
      lastSeq = 0;
    },
  });
  useChannelEvent(topic, "version", versionEvent, {
    onEvent: (event) => {
      version.value = event;
    },
  });

  /** True while pushes are driving the board: step 1's data refetch stands down. */
  const active = computed(() => subscribed.value !== null && snapshot.value !== null);
  return { snapshot, version, active };
}
