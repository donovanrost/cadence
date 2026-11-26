/**
 * Scrolls `box` sideways (its scrollLeft only, never the page) until `el` sits clear of `start` px
 * at the box's left edge and `end` px at its right: a sticky column, an edge fade. The browser
 * doesn't scroll a partly visible element on focus, so Tab can stop on a link cut off at the edge
 * of a sideways-scrolling table or strip (#189 sweep at 390). An element wider than the room keeps
 * its left edge in view.
 */
export function revealInline(
  box: HTMLElement,
  el: HTMLElement,
  inset: Readonly<{ start?: number; end?: number }> = {},
): void {
  const start = inset.start ?? 0;
  const end = inset.end ?? 0;
  const room = box.getBoundingClientRect();
  const at = el.getBoundingClientRect();
  const toLeft = at.left - room.left - start;
  let by = 0;
  if (toLeft < 0) by = toLeft;
  else if (at.right > room.right - end) by = Math.min(at.right - room.right + end, toLeft);
  if (by !== 0) box.scrollLeft = Math.max(0, box.scrollLeft + by);
}
