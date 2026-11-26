/**
 * A polite live region for words that appear with their own element, such as an empty search
 * result (a11y B6): a live region inserted already holding its words isn't reliably announced, so
 * they go to one that's already there. One region per container: the topmost open dialog (inside
 * an aria-modal sheet a screen reader hides everything outside it, so a region on <body> wouldn't
 * be read), else <body>. Created on first use; the words are set a moment after clearing, so the
 * region changes and the same sentence twice is announced twice.
 *
 * One timer for the whole page: a second call within ANNOUNCE_DELAY_MS, even for another region,
 * replaces the first, whose region stays empty (lead, #433). That suits search results, where only
 * the latest one matters; words that must each be heard need their own region.
 */
const regions = new WeakMap<HTMLElement, HTMLElement>();
let pending: ReturnType<typeof setTimeout> | undefined;

/** Delay between clearing the region and setting its words (screen readers need a change). */
export const ANNOUNCE_DELAY_MS = 150;

const OPEN_DIALOG = 'dialog[open], [role="dialog"][aria-modal="true"], [role="alertdialog"]';

/** The last open dialog in the page (the one on top), else <body>. */
function container(): HTMLElement {
  return Array.from(document.querySelectorAll<HTMLElement>(OPEN_DIALOG)).at(-1) ?? document.body;
}

export function announcePolite(text: string): void {
  if (typeof document === "undefined" || text.trim() === "") return;
  const host = container();
  let region = regions.get(host);
  if (!region?.isConnected) {
    region = document.createElement("div");
    region.setAttribute("role", "status");
    region.setAttribute("data-ap-announcer", "");
    region.className = "sr-only";
    host.append(region);
    regions.set(host, region);
  }
  const target = region;
  target.textContent = "";
  clearTimeout(pending);
  pending = setTimeout(() => {
    target.textContent = text;
  }, ANNOUNCE_DELAY_MS);
}
