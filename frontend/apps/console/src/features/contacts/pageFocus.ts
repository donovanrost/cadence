import { nextTick } from "vue";

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
