import { nextTick, watch } from "vue";
import { refocusFirst } from "@/ui";

/**
 * #244 (A5, B4): Submit and Send back close their sheet as the plan changes, so the opener the
 * sheet would return focus to can be gone. `to(target)` moves focus to what the act produced (the
 * review's line, or the sent-back line) at once and again once the plan's refetch shows the change
 * (`planKey` changes), always through refocusFirst: only lost focus moves. A pending move runs once;
 * `cancel()` drops it (a day change).
 */
export function usePlanFocus(planKey: () => string | null) {
  let pending: (() => HTMLElement | null) | null = null;
  watch(planKey, async () => {
    const target = pending;
    if (!target) return;
    pending = null;
    await nextTick();
    refocusFirst(target());
  });
  return {
    to(target: () => HTMLElement | null) {
      pending = target;
      void nextTick(() => refocusFirst(target()));
    },
    cancel() {
      pending = null;
    },
  };
}
