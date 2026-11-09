import { computed, onScopeDispose, type Ref } from "vue";
import { useRemoteQuery, type RemoteState } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { FLEET_REFETCH_GAP_MS, FLEET_TELEMETRY_GAP_MS, throttle } from "@/features/fleet/index.ts";
import { fetchActionQueue, presentQueue } from "./actionQueue.ts";
import type { QueueItem } from "./queue.ts";

/** The viewer's ranked queue (M6), refetched per the contract: state changes promptly, telemetry every 10 s. */
export function useActionQueue(missionId: Ref<string | null>) {
  const query = useRemoteQuery(missionId, (id, signal) => fetchActionQueue(id, signal));
  const prompt = throttle(query.refetch, FLEET_REFETCH_GAP_MS);
  const slow = throttle(prompt.call, FLEET_TELEMETRY_GAP_MS);
  useMissionInvalidation(
    missionId,
    ["alarms", "commanding", "spacecraft", "limits", "catalog", "data_sources", "settings"],
    prompt.call,
  );
  useMissionInvalidation(missionId, ["telemetry"], slow.call);
  onScopeDispose(() => {
    prompt.cancel();
    slow.cancel();
  });
  const items = computed<RemoteState<QueueItem[]>>(() => {
    const s = query.state.value;
    return s.status === "ready"
      ? { status: "ready", value: presentQueue(s.value), receivedAt: s.receivedAt }
      : s;
  });
  return { state: query.state, items, refetch: query.refetch };
}
