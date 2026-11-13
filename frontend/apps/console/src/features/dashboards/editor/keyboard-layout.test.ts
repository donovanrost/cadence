import { describe, expect, it } from "vite-plus/test";
import { keyboardLayout, positionText } from "./keyboard-layout.ts";

const p = {
  id: "w1",
  layout: { x: 0, y: 2, w: 4, h: 3 },
  constraints: { min_w: 2, min_h: 2, max_w: 6, max_h: 4, max_y: 10 },
};

describe("keyboard layout (a11y: the drag handle's keys)", () => {
  it("moves one cell with the arrows, within the grid", () => {
    expect(keyboardLayout(p, "ArrowRight", false, 12)).toEqual({
      placement_id: "w1",
      x: 1,
      y: 2,
      w: 4,
      h: 3,
    });
    expect(keyboardLayout(p, "ArrowLeft", false, 12)).toBeNull(); // already at x 0
    expect(
      keyboardLayout({ ...p, layout: { ...p.layout, x: 8 } }, "ArrowRight", false, 12),
    ).toBeNull();
    expect(keyboardLayout(p, "ArrowUp", false, 12)?.y).toBe(1);
  });

  it("resizes with Shift, within the widget's constraints", () => {
    expect(keyboardLayout(p, "ArrowRight", true, 12)?.w).toBe(5);
    expect(keyboardLayout(p, "ArrowDown", true, 12)?.h).toBe(4);
    expect(
      keyboardLayout({ ...p, layout: { ...p.layout, h: 4 } }, "ArrowDown", true, 12),
    ).toBeNull();
    expect(
      keyboardLayout({ ...p, layout: { ...p.layout, w: 2 } }, "ArrowLeft", true, 12),
    ).toBeNull();
  });

  it("ignores other keys", () => {
    expect(keyboardLayout(p, "Enter", false, 12)).toBeNull();
  });

  it("says the position 1-based, or that it's automatic", () => {
    expect(positionText({ x: 2, y: 0, w: 4, h: 3 })).toBe("column 3, row 1, 4 × 3");
    expect(positionText({ x: null, y: null, w: 4, h: 3 })).toBe("placed automatically, 4 × 3");
  });
});
