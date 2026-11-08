import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { fleetReader } from "./api.ts";
import { fleetOf, spacecraftRow } from "./fixtures.ts";
import { fitCell, layoutMatrix } from "./matrix.ts";
import { throttle } from "./useFleet.ts";

const range = (from: number, to: number) =>
  Array.from({ length: to - from + 1 }, (_, i) => from + i);

describe("fleetReader", () => {
  it("accepts a consistent snapshot", () => {
    const fleet = fleetOf(range(1, 3).map((scid) => spacecraftRow(scid)));
    expect(decode(fleetReader, fleet).ok).toBe(true);
  });

  it("rejects counts that don't partition the fleet", () => {
    const fleet = fleetOf([spacecraftRow(1)]);
    const result = decode(fleetReader, { ...fleet, counts: { ...fleet.counts, nominal: 0 } });
    expect(result.ok).toBe(false);
  });

  it("rejects a total that doesn't match the rows", () => {
    const fleet = fleetOf([spacecraftRow(1)]);
    const result = decode(fleetReader, { ...fleet, spacecraft: [] });
    expect(result.ok).toBe(false);
  });

  it("rejects an unknown state", () => {
    const fleet = fleetOf([spacecraftRow(1)]);
    const row = { ...spacecraftRow(1), state: "green" };
    expect(decode(fleetReader, { ...fleet, spacecraft: [row] }).ok).toBe(false);
  });

  it("keeps text values as text", () => {
    const point = {
      point_id: "HK.mode",
      point_name: "MODE",
      value: "SAFE",
      limit_state: "critical",
      raw_limit_state: null,
      received_at: null,
    } as const;
    const fleet = fleetOf([spacecraftRow(1, { state: "critical", worst_point: point })]);
    const result = decode(fleetReader, fleet);
    expect(result.ok && result.value.spacecraft[0]?.worst_point?.value).toBe("SAFE");
  });
});

describe("layoutMatrix (U8)", () => {
  it("uses rows = planes and columns = max slot", () => {
    const layout = layoutMatrix(range(1, 500).map((scid) => spacecraftRow(scid)));
    expect(layout.mode).toBe("planes");
    expect(layout.columns).toBe(25);
    expect(layout.rows).toHaveLength(20);
    expect(layout.rows[0]?.label).toBe("P01");
    expect(layout.rows[1]?.cells[0]?.scid).toBe(26);
  });

  it("puts spacecraft without a plane in a trailing — row", () => {
    const rows = [spacecraftRow(1), spacecraftRow(2), spacecraftRow(99, { plane: null })];
    const layout = layoutMatrix(rows);
    expect(layout.rows.at(-1)?.label).toBe("—");
    expect(layout.rows.at(-1)?.cells[0]?.scid).toBe(99);
  });

  it("leaves empty slots and places unslotted spacecraft in free cells", () => {
    const rows = [
      spacecraftRow(1, { slot: 3 }),
      spacecraftRow(2, { slot: null }),
      spacecraftRow(3, { slot: 3 }),
    ];
    const cells = layoutMatrix(rows).rows[0]?.cells ?? [];
    expect(cells.map((sc) => sc?.scid ?? null)).toEqual([2, 3, 1]);
  });

  it("falls back to a flat SCID grid, 50 per row, without plane metadata", () => {
    const rows = range(1, 120).map((scid) => spacecraftRow(scid, { plane: null, slot: null }));
    const layout = layoutMatrix(rows);
    expect(layout.mode).toBe("flat");
    expect(layout.columns).toBe(50);
    expect(layout.rows.map((row) => row.label)).toEqual(["001–050", "051–100", "101–120"]);
  });
});

describe("throttle", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("runs at once, then keeps one trailing call inside the gap", () => {
    const run = vi.fn();
    const t = throttle(run, 2000);
    t.call();
    expect(run).toHaveBeenCalledTimes(1);
    t.call();
    t.call();
    expect(run).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(2000);
    expect(run).toHaveBeenCalledTimes(2);
  });

  it("drops a scheduled call when cancelled", () => {
    const run = vi.fn();
    const t = throttle(run, 2000);
    t.call();
    t.call();
    t.cancel();
    vi.advanceTimersByTime(5000);
    expect(run).toHaveBeenCalledTimes(1);
  });
});

describe("fitCell (ux: clamp(8px, available / planes, 16px))", () => {
  it("fills the height between 8 and 16px", () => {
    expect(fitCell(1000, 240, 20, 25)).toEqual({ cell: 10, overflows: false });
  });

  it("caps at 16px when there is room", () => {
    expect(fitCell(1000, 1000, 20, 25).cell).toBe(16);
  });

  it("keeps 8px cells and reports overflow when the box is too small", () => {
    expect(fitCell(1000, 100, 20, 25)).toEqual({ cell: 8, overflows: true });
  });

  it("respects width when no height is given", () => {
    expect(fitCell(44 + 25 * 12, null, 20, 25).cell).toBe(10);
  });
});
