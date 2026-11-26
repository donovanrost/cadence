/**
 * A11y B4, A5: a live append or a rebuild repaints the legend, annotation, limit and event
 * buttons (their layers are replaced), so a focused one would be destroyed under the user. These
 * say which control a button is from its data attributes, so the repaint can put focus back on
 * the same control, else on the first legend item, never on <body>.
 */
export function controlKey(el: Element): string | null {
  if (!(el instanceof HTMLElement)) return null;
  const d = el.dataset;
  if (d.chartLegendItem !== undefined) return `legend:${d.chartLegendItem}`;
  if (d.chartAxisMode !== undefined) return "axis";
  if (d.chartAnnotationControl !== undefined) return `annotation:${d.chartAnnotationId ?? ""}`;
  if (d.limitMarkerRef !== undefined) return `limit:${d.limitMarkerRef}`;
  if (d.eventMarkerRef !== undefined) return `event:${d.eventMarkerRef}`;
  return null;
}

/** Runs `paint`; if it took the focused chart control away, focuses its counterpart. */
export function keepingFocus(root: HTMLElement, paint: () => void): void {
  const active = document.activeElement;
  const key = active && root.contains(active) ? controlKey(active) : null;
  paint();
  if (key === null || active?.isConnected) return;
  const buttons = Array.from(root.querySelectorAll<HTMLElement>("button"));
  const same = buttons.find((b) => controlKey(b) === key);
  const fallback = root.querySelector<HTMLElement>("[data-chart-legend-item]");
  (same ?? fallback)?.focus({ preventScroll: true });
}
