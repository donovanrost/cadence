import { nextTick } from "vue";
import { refocusFirst } from "@cadence/apogee-ui";

/**
 * a11y A5 for a list whose item leaves with its own focused control (a chip's ×, Remove leg,
 * Remove rule): once the list re-renders, focus the matching control now at that index (the
 * next item), else the one before, else `fallback` (the list's Add control), else the page h1.
 * Only when focus was lost: the user may already have moved on.
 */
export async function focusAfterRemove(
  box: HTMLElement | null | undefined,
  selector: string,
  index: number,
  fallback?: () => HTMLElement | null | undefined,
): Promise<void> {
  await nextTick();
  const items = box ? Array.from(box.querySelectorAll<HTMLElement>(selector)) : [];
  refocusFirst(items[index], items[index - 1], fallback?.());
}
