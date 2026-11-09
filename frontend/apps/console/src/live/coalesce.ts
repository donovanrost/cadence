import { getCurrentScope, onScopeDispose } from "vue";

/**
 * Leading + trailing throttle for refetches: the first call runs at once; calls during the next
 * `ms` collapse into one run at the window's end. A burst of invalidations (a fleet run, a
 * provider sync) becomes at most two refetches per window instead of one per event.
 */
export function coalesce(fn: () => void, ms: number): { call: () => void; flush: () => void } {
  let timer: ReturnType<typeof setTimeout> | null = null;
  let pending = false;
  const open = () => {
    timer = setTimeout(() => {
      timer = null;
      if (pending) {
        pending = false;
        fn();
        open();
      }
    }, ms);
  };
  const call = () => {
    if (timer) {
      pending = true;
      return;
    }
    fn();
    open();
  };
  /** Run now regardless of the window (reconnect resync), and start a fresh window. */
  const flush = () => {
    if (timer) clearTimeout(timer);
    timer = null;
    pending = false;
    call();
  };
  if (getCurrentScope())
    onScopeDispose(() => {
      if (timer) clearTimeout(timer);
    });
  return { call, flush };
}
