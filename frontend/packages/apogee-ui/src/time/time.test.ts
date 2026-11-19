import { describe, expect, it } from "vite-plus/test";
import { formatDayTime, formatMet, formatRelative } from "../lib/format.ts";
import { monthGrid, withDate } from "./calendar.ts";
import { parseTime } from "./parse.ts";

const NOW = Date.UTC(2026, 9, 23, 2, 21, 30);

describe("parseTime", () => {
  it("reads now and relative offsets", () => {
    expect(parseTime("now", NOW)).toBe(NOW);
    expect(parseTime("now+2h", NOW)).toBe(NOW + 7_200_000);
    expect(parseTime("T+38m", NOW)).toBe(NOW + 2_280_000);
    expect(parseTime("T−90s", NOW)).toBe(NOW - 90_000);
  });

  it("reads absolute UTC times with or without seconds and Z", () => {
    expect(parseTime("2026-10-24 06:00", NOW)).toBe(Date.UTC(2026, 9, 24, 6, 0, 0));
    expect(parseTime("2026-10-24T06:00:30Z", NOW)).toBe(Date.UTC(2026, 9, 24, 6, 0, 30));
  });

  it("rejects what it can't read, including calendar rollovers", () => {
    expect(parseTime("tomorrow", NOW)).toBeNull();
    expect(parseTime("2026-02-31 06:00", NOW)).toBeNull();
    expect(parseTime("2026-10-24 25:00", NOW)).toBeNull();
    expect(parseTime("", NOW)).toBeNull();
  });
});

describe("calendar", () => {
  it("builds a Monday-first 6-week grid", () => {
    const grid = monthGrid(2026, 9);
    expect(grid).toHaveLength(42);
    expect(grid[0]?.key).toBe("2026-09-28");
    expect(grid.find((d) => d.inMonth)?.key).toBe("2026-10-01");
  });

  it("keeps the time of day when changing the date", () => {
    expect(withDate(Date.UTC(2026, 9, 23, 2, 59, 40), 2026, 10, 2)).toBe(
      Date.UTC(2026, 10, 2, 2, 59, 40),
    );
  });
});

describe("time formats", () => {
  it("formats day-time, relative with days, and MET", () => {
    const at = new Date(Date.UTC(2026, 9, 23, 2, 59, 40));
    expect(formatDayTime(at)).toBe("10-23 02:59:40Z");
    expect(formatRelative(at, new Date(NOW))).toBe("T−00:38:10");
    expect(formatRelative(new Date(NOW + 93_600_000), new Date(NOW))).toBe("T−1d 02:00:00");
    expect(formatMet(new Date(NOW), new Date(NOW - 86_400_000 - 3_661_000))).toBe("MET 1:01:01:01");
  });
});

describe("parseTime dates", () => {
  it("reads a bare date as midnight UTC and rejects rollovers", () => {
    expect(parseTime("2026-11-10", NOW)).toBe(Date.UTC(2026, 10, 10));
    expect(parseTime("2026-02-30", NOW)).toBeNull();
  });
});
