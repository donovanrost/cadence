import { describe, expect, it } from "vite-plus/test";
import { revealInline } from "./reveal.ts";

/** A box 0..356 wide, scrolled to `scrollLeft`, and an element at `left`..`right` in the viewport. */
function setup(scrollLeft: number, left: number, right: number) {
  const box = document.createElement("div");
  const el = document.createElement("a");
  box.scrollLeft = scrollLeft;
  box.getBoundingClientRect = () => new DOMRect(0, 0, 356, 400);
  el.getBoundingClientRect = () => new DOMRect(left, 0, right - left, 15);
  return { box, el };
}

describe("revealInline", () => {
  it("scrolls a link cut off at the right edge fully in (#189: 169px at x=346)", () => {
    const { box, el } = setup(0, 346, 515);
    revealInline(box, el);
    expect(box.scrollLeft).toBe(515 - 356);
  });

  it("scrolls a link hidden under a sticky column out from under it", () => {
    const { box, el } = setup(300, 60, 160);
    revealInline(box, el, { start: 120 });
    expect(box.scrollLeft).toBe(240);
  });

  it("leaves a link that is already clear alone", () => {
    const { box, el } = setup(40, 130, 300);
    revealInline(box, el, { start: 120, end: 24 });
    expect(box.scrollLeft).toBe(40);
  });

  it("keeps the left edge of an element wider than the room in view", () => {
    const { box, el } = setup(0, 200, 900);
    revealInline(box, el, { start: 120 });
    expect(box.scrollLeft).toBe(80);
  });

  it("never scrolls before the start", () => {
    const { box, el } = setup(10, -5, 50);
    revealInline(box, el, { start: 24 });
    expect(box.scrollLeft).toBe(0);
  });
});
