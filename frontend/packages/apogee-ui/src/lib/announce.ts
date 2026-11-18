/**
 * One polite live region for the whole page (a11y B6), for words that appear with their own
 * element, such as an empty search result: a live region inserted already holding its words
 * isn't reliably announced, so they go here instead. Created on first use; the words are set a
 * moment after clearing, so the same sentence twice is announced twice.
 */
let region: HTMLElement | null = null;
let pending: ReturnType<typeof setTimeout> | undefined;

/** Delay between clearing the region and setting its words (screen readers need a change). */
export const ANNOUNCE_DELAY_MS = 150;

export function announcePolite(text: string): void {
  if (typeof document === "undefined" || text.trim() === "") return;
  if (!region?.isConnected) {
    region = document.createElement("div");
    region.setAttribute("role", "status");
    region.setAttribute("data-ap-announcer", "");
    region.className = "sr-only";
    document.body.append(region);
  }
  const target = region;
  target.textContent = "";
  clearTimeout(pending);
  pending = setTimeout(() => {
    target.textContent = text;
  }, ANNOUNCE_DELAY_MS);
}
