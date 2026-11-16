import { describe, expect, it } from "vite-plus/test";
import { dragged, keyed, keyStep, moved, niceUnit, rangeText } from "./range-drag.ts";

const M = 60_000;
const H = 60 * M;
const span = { from: 0, to: 24 * H };
const base = { from: 6 * H, to: 8 * H };

describe("range track drags (ux U62)", () => {
  it("moves one end only, snapped to whole minutes", () => {
    expect(dragged("start", base, 0, 5 * H + 20_000, span)).toEqual({ from: 5 * H, to: 8 * H });
    expect(dragged("end", base, 0, 9 * H + 40_000, span)).toEqual({ from: 6 * H, to: 9 * H + M });
  });
  it("never lets an end cross the other: a minute apart at least", () => {
    expect(dragged("start", base, 0, 10 * H, span)).toEqual({ from: 8 * H - M, to: 8 * H });
    expect(dragged("end", base, 0, 1 * H, span)).toEqual({ from: 6 * H, to: 6 * H + M });
  });
  it("keeps ends inside the span (a booking can't go before now)", () => {
    expect(dragged("start", base, 0, -5 * H, span).from).toBe(0);
    expect(dragged("end", base, 0, 30 * H, span).to).toBe(24 * H);
  });
  it("moves the whole window by the drag, keeping its length, pinned inside the span", () => {
    expect(dragged("band", base, 7 * H, 10 * H, span)).toEqual({ from: 9 * H, to: 11 * H });
    expect(moved(base, 100 * H, span)).toEqual({ from: 22 * H, to: 24 * H });
    expect(moved(base, -100 * H, span)).toEqual({ from: 0, to: 2 * H });
  });
  it("draws a new range either way from where it began", () => {
    expect(dragged("new", base, 12 * H, 10 * H, span)).toEqual({ from: 10 * H, to: 12 * H });
  });
  it("keeps a live end exactly at now when dragged there", () => {
    const live = { from: 0, to: 24 * H + 12_345 };
    expect(dragged("end", base, 0, 99 * H, live).to).toBe(live.to);
  });
});

describe("range track keys (ux U62)", () => {
  it("steps by the nice unit nearest 1% of the span; Shift/PgUp ×10", () => {
    expect(niceUnit(14.4 * M)).toBe(15 * M);
    expect(keyStep(span, false)).toBe(15 * M);
    expect(keyStep(span, true)).toBe(H);
    expect(keyStep({ from: 0, to: H }, false)).toBe(M);
  });
  it("nudges one end, pans the band, and goes to the bounds on Home/End", () => {
    expect(keyed("start", "ArrowLeft", base, span, 15 * M)).toEqual({
      from: 6 * H - 15 * M,
      to: 8 * H,
    });
    expect(keyed("end", "ArrowRight", base, span, 15 * M)).toEqual({
      from: 6 * H,
      to: 8 * H + 15 * M,
    });
    expect(keyed("band", "ArrowRight", base, span, 15 * M)).toEqual({
      from: 6 * H + 15 * M,
      to: 8 * H + 15 * M,
    });
    expect(keyed("start", "Home", base, span, 15 * M)).toEqual({ from: 0, to: 8 * H });
    expect(keyed("band", "End", base, span, 15 * M)).toEqual({ from: 22 * H, to: 24 * H });
    expect(keyed("start", "Tab", base, span, 15 * M)).toBeNull();
  });
  it("words the range for the live region", () => {
    const at = (iso: string) => Date.parse(iso);
    expect(rangeText({ from: at("2026-11-14T03:10:00Z"), to: at("2026-11-14T04:40:00Z") })).toBe(
      "Range 11-14 03:10Z–04:40Z",
    );
  });
});
