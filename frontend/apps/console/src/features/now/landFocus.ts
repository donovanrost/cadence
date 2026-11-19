/**
 * a11y checklist C (Now): after an action resolves a row, its button is gone and focus would fall
 * to <body>. Focus lands on the row's resolved line (`<key>|resolved`, the fading row), else the
 * row itself (still open, e.g. retried), else the queue's heading. Never if focus already went
 * somewhere real (a sheet's opener that survived, or the user moved on).
 */
const WAIT_MS = 1000;

const nextFrame = () =>
  new Promise<void>((resolve) =>
    typeof requestAnimationFrame === "function"
      ? requestAnimationFrame(() => resolve())
      : setTimeout(resolve, 16),
  );

const lost = () => {
  const a = document.activeElement;
  return !a || a === document.body || !a.isConnected;
};

function focusable(el: HTMLElement): HTMLElement {
  if (!el.hasAttribute("tabindex")) el.setAttribute("tabindex", "-1");
  return el;
}

/**
 * Where focus lands for a row (a11y A5, #243): its resolved line, else the row, else the queue's
 * heading. Made focusable. A sheet passes this as its return-focus, used once its opener is gone.
 */
export function landingFor(list: HTMLElement | null, key: string): HTMLElement | null {
  if (!list) return null;
  const el =
    list.querySelector<HTMLElement>(`[data-key="${CSS.escape(`${key}|resolved`)}"]`) ??
    list.querySelector<HTMLElement>(`[data-key="${CSS.escape(key)}"]`) ??
    list.closest("section")?.querySelector<HTMLElement>("h1, h2, h3") ??
    null;
  return el ? focusable(el) : null;
}

export async function landFocus(list: HTMLElement | null, key: string, waitMs = WAIT_MS) {
  if (!list) return;
  const started = Date.now();
  for (;;) {
    await nextFrame();
    if (!lost()) return;
    const row =
      list.querySelector<HTMLElement>(`[data-key="${CSS.escape(`${key}|resolved`)}"]`) ??
      list.querySelector<HTMLElement>(`[data-key="${CSS.escape(key)}"]`);
    if (row) {
      focusable(row).focus();
      return;
    }
    if (Date.now() - started > waitMs) {
      const heading = list.closest("section")?.querySelector<HTMLElement>("h1, h2, h3");
      if (heading) focusable(heading).focus();
      return;
    }
  }
}
