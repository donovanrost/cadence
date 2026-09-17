import { onBeforeUnmount, onMounted, ref, watch, type Ref } from "vue";
import type { LiveOpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";

/** Coalesce live wake-ups and discard reads overtaken by a local action. */
export function useLiveWorkspaceRead(
  port: LiveOpsPageReadPort,
  busy: Ref<boolean>,
  receive: (value: unknown) => void,
) {
  const syncing = ref(false),
    failed = ref(false);
  let disposed = false,
    requested = false,
    generation = 0;
  let active: Promise<void> | undefined;
  let unsubscribe: (() => void) | undefined;

  async function drain() {
    while (requested && !busy.value && !disposed) {
      requested = false;
      syncing.value = true;
      const started = generation;
      try {
        const value = await port.read();
        if (disposed) return;
        if (busy.value || generation !== started) requested = true;
        else {
          receive(value);
          failed.value = false;
        }
      } catch {
        if (!disposed) failed.value = true;
      } finally {
        if (!disposed) syncing.value = false;
      }
    }
  }
  function refresh(): Promise<void> {
    if (disposed) return Promise.resolve();
    requested = true;
    if (active) return active;
    if (busy.value) return Promise.resolve();
    active = drain().finally(() => {
      active = undefined;
      if (requested && !busy.value && !disposed) void refresh();
    });
    return active;
  }
  watch(
    busy,
    (pending) => {
      if (pending) generation++;
      else if (requested) void refresh();
    },
    { flush: "sync" },
  );
  onMounted(() => {
    unsubscribe = port.subscribe(() => {
      void refresh();
    });
    // Close the gap between the initial server read and mounting the subscriber.
    void refresh();
  });
  onBeforeUnmount(() => {
    disposed = true;
    unsubscribe?.();
  });
  return { refresh, syncing, syncFailed: failed };
}
