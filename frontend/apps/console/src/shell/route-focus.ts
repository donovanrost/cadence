import { nextTick, onBeforeUnmount, ref, type Ref } from "vue";
import { useRouter, type RouteLocationNormalized } from "vue-router";

/**
 * SPA focus on route change (dashboards' a11y pass; lead's shell item): after a navigation, focus
 * the new page's main heading (its h1, made focusable with tabindex=-1), else <main>, and announce
 * the page title in a polite live region. Skipped on the first load, for a query- or hash-only
 * change (same page), and when focus has already gone somewhere on purpose (a sheet, or the page's
 * own field), so it never fights a component that manages focus itself.
 */

/** How long to wait for the new page's heading (async screens render it after their read). */
const HEADING_WAIT_MS = 1500;
/** After falling back to <main>, how long a late heading may still take focus (qa: slow reads). */
const LATE_HEADING_MS = 8000;

/**
 * qa (live): a page whose read outlasts the wait leaves focus on <main> and a screen reader hears
 * "Loading…". When its h1 arrives, focus moves to it, but only if focus is still on <main>
 * (the user hasn't gone anywhere) and no newer navigation started.
 */
function upgradeWhenHeadingArrives(target: HTMLElement, stillMine: () => boolean, waitMs: number) {
  if (typeof MutationObserver === "undefined") return;
  const observer = new MutationObserver(() => {
    if (!stillMine() || document.activeElement !== target) {
      observer.disconnect();
      return;
    }
    const h1 = target.querySelector<HTMLElement>("h1");
    if (!h1) return;
    observer.disconnect();
    if (!h1.hasAttribute("tabindex")) h1.setAttribute("tabindex", "-1");
    h1.focus({ preventScroll: false });
  });
  observer.observe(target, { childList: true, subtree: true });
  setTimeout(() => observer.disconnect(), waitMs);
}

/** True when only the query or hash changed: the same page, so focus stays where it is. */
export const samePage = (to: RouteLocationNormalized, from: RouteLocationNormalized) =>
  to.path === from.path;

/**
 * Focus moved on its own since the navigation started: to a dialog (a sheet takes focus), or to
 * something new that's still in the document. The element that was focused before (the link or
 * button that navigated, often gone now) and <body> don't count.
 */
export function focusClaimed(before: Element | null): boolean {
  const now = document.activeElement;
  if (!now || now === document.body) return false;
  if (now.closest('[role="dialog"]')) return true;
  return now !== before && now.isConnected;
}

const nextFrame = () =>
  new Promise<void>((resolve) =>
    typeof requestAnimationFrame === "function"
      ? requestAnimationFrame(() => resolve())
      : setTimeout(resolve, 16),
  );

async function headingIn(main: HTMLElement, waitMs: number): Promise<HTMLElement | null> {
  const started = Date.now();
  for (;;) {
    const h1 = main.querySelector<HTMLElement>("h1");
    if (h1) return h1;
    if (Date.now() - started > waitMs) return null;
    await nextFrame();
  }
}

export function useRouteFocus(
  main: Readonly<Ref<HTMLElement | null>>,
  options: Readonly<{ headingWaitMs?: number; lateHeadingMs?: number }> = {},
) {
  const router = useRouter();
  /** The live region's text: the page title after each page change. */
  const announcement = ref("");
  let before: Element | null = null;
  let token = 0;

  const offBefore = router.beforeEach(() => {
    before = document.activeElement;
  });
  const offAfter = router.afterEach(async (to, from, failure) => {
    // The first load isn't a change of page; a failed navigation didn't move.
    if (failure || from.matched.length === 0 || samePage(to, from)) return;
    const mine = ++token;
    // afterEach runs before Vue renders the new page: the old page (and its h1) is still in <main>.
    await nextTick();
    const target = main.value;
    if (!target || mine !== token) return;
    const heading = await headingIn(target, options.headingWaitMs ?? HEADING_WAIT_MS);
    // A newer navigation took over, or the page (or a sheet) already put focus somewhere.
    if (mine !== token || focusClaimed(before)) return;
    const focusable = heading?.isConnected ? heading : target;
    if (!focusable.hasAttribute("tabindex")) focusable.setAttribute("tabindex", "-1");
    focusable.focus({ preventScroll: false });
    if (focusable === target)
      upgradeWhenHeadingArrives(
        target,
        () => mine === token,
        options.lateHeadingMs ?? LATE_HEADING_MS,
      );
    // Cleared first, so a page with the same title as the last one is still announced.
    announcement.value = "";
    await nextFrame();
    if (mine === token) announcement.value = document.title;
  });
  onBeforeUnmount(() => {
    offBefore();
    offAfter();
  });
  return { announcement };
}
