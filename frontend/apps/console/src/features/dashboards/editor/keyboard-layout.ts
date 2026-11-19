import type { LayoutEdit, OutlinePlacement } from "./contracts.ts";

type ArrowKey = "ArrowLeft" | "ArrowRight" | "ArrowUp" | "ArrowDown";
const STEP: Readonly<Record<ArrowKey, readonly [number, number]>> = {
  ArrowLeft: [-1, 0],
  ArrowRight: [1, 0],
  ArrowUp: [0, -1],
  ArrowDown: [0, 1],
};
/** A KeyboardEvent.key the layout moves by (the DOM gives plain text). */
const isArrow = (key: string): key is ArrowKey => Object.hasOwn(STEP, key);
const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), Math.max(lo, hi));

/** "column 2, row 3, 4 × 3" (1-based), for the Move button's description and announcements. */
export function positionText(
  l: Readonly<{ x: number | null; y: number | null; w: number; h: number }>,
) {
  const at =
    l.x === null || l.y === null ? "placed automatically" : `column ${l.x + 1}, row ${l.y + 1}`;
  return `${at}, ${l.w} × ${l.h}`;
}

/**
 * The keyboard way to lay out a widget (qa a11y: the drag handle was mouse-only). Arrows move one
 * cell, Shift+arrows resize, within the outline's constraints and the grid's columns. Returns the
 * one layout edit to stage, or null when the key isn't a layout key or nothing would change.
 */
export function keyboardLayout(
  p: Pick<OutlinePlacement, "id" | "layout" | "constraints">,
  key: string,
  shift: boolean,
  columns: number,
): LayoutEdit | null {
  if (!isArrow(key)) return null;
  const [dx, dy] = STEP[key];
  const x = p.layout.x ?? 0;
  const y = p.layout.y ?? 0;
  const c = p.constraints;
  const next = shift
    ? {
        x,
        y,
        w: clamp(p.layout.w + dx, c.min_w, Math.min(c.max_w, columns - x)),
        h: clamp(p.layout.h + dy, c.min_h, c.max_h),
      }
    : {
        x: clamp(x + dx, 0, columns - p.layout.w),
        y: clamp(y + dy, 0, c.max_y),
        w: p.layout.w,
        h: p.layout.h,
      };
  const same = next.x === x && next.y === y && next.w === p.layout.w && next.h === p.layout.h;
  return same ? null : { placement_id: p.id, ...next };
}
