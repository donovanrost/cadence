import { formatHourMinute, formatShort } from "../lib/format.ts";
import type { TimeRange } from "./types.ts";

/**
 * The range track's arithmetic (ux U62): what a drag or a key does to the selected window, clamped
 * to the track's span, with a one-minute minimum and whole-minute snapping. No DOM here.
 */
export const MINUTE = 60_000;
export const MIN_RANGE = MINUTE;
const NICE = [1, 5, 15, 30].map((m) => m * MINUTE).concat([1, 6, 12, 24].map((h) => h * 3_600_000));

/** The nice unit nearest `ms` (1/5/15/30 min, 1/6/12 h, 1 d), never under a minute. */
export function niceUnit(ms: number): number {
  return NICE.reduce((best, unit) => (Math.abs(unit - ms) < Math.abs(best - ms) ? unit : best));
}
/** A key's step: the nice unit nearest 1/100 of the span; `big` (Shift, PgUp/PgDn) is ×10. */
export function keyStep(span: TimeRange, big: boolean): number {
  const step = niceUnit((span.to - span.from) / 100);
  return big ? niceUnit(step * 10) : step;
}

/** What a pointer drag holds: a new range from `grab`, one end, or the whole window. */
export type DragPart = "new" | "start" | "end" | "band";

const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));
/** Whole minutes, except the span's own ends (a live range's end stays exactly at now). */
const snap = (t: number, span: TimeRange) =>
  t >= span.to ? span.to : t <= span.from ? span.from : Math.round(t / MINUTE) * MINUTE;

/** The window while dragging `part` from `grab` (when the drag began, over `base`) to `t`. */
export function dragged(
  part: DragPart,
  base: TimeRange,
  grab: number,
  t: number,
  span: TimeRange,
): TimeRange {
  const at = snap(clamp(t, span.from, span.to), span);
  switch (part) {
    case "new": {
      const start = snap(clamp(grab, span.from, span.to), span);
      return { from: Math.min(start, at), to: Math.max(start, at) };
    }
    case "start":
      return { from: Math.min(at, base.to - MIN_RANGE), to: base.to };
    case "end":
      return { from: base.from, to: Math.max(at, base.from + MIN_RANGE) };
    case "band":
      return moved(base, t - grab, span);
  }
}

/** The window moved by `delta`, keeping its length, inside the span (minute-snapped). */
export function moved(base: TimeRange, delta: number, span: TimeRange): TimeRange {
  const length = base.to - base.from;
  const last = Math.max(span.from, span.to - length);
  const raw = base.from + delta;
  // Pinned to the span's end exactly, so a window moved up to now ends at now.
  if (raw >= last) return { from: last, to: last + length };
  const from = Math.max(span.from, Math.round(raw / MINUTE) * MINUTE);
  return { from, to: from + length };
}

/** A key on a handle or the band: arrows by `step`; Home/End to the bounds. Null: not ours. */
export function keyed(
  part: Exclude<DragPart, "new">,
  key: string,
  base: TimeRange,
  span: TimeRange,
  step: number,
): TimeRange | null {
  const delta =
    key === "ArrowLeft" || key === "ArrowDown" || key === "PageDown"
      ? -step
      : key === "ArrowRight" || key === "ArrowUp" || key === "PageUp"
        ? step
        : null;
  const bound = key === "Home" ? span.from : key === "End" ? span.to : null;
  if (delta === null && bound === null) return null;
  if (part === "band") {
    // Home/End take the whole window to the span's start/end.
    const shift = key === "Home" ? span.from - base.from : key === "End" ? span.to - base.to : 0;
    return moved(base, bound === null ? (delta ?? 0) : shift, span);
  }
  const value = bound ?? (part === "start" ? base.from : base.to) + (delta ?? 0);
  return dragged(part, base, 0, value, span);
}

/** 'Range 11-14 03:10Z–04:40Z' (the end's date only when it's another day). */
export function rangeText(r: TimeRange): string {
  const from = new Date(r.from);
  const to = new Date(r.to);
  const sameDay = from.toISOString().slice(0, 10) === to.toISOString().slice(0, 10);
  return `Range ${formatShort(from)}–${sameDay ? formatHourMinute(to) : formatShort(to)}`;
}
