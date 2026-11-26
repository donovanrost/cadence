import { afterEach, describe, expect, it } from "vite-plus/test";
import { keepingFocus } from "./chart-focus.ts";

/** #245 B4, A5: a repaint that replaces the chart's buttons keeps focus on the same control. */
afterEach(() => {
  document.body.innerHTML = "";
});
function chart(html: string) {
  const root = document.createElement("div");
  const layer = document.createElement("div");
  layer.innerHTML = html;
  root.append(layer);
  document.body.append(root);
  return { root, repaint: (next: string) => () => void (layer.innerHTML = next) };
}

describe("keepingFocus", () => {
  it("puts focus back on the same legend item, limit or event marker after a repaint", () => {
    const html = `<button data-chart-legend-item="bus.v">Bus V</button><button data-limit-marker-ref="L1">!</button><button data-event-marker-ref="E1">•</button>`;
    const { root, repaint } = chart(html);
    for (const selector of [
      "[data-limit-marker-ref]",
      "[data-event-marker-ref]",
      "[data-chart-legend-item]",
    ]) {
      root.querySelector<HTMLElement>(selector)?.focus();
      keepingFocus(root, repaint(html));
      expect(document.activeElement?.matches(selector)).toBe(true);
    }
  });
  it("falls back to the first legend item when the focused marker is gone", () => {
    const { root, repaint } = chart(
      `<button data-chart-legend-item="bus.v">Bus V</button><button data-event-marker-ref="E1">•</button>`,
    );
    root.querySelector<HTMLElement>("[data-event-marker-ref]")?.focus();
    keepingFocus(root, repaint(`<button data-chart-legend-item="bus.v">Bus V</button>`));
    expect(document.activeElement?.getAttribute("data-chart-legend-item")).toBe("bus.v");
  });
  it("leaves focus alone when it was outside the chart", () => {
    const { root, repaint } = chart(`<button data-chart-legend-item="a">A</button>`);
    const outside = document.createElement("input");
    document.body.append(outside);
    outside.focus();
    keepingFocus(root, repaint(`<button data-chart-legend-item="a">A</button>`));
    expect(document.activeElement).toBe(outside);
  });
});
