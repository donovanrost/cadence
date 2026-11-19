import { effectScope } from "vue";
import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { retryText, useRetryAfter } from "./retry-after.ts";

describe("429 attempt limit (Auth.md)", () => {
  beforeEach(() => vi.useFakeTimers({ now: 0 }));
  afterEach(() => vi.useRealTimers());

  it("says the wait in m:ss, rounding up", () => {
    expect(retryText(42)).toBe("Too many attempts. Try again in 0:42.");
    expect(retryText(61.2)).toBe("Too many attempts. Try again in 1:02.");
  });

  it("counts down live and lets the form work again at zero", () => {
    const scope = effectScope();
    const r = scope.run(() => useRetryAfter());
    if (!r) throw new Error("no scope");
    r.block(3);
    expect(r.blocked.value).toBe(true);
    expect(r.text.value).toBe("Too many attempts. Try again in 0:03.");
    vi.advanceTimersByTime(1000);
    expect(r.text.value).toBe("Too many attempts. Try again in 0:02.");
    vi.advanceTimersByTime(2000);
    expect(r.blocked.value).toBe(false);
    expect(r.text.value).toBeNull();
    scope.stop();
  });
});
