import { watch } from "vue";

/**
 * ux a11y checklist A5: after an action, focus returns to the control that started it; when that
 * control has gone with the action (a removed row, a swapped header, a replaced button), focus
 * goes to a stated fallback, never to <body>.
 */

/** Focus is nowhere real: on <body>, or on an element no longer in the page. */
export function focusLost(): boolean {
  const active = document.activeElement;
  return active === null || active === document.body || !active.isConnected;
}

/**
 * Focuses `target` only if focus was lost, so a user who has already moved on keeps their place.
 * A heading or line gets `tabindex="-1"` so it can take focus without joining the Tab order.
 */
export function refocus(target: HTMLElement | null | undefined): void {
  if (!target || !focusLost()) return;
  if (!target.hasAttribute("tabindex") && target.tabIndex < 0) target.tabIndex = -1;
  target.focus();
}

/** Keys a takeover (kiosk, present) handles from anywhere, except inside a sheet it opened. */
export function inDialog(event: KeyboardEvent): boolean {
  return event.target instanceof Element && event.target.closest("dialog") !== null;
}

/**
 * A row can leave a list with its action (archive, restore, delete, unstar under Starred), taking
 * the focused ⋯ with it. Returns a refetch that, once the list has re-read, moves focus that was
 * lost to the page heading.
 */
export function refetchKeepingFocus(
  state: () => { status: string },
  refetch: () => void,
): () => void {
  let mayLeave = false;
  watch(
    state,
    (s) => {
      if (!mayLeave || s.status === "loading") return;
      mayLeave = false;
      refocus(document.querySelector<HTMLElement>("h1"));
    },
    { flush: "post" },
  );
  return () => {
    mayLeave = true;
    refetch();
  };
}
