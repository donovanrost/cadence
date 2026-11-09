import { computed, onScopeDispose, shallowRef, watch, type Ref } from "vue";
import { useRemoteQuery, type RemoteState } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { FLEET_REFETCH_GAP_MS, FLEET_TELEMETRY_GAP_MS, throttle } from "@/features/fleet/index.ts";
import { fetchActionQueue, presentQueue } from "./actionQueue.ts";
import { newlyResolved, RESOLVED_FADE_MS, withFading, type Fading } from "./attention.ts";
import type { QueueItem } from "./queue.ts";

/** The viewer's ranked queue (M6), refetched per the contract: state changes promptly, telemetry every 10 s. */
export function useActionQueue(missionId: Ref<string | null>) {
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
  const rows = computed(() =>
    query.state.value.status === "ready" ? presentQueue(query.state.value.value) : null,
  );
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
    if (!added.length) return;
    fading.value = [...fading.value, ...added];
    const timer = setTimeout(() => {
      timers.delete(timer);
      fading.value = fading.value.filter((f) => f.until > Date.now());
    }, RESOLVED_FADE_MS + 50);
    timers.add(timer);
  });
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
  return { state: query.state, items, refetch: query.refetch };
}
