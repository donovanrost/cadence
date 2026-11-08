import { onScopeDispose } from "vue";
import type { RouteLocationRaw, Router } from "vue-router";

const typing = (target: EventTarget | null) =>
  target instanceof HTMLElement &&
  (target.isContentEditable || ["INPUT", "SELECT", "TEXTAREA"].includes(target.tagName));

/** `[` and `]` step to the previous/next spacecraft (Investigate spec), except while typing. */
export function usePrevNextKeys(
  prev: () => RouteLocationRaw | null,
  next: () => RouteLocationRaw | null,
  router: Router,
) {
  function onKey(event: KeyboardEvent) {
    if (event.metaKey || event.ctrlKey || event.altKey || typing(event.target)) return;
    const to = event.key === "[" ? prev() : event.key === "]" ? next() : null;
    if (to === null) return;
    event.preventDefault();
    router.push(to).catch((error: unknown) => console.error("Navigation failed", error));
  }
  window.addEventListener("keydown", onKey);
  onScopeDispose(() => window.removeEventListener("keydown", onKey));
}
