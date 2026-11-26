import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { probeStop } from "./probe-stop.ts";

/** Focuses a stop at the given box in a 390×844 phone viewport and probes it. */
function probe(left: number, top: number, width: number, height: number) {
  const stop = document.createElement("div");
  stop.tabIndex = 0;
  stop.setAttribute("role", "region");
  stop.setAttribute("aria-label", "Spacecraft");
  stop.style.outline = "2px solid red";
  document.body.append(stop);
  vi.spyOn(stop, "getBoundingClientRect").mockReturnValue(new DOMRect(left, top, width, height));
  const pointed = vi.spyOn(document, "elementFromPoint").mockReturnValue(stop);
  stop.focus();
  return { problems: probeStop([])?.problems ?? [], pointed };
}

beforeEach(() => {
  vi.stubGlobal("innerWidth", 390);
  vi.stubGlobal("innerHeight", 844);
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  document.body.replaceChildren();
});

/** #189: the sweep's geometry run at 390. */
describe("probeStop: is the focused stop on screen?", () => {
  it("passes a table region taller than the viewport whose top shows", () => {
    expect(probe(17, 56, 356, 59285).problems).toEqual([]);
  });

  it("tests the visible part of a tall stop for cover, not its centre", () => {
    expect(probe(17, 56, 356, 2264).pointed).toHaveBeenCalledWith(195, 450);
  });

  it("fails a tall stop that is wholly below the fold", () => {
    expect(probe(17, 900, 356, 2264).problems).toEqual([
      "off screen when focused (at 17,900 356×2264 in 390×844)",
    ]);
  });

  it("fails a link whose centre is cut off at the right edge", () => {
    expect(probe(369, 222, 133, 36).problems).toEqual([
      "off screen when focused (at 369,222 133×36 in 390×844)",
    ]);
  });
});
