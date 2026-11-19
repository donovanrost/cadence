import {
  onScopeDispose,
  shallowRef,
  toValue,
  watch,
  type MaybeRefOrGetter,
  type ShallowRef,
} from "vue";
import type { ApiResult } from "./http.ts";
import type { RemoteState } from "./remote-state.ts";

/**
 * Owns one remote read: fetches when `key` changes (null pauses), aborts the previous request,
 * ignores stale responses, and keeps showing the last value while a refetch is in flight
 * (refetches never flash back to loading). A refetch while a read of the same key is in flight
 * doesn't abort it: it asks for one more read when that one lands (qa 11-14: invalidations at
 * ~1/s against ~1.5 s reads aborted every read, so the plan screen never settled). Aborts on scope dispose. Keys compare by value (a
 * stable JSON signature), so callers pass typed object keys and the fetcher gets them back as
 * they are: no stringify-and-parse round trip (typing plan §12 A4).
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
  /** The signature of the read in flight, and whether a refetch arrived during it. */
  let inFlight: string | null = null;
  let again = false;

  async function run(current: K, keepValue: boolean) {
    controller?.abort();
    const mine = new AbortController();
    controller = mine;
    const id = ++generation;
    inFlight = JSON.stringify(current);
    again = false;
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
    } finally {
      if (id === generation) {
        inFlight = null;
        if (again) void run(current, true).catch(() => undefined);
      }
    }
  }

  // A new object with the same contents is the same key: watch its signature, not its identity.
  const signature = () => {
    const current = toValue(key);
    return current === null ? null : JSON.stringify(current);
  };
  watch(
    signature,
    (sig, previous) => {
      const current = toValue(key);
      if (sig === null || current === null) {
        controller?.abort();
        generation += 1;
        state.value = { status: "loading" };
        return;
      }
      void run(current, previous === sig).catch(() => undefined);
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
      if (current === null) return;
      if (inFlight !== null && inFlight === JSON.stringify(current)) again = true;
      else void run(current, true).catch(() => undefined);
    },
  };
}
