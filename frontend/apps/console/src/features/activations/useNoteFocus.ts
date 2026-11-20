import { nextTick, watch, type Ref } from "vue";
import { refocusFirst } from "@/ui";

/**
 * #244 (A5, B4; ux on #584): after an outcome, focus moves to the note only once the control that had
 * it is gone, and only if focus was lost (refocusFirst). Arm it with the outcome:
 * - right away (a Retry's button unmounts as the note mounts);
 * - again once `settled()` turns true (the refetch drops the Decide panel later, when the request
 *   leaves approval_pending). A pending move runs once.
 */
export function useNoteFocus(box: Ref<HTMLElement | null>, settled: () => boolean) {
  let pending = false;
  watch(settled, async (now) => {
    if (!pending || !now) return;
    pending = false;
    await nextTick();
    refocusFirst(box.value);
  });
  return async function arm(): Promise<void> {
    pending = true;
    await nextTick();
    refocusFirst(box.value);
  };
}
