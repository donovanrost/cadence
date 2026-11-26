import { nextTick, watch } from "vue";
import { refocusFirst } from "@/ui";

/**
 * #244 (A5, B4; fe-ops on #590): after the person's own act (Remove, Add, a resolve) removes the
 * control that had focus, the next change of `trigger` moves focus to `target`, only if it was lost.
 * Unarmed, a change does nothing: a background refetch never pulls focus from someone whose focus
 * sits on <body> (a mouse user, a screen reader in browse mode). An armed move runs once.
 */
export function useArmedRefocus(trigger: () => unknown, target: () => HTMLElement | null) {
  let armed = false;
  watch(trigger, async () => {
    if (!armed) return;
    armed = false;
    await nextTick();
    refocusFirst(target());
  });
  return {
    arm: (): void => {
      armed = true;
    },
  };
}
