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
