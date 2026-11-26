import { computed, ref, watch, type Ref } from "vue";
import type { DashboardId } from "@/api/index.ts";
import { useNow } from "@/ui";

type Entry = Readonly<{ id: DashboardId; name: string; archived: boolean }>;

/**
 * Present mode's rotation (ux): each dashboard for one dwell, ←/→ step, Space pauses. Archived
 * dashboards are skipped and counted (Q10). A dashboard that fails to load keeps its slot for one
 * dwell (the screen shows its error) and the rotation moves on.
 */
export function usePresent(
  entries: Readonly<Ref<readonly Entry[]>>,
  dwellSeconds: Readonly<Ref<number>>,
) {
  const now = useNow();
  const active = computed(() => entries.value.filter((e) => !e.archived));
  const skipped = computed(() => entries.value.length - active.value.length);
  const index = ref(0);
  const paused = ref(false);
  const deadline = ref(now.value.getTime() + dwellSeconds.value * 1000);
  /** Remaining in the paused slot, so resuming doesn't skip ahead. */
  let held = 0;

  const current = computed(
    () => active.value[index.value % Math.max(active.value.length, 1)] ?? null,
  );
  const remainingMs = computed(() =>
    paused.value ? held : Math.max(0, deadline.value - now.value.getTime()),
  );
  function go(by: number) {
    const n = active.value.length;
    if (n === 0) return;
    index.value = (((index.value + by) % n) + n) % n;
    deadline.value = Date.now() + dwellSeconds.value * 1000;
    held = dwellSeconds.value * 1000;
  }
  function togglePause() {
    if (paused.value) deadline.value = Date.now() + held;
    else held = Math.max(0, deadline.value - Date.now());
    paused.value = !paused.value;
  }
  watch(now, (t) => {
    if (!paused.value && active.value.length > 1 && t.getTime() >= deadline.value) go(1);
  });
  return {
    current,
    index,
    total: computed(() => active.value.length),
    skipped,
    paused,
    remainingMs,
    next: () => go(1),
    previous: () => go(-1),
    togglePause,
  };
}
