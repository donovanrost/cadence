import { effectScope, nextTick } from "vue";
import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { RETRY_OPEN, retryText, useRetryAfter, waitSentence } from "./retry-after.ts";

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

  it("says the wait once as an alert, and once politely when it's over (ux #276)", async () => {
    const scope = effectScope();
    const r = scope.run(() => useRetryAfter());
    if (!r) throw new Error("no scope");
    r.block(120);
    await nextTick();
    expect(r.said.value).toEqual({
      alert: "Too many attempts. Try again in 2 minutes.",
      status: "",
    });
    vi.advanceTimersByTime(60_000);
    await nextTick();
    // The countdown moved on, but nothing new is said.
    expect(r.text.value).toBe("Too many attempts. Try again in 1:00.");
    expect(r.said.value.alert).toBe("Too many attempts. Try again in 2 minutes.");
    vi.advanceTimersByTime(60_000);
    await nextTick();
    expect(r.said.value).toEqual({ alert: "", status: RETRY_OPEN });
    scope.stop();
  });

  it("puts the wait in plain words: seconds under a minute, else whole minutes rounded up", () => {
    expect(waitSentence(1)).toBe("Too many attempts. Try again in 1 second.");
    expect(waitSentence(42)).toBe("Too many attempts. Try again in 42 seconds.");
    expect(waitSentence(60)).toBe("Too many attempts. Try again in 1 minute.");
    expect(waitSentence(61)).toBe("Too many attempts. Try again in 2 minutes.");
  });
});
