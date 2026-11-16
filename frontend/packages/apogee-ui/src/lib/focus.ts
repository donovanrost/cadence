/**
 * Where focus goes when the control that should get it back is gone (ux a11y checklist A5): the
 * page's h1, else <main>, made focusable without joining the Tab order. Never <body>.
 */
export function pageLandmark(): HTMLElement | null {
  const target =
    document.querySelector<HTMLElement>("main h1") ?? document.querySelector<HTMLElement>("main");
  if (target && !target.hasAttribute("tabindex")) target.setAttribute("tabindex", "-1");
  return target;
}

/** Focus the first of these that's still in the page, else the page landmark. */
export function focusFirstConnected(
  ...candidates: readonly (HTMLElement | null | undefined)[]
): void {
  const target = candidates.find((c) => c?.isConnected) ?? pageLandmark();
  target?.focus();
}

/** Focus is nowhere real: on <body>, or on an element no longer in the page. */
export function focusLost(): boolean {
  const active = document.activeElement;
  return active === null || active === document.body || !active.isConnected;
}

/**
 * After an in-place swap or a refetch (A5): only if focus was lost, focus the first candidate still
 * in the page, else the page landmark. A line or callout gets tabindex=-1 so it can take focus
 * without joining the Tab order. A user who has already moved on keeps their place.
 */
export function refocusFirst(...candidates: readonly (HTMLElement | null | undefined)[]): void {
  if (!focusLost()) return;
  const target = candidates.find((c) => c?.isConnected) ?? pageLandmark();
  if (target && !target.hasAttribute("tabindex") && target.tabIndex < 0)
    target.setAttribute("tabindex", "-1");
  target?.focus();
}
