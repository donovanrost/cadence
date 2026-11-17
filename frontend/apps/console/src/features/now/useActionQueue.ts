import type { MissionId } from "@/api/index.ts";
import { computed, onScopeDispose, ref, shallowRef, watch, type Ref } from "vue";
import { useRemoteQuery, type RemoteState, type Unshown } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { FLEET_REFETCH_GAP_MS, FLEET_TELEMETRY_GAP_MS, throttle } from "@/features/fleet/index.ts";
import { fetchActionQueue, presentQueue } from "./actionQueue.ts";
import {
  newlyResolved,
  RESOLVED_FADE_MS,
  withFading,
  type Attention,
  type Fading,
} from "./attention.ts";
import type { QueueItem } from "./queue.ts";
import type { RetryOutcome } from "./useQueueCommand.ts";

/** The viewer's ranked queue (M6), refetched per the contract: state changes promptly, telemetry every 10 s. */
export function useActionQueue(
  missionId: Ref<MissionId | null>,
  missionName: Ref<string | null> = ref(null),
  /** U61: the signed-in user (a plan's author reads "You can't approve your own plan."). */
  viewerId: string | null = null,
) {
  const query = useRemoteQuery(missionId, (id, signal) => fetchActionQueue(id, signal));
  const prompt = throttle(query.refetch, FLEET_REFETCH_GAP_MS);
  const slow = throttle(prompt.call, FLEET_TELEMETRY_GAP_MS);
  useMissionInvalidation(
    missionId,
    [
      "alarms",
      "attention",
      "commanding",
      "spacecraft",
      "limits",
      "catalog",
      "data_sources",
      "settings",
    ],
    prompt.call,
  );
  useMissionInvalidation(missionId, ["telemetry"], slow.call);
  /**
   * Attention items a write returned (U37 Retry: ux, the row takes the returned state at once),
   * by item id, until the next read replaces them.
   */
  const patches = shallowRef<ReadonlyMap<string, Attention>>(new Map());
  watch(
    () => query.state.value,
    () => (patches.value = new Map()),
  );
  const rows = computed(() => {
    const s = query.state.value;
    if (s.status !== "ready") return null;
    const p = patches.value;
    if (p.size === 0) return presentQueue(s.value, new Date(), missionName.value, viewerId);
    const items = s.value.items.map((i) => {
      const a = i.attention ? p.get(i.attention.id) : undefined;
      return a ? { ...i, attention: a } : i;
    });
    return presentQueue({ ...s.value, items }, new Date(), missionName.value, viewerId);
  });
  // U31: a resolved attention row stays 5 s, faded, reading "Resolved by …".
  const fading = shallowRef<Fading[]>([]);
  const timers = new Set<ReturnType<typeof setTimeout>>();
  let previous: QueueItem[] = [];
  watch(rows, (current) => {
    if (current === null) return;
    const s = query.state.value;
    const resolved = s.status === "ready" ? (s.value.resolved ?? []) : [];
    const added = newlyResolved(previous, current, resolved, fading.value, Date.now());
    previous = current;
    if (added.length) fade(added);
  });
  function fade(add: Fading[]) {
    fading.value = [...fading.value, ...add];
    const timer = setTimeout(() => {
      timers.delete(timer);
      fading.value = fading.value.filter((f) => f.until > Date.now());
    }, RESOLVED_FADE_MS + 50);
    timers.add(timer);
  }
  /** After Retry: hold an emptied fold 5 s with its result (ux), then show the returned items. */
  function applyRetry(row: QueueItem, outcome: RetryOutcome) {
    if (outcome.emptied && outcome.text) {
      const index = Math.max(
        0,
        (rows.value ?? []).findIndex((r) => r.key === row.key),
      );
      const { list: _l, command: _c, memberKeys: _m, ...rest } = row;
      const item: QueueItem = {
        ...rest,
        key: `${row.key}|retried`,
        state: "off",
        sentence: outcome.text,
        meta: null,
        acknowledged: true,
      };
      fade([{ item, index, until: Date.now() + RESOLVED_FADE_MS }]);
    }
    if (outcome.items.length)
      patches.value = new Map([...patches.value, ...outcome.items.map((a) => [a.id, a] as const)]);
  }
  onScopeDispose(() => {
    prompt.cancel();
    slow.cancel();
    for (const t of timers) clearTimeout(t);
  });
  const items = computed<RemoteState<QueueItem[]>>(() => {
    const s = query.state.value;
    if (s.status !== "ready") return s;
    const value = withFading(rows.value ?? [], fading.value);
    return { status: "ready", value, receivedAt: s.receivedAt };
  });
  /** U86: the items this console couldn't read, for the line at the top of the queue. */
  const unshown = computed<readonly Unshown[]>(() => {
    const s = query.state.value;
    return s.status === "ready" ? s.value.unshown : [];
  });
  return { state: query.state, items, unshown, refetch: query.refetch, applyRetry };
}
