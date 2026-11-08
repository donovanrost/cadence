import { onScopeDispose, shallowRef, toValue, watch, type MaybeRefOrGetter, type ShallowRef } from "vue";
import type { ApiResult } from "./http.ts";
import type { RemoteState } from "./remote-state.ts";

/**
 * Owns one remote read: fetches when `key` changes (null pauses), aborts the previous request,
 * ignores stale responses, and keeps showing the last value while a refetch is in flight
 * (refetches never flash back to loading). Aborts on scope dispose.
 *
 *   const { state, refetch } = useRemoteQuery(
 *     () => scope.value.mission.id,
 *     (missionId, signal) => fetchFleet(missionId, signal),
 *   );
 */
export function useRemoteQuery<K, T>(
  key: MaybeRefOrGetter<K | null>,
  fetcher: (key: K, signal: AbortSignal) => Promise<ApiResult<T>>,
): { state: Readonly<ShallowRef<RemoteState<T>>>; refetch: () => void } {
  const state = shallowRef<RemoteState<T>>({ status: "loading" });
  let controller: AbortController | null = null;
  let generation = 0;

  async function run(current: K, keepValue: boolean) {
    controller?.abort();
    const mine = new AbortController();
    controller = mine;
    const id = ++generation;
    if (!keepValue || state.value.status !== "ready") state.value = { status: "loading" };
    try {
      const result = await fetcher(current, mine.signal);
      if (id !== generation) return;
      state.value = result.ok
        ? { status: "ready", value: result.value, receivedAt: new Date() }
        : { status: "failed", error: result.error };
    } catch (error) {
      if (mine.signal.aborted || id !== generation) return;
      state.value = {
        status: "failed",
        error: {
          kind: "unavailable",
          status: 0,
          message: error instanceof Error ? error.message : "Request failed",
        },
      };
    }
  }

  watch(
    () => toValue(key),
    (current, previous) => {
      if (current === null) {
        controller?.abort();
        generation += 1;
        state.value = { status: "loading" };
        return;
      }
      void run(current, previous === current).catch(() => undefined);
    },
    { immediate: true },
  );

  onScopeDispose(() => {
    generation += 1;
    controller?.abort();
  });

  return {
    state,
    refetch: () => {
      const current = toValue(key);
      if (current !== null) void run(current, true).catch(() => undefined);
    },
  };
}
