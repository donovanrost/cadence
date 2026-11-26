import { nextTick, watch, type Ref } from "vue";
import type { PagedQuery } from "@/api/index.ts";

/**
 * a11y A5 (#243): 'Show earlier' goes away on the last page. If it had focus, focus lands on the
 * first row it just showed (made focusable), never on <body>; if the person had moved on, it stays
 * where they put it (B4).
 */
export async function landOnFirstNew(
  list: HTMLElement | null,
  firstNew: number,
  hadFocus: boolean,
): Promise<void> {
  if (!hadFocus) return;
  await nextTick();
  const row = list?.children.item(firstNew);
  if (!(row instanceof HTMLElement)) return;
  if (!row.hasAttribute("tabindex")) row.setAttribute("tabindex", "-1");
  row.focus();
}

/** Whether focus is inside `el` (the wrapper of a control that may go away). */
export const holdsFocus = (el: HTMLElement | null) =>
  el !== null && el.contains(document.activeElement);

/**
 * Show earlier through a paged query (#176), with A5/B4's focus rule. Whether focus is still on the
 * button is read the moment the page lands in the state, before Vue patches the DOM: on the last
 * page the button goes away, and reading after the patch would find focus on <body> and take it
 * for the person having moved on.
 */
export function useShowEarlier<Item, Meta>(
  query: PagedQuery<Item, Meta>,
  list: Readonly<Ref<HTMLElement | null>>,
  button: Readonly<Ref<HTMLElement | null>>,
): () => Promise<void> {
  let focusOnArrival = false;
  watch(query.state, () => (focusOnArrival = holdsFocus(button.value)), { flush: "sync" });
  return async () => {
    const before = query.state.value;
    const firstNew = before.status === "ready" ? before.value.items.length : 0;
    await query.more();
    const after = query.state.value;
    if (!query.moreError.value && after.status === "ready" && after.value.next === null)
      await landOnFirstNew(list.value, firstNew, focusOnArrival);
  };
}
