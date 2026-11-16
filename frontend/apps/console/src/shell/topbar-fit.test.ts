import { describe, expect, it } from "vite-plus/test";
import { nextLevel, TopBarLevel } from "./topbar-fit.ts";

describe("top bar give-way step (ux IA §Top bar, f144e8fab)", () => {
  it("gives way one step while it overflows, up to the wrap", () => {
    expect(nextLevel({ level: 0, overflow: true, width: 1100, need: [] })).toBe(1);
    expect(nextLevel({ level: TopBarLevel.wrap, overflow: true, width: 800, need: [] })).toBe(
      TopBarLevel.wrap,
    );
  });
  it("steps back only when the bar is as wide as the content that overflowed", () => {
    expect(nextLevel({ level: 2, overflow: false, width: 1300, need: [1400, 1350] })).toBe(2);
    expect(nextLevel({ level: 2, overflow: false, width: 1360, need: [1400, 1350] })).toBe(1);
    expect(nextLevel({ level: 0, overflow: false, width: 2000, need: [] })).toBe(0);
  });
});

/**
 * A model of the bar: content width per level (qa's 1100 Setup: 1358px with the posture compact
 * and the query at 160) and the fit loop as useTopBarFit runs it. The account and UTC are the
 * bar's last items, so 'never clipped' means content ≤ width, or the wrap.
 */
describe("the bar settles without flapping, and nothing is clipped (lead, qa)", () => {
  // Savings per step, roughly from qa's shots: posture 250, brand 110, crumb 150, query 110, clocks 120.
  const content = [1608, 1358, 1248, 1098, 988, 868];
  function settle(width: number) {
    let level = 0;
    const need: number[] = [];
    const seen: number[] = [];
    const overflow = (l: number) => l < TopBarLevel.wrap && (content[l] ?? 0) > width;
    for (let i = 0; i < 20; i++) {
      const now = level;
      const next = nextLevel({ level: now, overflow: overflow(now), width, need });
      if (next > now) need[now] = content[now] ?? 0;
      level = next;
      if (next < now && overflow(next)) {
        need[next] = content[next] ?? 0;
        level = now;
      }
      seen.push(level);
    }
    return seen;
  }
  it("settles at every width from 768 to 2200, and the last level fits or wraps", () => {
    for (let width = 768; width <= 2200; width += 8) {
      const seen = settle(width);
      const last = seen.at(-1) ?? 0;
      expect(seen.slice(-10).every((l) => l === last)).toBe(true);
      expect(last === TopBarLevel.wrap || (content[last] ?? 0) <= width).toBe(true);
    }
  });
  it("matches ux's arithmetic: 1100 needs the first three steps; 800 wraps", () => {
    expect(settle(1100).at(-1)).toBe(TopBarLevel.crumbMission);
    expect(settle(1280).at(-1)).toBe(TopBarLevel.brandMark);
    expect(settle(800).at(-1)).toBe(TopBarLevel.wrap);
    expect(settle(1700).at(-1)).toBe(0);
  });
});
