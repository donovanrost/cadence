import { describe, expect, it } from "vite-plus/test";
import { extent, hourTicks, neighbour, position, type GanttBar, type GanttRow } from "./model.ts";

const H = 3_600_000;
const day = { from: 0, to: 24 * H };

describe("gantt model", () => {
  it("positions and clamps", () => {
    expect(position(day, 12 * H)).toBe(50);
    expect(position(day, -H)).toBe(0);
    expect(extent(day, 0, 0).width).toBe(0.25);
  });

  it("labels every 2 hours across a day", () => {
    const ticks = hourTicks(day);
    expect(ticks).toHaveLength(25);
    expect(ticks.filter((t) => t.major).map((t) => t.t / H)).toEqual([
      0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24,
    ]);
  });

  it("moves through bars by row and by nearest time across rows", () => {
    const rows: GanttRow[] = [
      { id: "a", label: "A" },
      { id: "b", label: "B" },
    ];
    const bar = (id: string, rowId: string, from: number): GanttBar => ({
      id,
      rowId,
      from,
      to: from + H / 6,
      kind: "own",
      description: id,
    });
    const bars = [
      bar("a1", "a", H),
      bar("a2", "a", 5 * H),
      bar("b1", "b", 2 * H),
      bar("b2", "b", 6 * H),
    ];
    expect(neighbour(rows, bars, "a1", "ArrowRight")).toBe("a2");
    expect(neighbour(rows, bars, "a1", "ArrowLeft")).toBeNull();
    expect(neighbour(rows, bars, "a2", "ArrowDown")).toBe("b2");
    expect(neighbour(rows, bars, "b1", "ArrowUp")).toBe("a1");
  });
});
