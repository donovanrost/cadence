import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { computed, nextTick, ref, watch } from "vue";
import { floorTo } from "./coarseClock.ts";
import { decode, pointId as pointIdReader } from "@/api/index.ts";
import { fleetReader } from "./api.ts";
import { fleetOf, spacecraftRow } from "./fixtures.ts";
import { fitCell, fitMatrix, layoutMatrix, splitRows } from "./matrix.ts";
import { throttle } from "./useFleet.ts";
import {
  byStateThenName,
  describeFilter,
  filterQuery,
  matches,
  NO_FILTER,
  parseFilter,
  nextContact,
} from "./filters.ts";
import { fleetSubset } from "./stats.ts";

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
      point_id: pointIdReader("HK.mode"),
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

describe("fitMatrix (U14)", () => {
  it("wraps rows into blocks when that gives larger cells", () => {
    // 20 planes x 25 slots in a wide, short box: one block would be 8px cells.
    const fit = fitMatrix(900, 180, 20, 25);
    expect(fit.blocks).toBe(2);
    expect(fit.cell).toBeGreaterThan(8);
  });

  it("wraps to stop overflowing even when the cell can't grow", () => {
    expect(fitMatrix(630, 180, 20, 25)).toMatchObject({ blocks: 2, overflows: false });
  });

  it("keeps one block when there is height to spare", () => {
    expect(fitMatrix(630, 1000, 20, 25)).toEqual({ cell: 16, overflows: false, blocks: 1 });
  });

  it("splits rows into consecutive groups", () => {
    expect(splitRows([1, 2, 3, 4, 5], 2)).toEqual([
      [1, 2, 3],
      [4, 5],
    ]);
  });
});

describe("fleet filters", () => {
  it("round-trips through the URL and keeps unrelated keys", () => {
    const filter = parseFilter({
      plane: "7",
      state: "critical,bogus,caution",
      q: " 31 ",
      view: "matrix",
    });
    expect(filter).toEqual({
      plane: 7,
      states: ["critical", "caution"],
      profile: null,
      contact: false,
      q: "31",
    });
    expect(parseFilter({ contact: "1" }).contact).toBe(true);
    expect(filterQuery({ ...NO_FILTER, contact: true }, {})).toEqual({ contact: "1" });
    expect(filterQuery(filter, { view: "matrix", plane: "3" })).toEqual({
      view: "matrix",
      plane: "7",
      state: "critical,caution",
      q: "31",
    });
    expect(filterQuery(NO_FILTER, { plane: "3", view: "matrix" })).toEqual({ view: "matrix" });
  });

  it("filters to in contact and says the next contact", () => {
    const now = new Date("2026-11-12T00:00:00Z");
    const live = spacecraftRow(1, { in_contact: true });
    const later = spacecraftRow(2, { in_contact: false, next_aos_at: "2026-11-12T00:38:00Z" });
    expect([live, later].filter((sc) => matches(sc, { ...NO_FILTER, contact: true }))).toEqual([
      live,
    ]);
    expect([
      nextContact(live, now),
      nextContact(later, now),
      nextContact(spacecraftRow(3), now),
    ]).toEqual(["In contact", "T−38m", null]);
  });

  it("matches plane, state, profile and name or SCID prefix", () => {
    const sc = spacecraftRow(312, { plane: 7, state: "critical" });
    expect(matches(sc, { ...NO_FILTER, plane: 7, states: ["critical"] })).toBe(true);
    expect(matches(sc, { ...NO_FILTER, q: "31" })).toBe(true);
    expect(matches(sc, { ...NO_FILTER, q: "99" })).toBe(false);
    expect(matches(sc, { ...NO_FILTER, q: "earendil-312" })).toBe(true);
    expect(matches(sc, { ...NO_FILTER, profile: "other" })).toBe(false);
  });

  it("describes the filter and sorts by state precedence then name", () => {
    expect(describeFilter({ ...NO_FILTER, plane: 7, states: ["critical"] }, (id) => id)).toBe(
      "plane 07 + critical",
    );
    const rows = [
      spacecraftRow(2),
      spacecraftRow(1, { state: "stale" }),
      spacecraftRow(3, { state: "critical" }),
    ];
    expect([...rows].sort(byStateThenName).map((sc) => sc.scid)).toEqual([3, 1, 2]);
  });

  it("recomputes counts for a subset", () => {
    const fleet = fleetOf([spacecraftRow(1), spacecraftRow(2, { state: "critical" })]);
    const subset = fleetSubset(
      fleet,
      fleet.spacecraft.filter((sc) => sc.state === "critical"),
    );
    expect(subset.counts).toMatchObject({ total: 1, critical: 1, nominal: 0 });
  });
});

describe("coarse clock (Fleet past 200 rows)", () => {
  it("floors to the step, so values inside one step are equal", () => {
    expect(floorTo(1_234_567, 10_000)).toBe(1_230_000);
    expect(floorTo(1_239_999, 10_000)).toBe(floorTo(1_230_001, 10_000));
  });
  it("a number computed doesn't notify within a step", async () => {
    const t = ref(1_230_000);
    const coarse = computed(() => floorTo(t.value, 10_000));
    let runs = 0;
    watch(coarse, () => (runs += 1));
    t.value = 1_235_000;
    await nextTick();
    t.value = 1_241_000;
    await nextTick();
    expect(runs).toBe(1);
  });
});
