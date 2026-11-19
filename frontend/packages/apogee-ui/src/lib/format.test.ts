import { describe, expect, it } from "vite-plus/test";
import {
  formatAbsolute,
  formatCount,
  formatCountdown,
  formatDuration,
  initials,
  plural,
} from "./format.ts";

const at = new Date("2026-10-23T02:41:17Z");

describe("format", () => {
  it("formats absolute UTC with Z", () => {
    expect(formatAbsolute(at)).toBe("2026-10-23 02:41:17Z");
  });

  it("uses U+2212 for countdowns and + for elapsed", () => {
    expect(formatCountdown(new Date("2026-10-23T02:45:29Z"), at)).toBe("T−00:04:12");
    expect(formatCountdown(new Date("2026-10-23T02:34:36Z"), at)).toBe("T+00:06:41");
    // §4: past a day, days then a clock that never exceeds 23 h (qa saw T−99:28:39).
    expect(
      formatCountdown(new Date(at.getTime() + (4 * 86_400 + 3 * 3600 + 28 * 60 + 39) * 1000), at),
    ).toBe("T−4d 03:28:39");
  });

  it("formats durations, counts and plurals", () => {
    expect(formatDuration(552)).toBe("9m 12s");
    expect(formatDuration(20_400)).toBe("5h 40m");
    expect(formatCount(-4812)).toBe("−4,812");
    expect(plural(1, "target")).toBe("1 target");
    expect(plural(2, "target")).toBe("2 targets");
  });

  it("derives initials", () => {
    expect(initials("Donovan Rost")).toBe("DR");
    expect(initials("admin@example.com")).toBe("AD");
  });
});
