import { describe, expect, it } from "vite-plus/test";
import { MIN_TABLE_BOX, tableRoom } from "./useTableBox.ts";

/** OpsLists.md › Fleet, option A: the room left for the table decides box vs page scroll. */
function screenAt(height: number, scrollTop: number) {
  const el = document.createElement("div");
  Object.defineProperty(el, "clientHeight", { get: () => height });
  Object.defineProperty(el, "scrollTop", { get: () => scrollTop });
  el.getBoundingClientRect = () => new DOMRect(0, 100, 1000, height);
  return el;
}
const panelAt = (viewportTop: number) => {
  const el = document.createElement("section");
  el.getBoundingClientRect = () => new DOMRect(0, viewportTop, 1000, 10);
  return el;
};

describe("Fleet table box", () => {
  it("measures from the panel's top in the screen's content to the screen's bottom", () => {
    // Panel 240px below the screen's top: 860 - 240 = 620 left.
    expect(tableRoom(screenAt(860, 0), panelAt(340))).toBe(620);
  });

  it("reads the same when the screen has scrolled (the fallback layout)", () => {
    // Scrolled 200: the panel shows 40px below the top but still starts 240px into the content.
    expect(tableRoom(screenAt(860, 200), panelAt(140))).toBe(620);
  });

  it("needs 360px", () => {
    expect(MIN_TABLE_BOX).toBe(360);
    expect(tableRoom(screenAt(599, 0), panelAt(340))).toBeLessThan(MIN_TABLE_BOX);
    expect(tableRoom(screenAt(600, 0), panelAt(340))).toBe(MIN_TABLE_BOX);
  });
});
