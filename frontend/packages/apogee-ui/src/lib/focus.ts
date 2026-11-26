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

const FIELD =
  "input:not([type=hidden]):not([disabled]), select:not([disabled]), textarea:not([disabled])";

/**
 * Where focus goes when a chip leaves with its × focused (A5), in order: the next chip's ×, the
 * previous chip's ×, then the group's field (a search box or an Add select beside the chips, up to
 * three levels out). The group is the nearest `[data-ap-chips]`, else the chip's parent (its list
 * when each chip sits in an <li>). Read before the chip leaves the page.
 */
export function chipFocusCandidates(remove: HTMLElement): readonly (HTMLElement | null)[] {
  const chip = remove.closest<HTMLElement>("[data-ap-chip]") ?? remove;
  const parent = chip.parentElement;
  const group =
    chip.closest<HTMLElement>("[data-ap-chips]") ??
    (parent?.tagName === "LI" ? parent.parentElement : parent);
  if (!group) return [];
  const buttons = Array.from(group.querySelectorAll<HTMLElement>("[data-ap-chip-remove]"));
  const at = buttons.indexOf(remove);
  let field: HTMLElement | null = null;
  for (let box: HTMLElement | null = group, up = 0; box && up < 3 && !field; up++) {
    field =
      Array.from(box.querySelectorAll<HTMLElement>(FIELD)).find(
        (f) => !f.closest("[data-ap-chip]"),
      ) ?? null;
    box = box.parentElement;
  }
  return [buttons[at + 1] ?? null, at > 0 ? (buttons[at - 1] ?? null) : null, field];
}
