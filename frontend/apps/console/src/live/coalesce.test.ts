import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { coalesce } from "./coalesce.ts";

describe("coalesce", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("runs the first call at once and collapses a burst into one trailing run", () => {
    const fn = vi.fn();
    const { call } = coalesce(fn, 1000);
    call();
    expect(fn).toHaveBeenCalledTimes(1);
    for (let i = 0; i < 20; i++) call();
    expect(fn).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(1000);
    expect(fn).toHaveBeenCalledTimes(2);
    vi.advanceTimersByTime(5000);
    expect(fn).toHaveBeenCalledTimes(2);
  });

  it("a quiet window ends without a trailing run; flush runs now", () => {
    const fn = vi.fn();
    const { call, flush } = coalesce(fn, 1000);
    call();
    vi.advanceTimersByTime(1000);
    expect(fn).toHaveBeenCalledTimes(1);
    call();
    flush();
    expect(fn).toHaveBeenCalledTimes(3);
  });
});
